# 阶段零设计文档 · 汇编种子编译器（flint-seed 0.0.1）

项目代号暂定 **Flint**（正式语言名待定，改名成本在规格冻结前近似为零：仅需同步 build.ps1 与文件后缀）。
本文件只描述阶段零：一个**纯 x86-64 汇编（NASM）手写**、不依赖任何高级语言与外部链接器的种子编译器。
它要证明三件事：不借链接器也能产出可加载的 PE32+；前端（词法/语法/诊断）在汇编下可工程化；为新语言源码编译出原生程序提供最小闭环。

---

## 一、阶段目标与能力边界

阶段零支持的最小语言子集（同时也是新语言的第一块地基，不是一次性玩具）：

- 顶层只能有 `fn` 定义；必须存在 `fn main() -> i64`。
- 类型只有 `i64`（参数、返回、`let` 注解全部只接受 `i64`，其余报“阶段 0 仅支持 i64 类型”）。
- 语句：`let 名字: i64 = 表达式;`、`return 表达式;`（`return;` 等价返回 0）、表达式语句。
- 表达式：十进制 / `0x` / `0b` 整数字面量（允许 `_` 分隔）、标识符、函数调用、`+ - * / %`、一元负号、括号。
- 内建 `print(x)`：十进制输出 + 换行，仅接受 1 个实参。
- 函数最多 4 个参数（对应 Win64 的 rcx/rdx/r8/r9）。
- 注释：`//` 行注释、可嵌套 `/* */` 块注释；字符串字面量明确拒绝（阶段零不实现）。

显式不支持（不是遗漏，是边界）：控制流（if/while/for）、字符串、结构体/数组/指针、类型别名、泛型、模式匹配、
宏、内联汇编、FFI 声明、多文件模块、ELF/裸机目标。以上全部在阶段一之后按路线图逐项引入。

---

## 二、总体架构与源文件划分

单节镜像、全部代码与数据同处一个 `.text`（RWX），所有内部引用为 RIP 相对，**不生成重定位项**（`Characteristics = 0x0023`，
含 `RELOCS_STRIPPED`），`DllCharacteristics = 0`（无 ASLR、无 NX）。这是阶段零的关键取舍：用“位置无关写法 + 固定 ImageBase”
换掉“必须自己实现重定位表”的复杂度，阶段七再拆分节权限并生成 `.reloc`。

源文件（`src/seed/`，由 `seed.asm` 顺序 `%include`，共享一个 `sec_start` 基准）：

| 文件 | 职责 |
| --- | --- |
| `defines.inc` | 常量、结构体字段偏移、Token/AST kind 枚举、内部调用约定、上限、PE/Win32 常量 |
| `data.asm` | 节起点 `sec_start`、IAT 与导入表、全部运行时全局、优先级表、Token 名称表、诊断文本、静态缓冲 |
| `memory.asm` | `arena_alloc`：VirtualAlloc 1 MiB 块 bump 分配，16 字节对齐，永不回收 |
| `diag.asm` | UTF-8 输出、行定位、源码片段与插入符、`diag_at` / `fatal` / `fatal_win` / `exit_now` |
| `fileio.asm` | `file_read`（源文件，8 MiB 上限）/ `file_write`（产物） |
| `lexer.asm` | 空白与注释、标识符与关键字、整数字面量、标点、Token 发射 |
| `parser.asm` | 递归下降 + Pratt 表达式、AST 构造、语句/参数/函数三级错误同步 |
| `codegen1.asm` | 节缓冲、机器码编码器、Fixup 表、函数表、局部表、名字工具、`print` 桩 |
| `codegen2.asm` | 函数收集与语义子集检查、表达式/语句/函数生成、入口 stub、回填、PE 头构造与落盘 |
| `main.asm` | 命令行解析（UTF-16 → UTF-8）、`--version` / `--tokens` / 编译分发、入口点 |

构建采用**两次汇编**：NASM 的 `-f bin` 无法在汇编期知道“节最终多长”，而 PE 头必须写死 `SizeOfRawData`。

1. `nasm -DMEASURE_PASS` 跳过 PE 头，量出节长度（末尾 `align 0x200` 保证已按文件对齐）；
2. `nasm -DSEC_RAW=<实测长度>` 带上头，产出 `build\flint-seed.exe`。

`SEC_IMAGE_SIZE = (SEC_RVA + SEC_RAW + 0xFFF) & ~0xFFF` 由命令行宏参与计算，头内 `SizeOfImage` 与之自洽。
这不是“绕不过去的黑魔法”，而是 bin 输出格式的硬约束；阶段七自研链接器后即可去掉两遍汇编。

---

## 三、关键数据结构（选型、偏移、代价）

### Token（32 字节）

| 偏移 | 字段 | 说明 |
| --- | --- | --- |
| 0 | `TK_KIND` (u32) | kind 枚举，20 种 |
| 4 | `TK_LINE` (u32) | 1 基行号 |
| 8 | `TK_COL` (u32) | 1 基列号（Tab 按 4 列展开后的显示列） |
| 12 | `TK_START` (u32) | 源码字节偏移（含） |
| 16 | `TK_END` (u32) | 源码字节偏移（不含） |
| 20 | `TK_PAD` (u32) | 显式补 0，禁止出现“qword 读 dword 带出相邻字段”的隐性 bug |
| 24 | `TK_IVAL` (i64) | 整数字面量值 |

选型理由：32 字节是 2 的幂，索引即 `index << 5`，缓存行对齐友好；`PAD` 与 `IVAL` 的 8 字节对齐让
“值”可以被单条 `mov rcx,[tok+24]` 读取，而所有 32 位字段必须用 32 位指令访问（本轮已因此修掉 6 处真实 bug）。
代价：每 Token 32 B，上限 65536 → 2 MiB 固定占用；错误恢复与注释保留都不额外分配。

### AST 节点（56 字节，arena 分配后按 16 对齐实际占 64）

`ND_KIND(0,u32) / ND_LINE(4,u32) / ND_COL(8,u32) / ND_PAD(12,u32) / ND_NEXT(16,qword) / ND_A(24,qword) / ND_B(32,qword) / ND_C(40,qword) / ND_VAL(48,qword)`

- 兄弟链用 `ND_NEXT`，子节点用固定三槽 `A/B/C`，避免“万能 child 数组”带来的间接层与装箱。
- 节点不携带类型字段：阶段零只有 i64，类型检查是语法级白名单；阶段四引入类型系统时在此处扩展（需评估节点尺寸膨胀与 arena 压力）。
- 全部节点一次性 arena 分配、不释放：编译结束即进程退出，回收无意义；阶段十（自举后做 LSP/增量编译）必须换成可回收的区域分配器，这是明确的后期成本。

### 函数表项（48 字节）

`FN_NAME(0,qword) / FN_LEN(8,u32) / FN_ARITY(12,u32) / FN_OFF(16,u32) / FN_NODE(24,qword) / FN_NEXT(32,qword) / FN_FLAGS(40,u32)`

- 名字只存 `源码指针 + 长度`，不做字符串拷贝；比较是长度先行 + 逐字节。
- 链表头插（`fn_head`），顺序不敏感；查找 O(n)，阶段零函数数量小，暂不上哈希。函数数量上千时需换成开放寻址哈希（评估点已标注）。
- `FN_OFF` 在生成阶段回填为节内偏移，供入口 stub 与 Fixup 解析使用。

### 局部变量表项（24 字节）

`LV_NAME(0,qword) / LV_LEN(8,u32) / LV_SLOT(12,u32) / LV_NEXT(16,qword)`
槽位从 0 递增，实际地址 `[rbp - 8*(slot+1)]`；参数先占 0..arity-1，`let` 依次追加；`next_slot` 决定帧大小。

### Fixup 表项（40 字节）

`FX_OFF(0,u32) / FX_PAD(4,u32) / FX_NAME(8,qword) / FX_LEN(16,u32) / FX_LINE(20,u32) / FX_COL(24,u32) / FX_SRCOFF(28,u32) / FX_NEXT(32,qword)`

- 调用点统一先写 `E8 + 00000000` 并登记 fixup，全部函数生成完后按名字回填 `rel32`；未命中报“未定义的函数”，带行列与源码片段。
- 存 `行/列/字节偏移` 而不是 Token 指针：Token 数组在阶段零不回收，但阶段十之后可能被压缩/重排，存位置信息更稳。

### 固定上限

`SRC_MAX = 8 MiB`、`MAX_TOKENS = 65536`、`SEC_BYTES = 8 MiB`、`DIAG_MAX = 32` 条错误、命令行参数最多 8 个、路径缓冲 2 KiB。
全部是“编译期常量 + 溢出即诊断”的硬边界：宁可明确失败，不做隐式扩容。

---

## 四、内存分配策略

- 统一 `arena_alloc(size)`：16 字节对齐，块不足时 `VirtualAlloc(1 MiB, MEM_COMMIT|MEM_RESERVE, PAGE_READWRITE)`；
  单次请求超过 1 MiB 时按请求向上取整到 4 KiB 页。
- 分配对象：Token 数组（2 MiB）、AST 节点、函数/局部/Fixup 记录、生成节缓冲（8 MiB）、源文件缓冲（8 MiB）。
- 不回收、不碎片整理。代价：一次编译的峰值常驻 ≈ 20 MiB 级别，且进程退出才释放；收益：分配路径只有 6 条指令，无锁、无元数据。
- 失败路径唯一：`m_oom` → `fatal` 退出码 3。没有“分配失败返回空指针再分支”的分散判断。

---

## 五、调用约定与栈帧

种子自身使用内部约定（仅用于种子，不是正式 FlintCall）：参数 `rdi, rsi, rdx, rcx, r8, r9`，返回 `rax`，
保留 `rbx, rbp, r12-r15`。每个函数 `push rbp; mov rbp,rsp; sub rsp,N`，`N` 为 16 的倍数且 ≥ 0x30
（Win32 调用需要 32 字节影子空间 + 第 5 参数槽），保证所有 `call [__imp_*]` 点 `rsp % 16 == 0`。

生成物遵循 **Microsoft x64 调用约定**：参数 `rcx,rdx,r8,r9`，返回 `rax`，`rbp` 帧，影子空间 32 字节，
调用点 16 字节对齐（表达式栈机用 `cg_depth` 奇偶插入 `sub rsp,8 / add rsp,8`）。
两套约定在阶段零是**刻意分离**的：种子自身不对外暴露 ABI，避免过早冻结 FlintCall；阶段八再设计正式 ABI 与 System V 变体。

---

## 六、前端设计要点

### 词法

- Token 全枚举 20 种：`EOF, IDENT, INT, fn, let, return, ( ) { } , : ; -> = + - * / %`。
- 列号按“显示列”维护：Tab 跳到下一个 4 的倍数 +1，换行复位为 1；UTF-8 续字节在片段与插入符计算中宽度为 0。
- 数字：`0x`/`0b` 前缀先消费 2 字节再进入公共累加；累加用 `acc = acc*base + digit`，`acc < 0` 判溢出（> i64 上限）；
  下划线允许出现在任意位置（含首尾），不产生空 token 时按“缺少有效数字”报错。
- 块注释深度计数，未闭合时**直接把扫描位置推到 EOF**再报错，避免把后续字符误报为无效字符（本轮修复项）。
- 词法错误不终止：记录后按单字节推进继续扫描，一次编译可报多条（上限 32）。

### 语法

- `parse_expr(min_bp)` 为 Pratt 循环；优先级只在 `prec_table`（按 Token kind 索引的 20 字节表）里定义，`+/-=10`、`*/%=20`，左结合；
  新增运算符只改这张表。`parse_prefix` 处理字面量、标识符/调用、括号、一元负号；遇到非法前缀产生“占位字面量 0”节点并推进，保证后续不雪崩。
- 泛型尖括号歧义在阶段零不存在（无泛型），阶段三再引入“先尝试类型实参再看 `>`”的受限回溯；这一点已在路线图风险项中登记。
- 错误同步三级：语句边界（`;`、`}`、`fn`）、参数边界（`,`、`)`、`{`）、函数边界（下一个 `fn`）。
- 关键坑：`parse_prefix` 内构造节点后若再调用 `adv`，`rax` 会被 `ps_cur` 覆盖——阶段零必须“先存节点指针再推进”（本轮真实 bug，已修）。

### 语义子集检查（不是完整类型检查）

函数重名、参数重名、参数超过 4 个、`print` 保留名、局部重名（阶段零不允许遮蔽）、未定义标识符、
未定义函数、实参数量不匹配、函数名当作值使用、缺少 `main`。
检查分布在 `collect_functions`（收集期）与生成期两处；错误全部走 `diag_tok/diag_name`，带 `'名字'` 与定位。

---

## 七、代码生成

- 表达式采用**栈机**：左值 `push rax`，右值进 `rcx`，`pop rax` 后 `add/sub/imul`；除法/取模 `cqo; idiv rcx`，取模取 `rdx`。
  代价：每层表达式两次栈访问，性能不如寄存器线性扫描（Sethi-Ullman）；收益：编码器极简、正确性可穷举验证。
  阶段六引入寄存器分配（线性扫描 + 溢出槽）时，这层会被整体替换。
- 函数帧：`frame = align16(8*(arity + let_count) + 32)`；参数入栈 `mov [rbp-8*(i+1)], rcx/rdx/r8/r9`；
  `return` 内联 `mov rsp,rbp; pop rbp; ret`；控制流落空时返回 0（`xor eax,eax` 编码为 `31 C0`）。
- 调用：实参左到右求值并 push，逆序 pop 进 `rcx/rdx/r8/r9`，按 `cg_depth` 奇偶补 8 字节对齐，再 `E8 rel32`。
- `print` 桩：自实现十进制（负号、`div 10`、32 字节栈缓冲），两次 `WriteFile`（数字 + 换行）；
  只使用易失寄存器 `r10/r11`，帧 0x70，`[rbp-0x38]` 存 `lpNumberOfBytesWritten`，`[rsp+0x20]` 置 `lpOverlapped = NULL`。
- 入口 stub：`sub rsp,0x28; GetStdHandle(-11); mov [g_hstdout],rax; call main; mov rcx,rax; ExitProcess; int3`。

编码器全部手写字节：`cb_b/cb_w/cb_d/cb_q`、`emit_rm_disp`（REX.W + ModR/M，base 固定 rbp，disp8/disp32 自动选择）、
`emit_rip`（RIP 相对，按是否需要 REX.W 选择 6/7 字节）、`emit_imm64`（`48 B8 imm64`）、`patch_rel32`。
**编码器不得在 `cb_*` 调用之后继续使用 `rdi/rax/rcx` 中的入参**——`cb_b` 会覆盖它们（本轮真实 bug：`emit_imm64` 把 `rdi` 当值用，结果写进了节缓冲指针）。

---

## 八、PE32+ 布局（种子自身与生成物同一套常量）

| 项 | 值 |
| --- | --- |
| 文件头 | DOS 头 64 字节，`e_lfanew = 0x40` |
| COFF | Machine `0x8664`，节数 1，`SizeOfOptionalHeader = 0xF0`，Characteristics `0x0023` |
| 可选头 | Magic `0x20B`，ImageBase `0x140000000`，SectionAlignment `0x1000`，FileAlignment `0x200`，Subsystem 3 (CUI) |
| 节表 | `0x148` 起：`.text`，VirtualSize / VirtualAddress `0x1000` / SizeOfRawData / PointerToRawData `0x200` |
| 节特征 | `0xE0000060`（RWX + CODE + MEM_EXECUTE + MEM_READ + MEM_WRITE） |
| 导入目录 | 1 个描述符（40 字节），`OriginalFirstThunk = 0`（以 FirstThunk 同时充当 INT/IAT） |

种子自身导入 kernel32 的 12 个函数（stdout、文件、控制台代码页、VirtualAlloc、GetLastError）；
生成物只导入 3 个：`GetStdHandle`、`WriteFile`、`ExitProcess`。
IAT 项写成 `dq hint_X - sec_start + SEC_RVA`（**必须换算成 RVA**，写文件偏移会导致 `0xC0000139`，探针阶段已踩过）。
生成物节内布局固定为：数据（DLL 名 / 3 个 Hint&Name / IAT 4 槽 / 导入描述符 / `g_hstdout` / 换行字节）→ 16 字节对齐 →
`print` 桩 → 各函数 → 入口 stub。RVA 与文件偏移只差 `0x1000 - 0x200`，头部字段由运行期 `pe_build_header` 逐字段写入。

**代价（必须在阶段零就写清）**：单节 RWX + 无 ASLR + 无 NX 意味着产物在启用 DEP/CFG 的强加固环境里不可用，
也意味着“代码段可写”这一安全弱点；阶段七拆 `.text/.rdata/.data/.reloc` 并开启 ASLR/NX，同时自研重定位。
把这一取舍推迟到阶段七，是因为阶段零的目标是验证“无链接器产出可执行 PE”，不是产出可发布的加固二进制。

---

## 九、诊断格式与错误传播

```
<path>:<line>:<col>: error: <消息>['名字']
  <行号> | <源码行，Tab 展开，超 160 列截断>
        | <插入符>
```
- 路径是命令行传入的原始字符串（UTF-8），行列 1 基，插入符按显示列对齐。
- 编译期错误累计到 32 条后 `fatal` 终止；运行期（阶段零无运行时）只保留 Win32 失败路径，格式 `flint: <消息> (win32=<code>)`。
- 传播方式：函数返回 `rax` 表达结果，错误统一写入全局 `err_count` + 立即打印；调用方在阶段边界检查 `err_count` 决定是否继续。
  这是“诊断即副作用”的简化模型；阶段四引入 `Result` 与诊断对象后改为结构化返回，届时 `diag_at` 的签名会变，影响面集中在 parser/codegen。

---

## 十、构建、运行与验证

```
tools\nasm-2.16.03\nasm.exe -v          # 2.16.03
pwsh -NoProfile -File build.ps1          # 两遍汇编 → build\flint-seed.exe
build\flint-seed.exe --version
build\flint-seed.exe --tokens tests\p0\pos\ai_arith.fl
build\flint-seed.exe tests\p0\pos\ai_arith.fl build\ai_arith.exe
pwsh -NoProfile -File tests\run_p0.ps1   # 17/17
```

---

## 十一、性能瓶颈（阶段零实测口径）

- 词法：单遍扫描，每字节一次分支；1 万行源码在毫秒级，瓶颈在 `out_*` 诊断时的多次 `WriteFile`（每字符一次系统调用）。
  已知优化点：诊断聚类输出、批量拼接；阶段二做 REPL 时再改。
- 语法/生成：全链表查找（函数/局部/Fixup），O(n²) 风险出现在大量函数与大量调用点；阶段四/六换哈希与数组。
- PE 落盘：整节 `rep movsb` 到 `VirtualAlloc` 缓冲再一次 `WriteFile`，避免多次小块写。
- 峰值内存 ≈ 源 8 MiB + Token 2 MiB + 节 8 MiB + AST/表 ≈ 20–24 MiB，全部进程退出释放。

---

## 十二、设计锁死与长期代价（逐条登记）

| 决策 | 锁死程度 | 后期代价 / 替代方案 |
| --- | --- | --- |
| 单节 RWX、无重定位 | 中 | 阶段七拆节 + 自研 `.reloc`；生成器与 PE 构造需重写，前端不受影响 |
| 两遍汇编构建 | 低 | 阶段七有链接器后改为单遍 + 链接 |
| 仅 i64 | 低 | 阶段四类型系统上线时，AST 增加类型槽、代码生成按宽度分派 |
| 栈机表达式 | 中 | 阶段六寄存器分配替换，影响 `gen_expr` 与其编码器 |
| 链表符号表 | 低 | 阶段四换分层哈希（四命名空间），影响 `fn_find/local_find` 调用点 |
| arena 不回收 | 中 | 阶段十 LSP/增量编译必须改区域分配器；`arena_alloc` 是唯一入口，替换面可控 |
| 诊断即副作用（全局 `err_count`） | 中 | 阶段四结构化诊断，`diag_at` 签名变更，parser/codegen 全体调用点需同步 |
| Token 32B、AST 56B 固定尺寸 | 低-中 | 尺寸变更会破坏所有硬编码偏移；改尺寸必须同步 `defines.inc` 与全部汇编常量，建议冻结到阶段四再评估 |

---

## 十三、阶段零技术债（明确记录，不在本阶段修）

1. 生成物依赖 kernel32 的 3 个导入；阶段八用自实现 syscall 封装替换，确保裸机/内核场景零依赖。
2. 无调试信息、无行号映射表（崩溃无法回源码）；阶段九补 DWARF 与 `machine_offset → source` 映射。
3. `--tokens` 输出仅供调试，不是稳定接口。
4. 未实现常量折叠/死代码消除（阶段五）。
5. 错误恢复不保证“报错后 AST 可继续生成”，只保证不崩溃并继续扫描/解析。
6. 表达式临时值全走栈，深表达式会放大栈使用；阶段六一并解决。
7. `print` 是内建保留名，不是标准库函数；阶段八迁到标准库并保留兼容语法。
