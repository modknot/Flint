# Flint（代号）——自研系统级高级语言 · 编译器/运行时/工具链

> 语言正式名称待定，`Flint` 只是阶段零的工作代号。改名成本：`build.ps1`、文件后缀 `.fl`、文档标题三处。

目标：从零设计并实现一门全新的系统级高级语言，配套编译器、运行时、标准库与工具链；
起点是**纯 x86-64 汇编（NASM）手写的种子编译器**，不借 C/Rust/Python 作宿主，不使用 LLVM/GCC/Clang/ANTLR/Bison/Yacc/Tree-sitter
或任何语法生成器、第三方代码生成库、现成虚拟机框架。种子跑通后用新语言重写编译器，最终自举。

## 当前状态

阶段零（汇编种子编译器）已完成并通过验收：**17 / 17** 用例（正例 3、反例 14），详见 `docs\p0-acceptance.md`。

阶段二（自举准备）已完成第三段：

- 自举闸门 **13 / 13**：`p0`–`p9` 编译器底层能力，`p10` 种子编译整个 `src\flintc\flintc.fl`，`p11` 生成程序写文件，`p12` 生成程序读文件。
- `src\flintc\flintc.fl` v0.4 已识别标识符、关键字、整数、运算符，支持 `fn`、`let`、`return`、`if/else`、`while`、赋值、`+ - * / %`、比较和局部变量。
- 已支持多函数程序、函数参数、函数调用和递归；参数按栈传递，调用者清理实参，函数标签在所有函数生成后统一回填。
- `src\flintc\sample.fl` 现在包含 `add`、递归 `fact` 和 `main`；PE 在 Windows 退出 `20`，ELF 在 Linux 退出 `20`，证明参数、调用、递归和控制流真实可执行。
- 同一份 AST 代码生成结果可写出 **PE32+ / ELF64 / Mach-O 64** 三个目标文件；Mach-O 已通过文件类型校验为 `Mach-O 64-bit x86_64 executable`，尚未在真实 macOS 运行。
- 种子仍只负责把第一版 flintc 编译出来；三系统不是三份种子，而是 flintc 的三个后端模块。

自举下一段：flintc 补齐字符串、结构体、数组和命令行参数，最终用 flintc 编译 `src\flintc\flintc.fl` 自身。

阶段一（语言规格定稿）**草案已交付，未冻结**：

- `docs\p1-spec.md`：词法、EBNF、类型系统、表达式/语句语义、ABI、错误处理、内存模型与 UB 清单、特性代价表、与阶段零兼容性、10 项待决问题。
- `docs\p1-errors.md`：E1xxx–E9xxx 错误编号体系、消息模板、恢复策略、阶段零消息迁移表、实现约束与退出码。
- `tests\spec\examples\`：**46 份**规格示例（基础/函数/指针/复合类型/枚举与模式/泛型/错误处理/模块与 FFI/资源/汇编与 goto/编译期求值）。
- `tests\spec\manifest.csv`：逐例登记 `ok|cerr|rerr` 与期望（stdout 或错误码）。
- `tests\spec\check_examples.ps1`：数量、命名、头注释、manifest 覆盖自检（当前通过）。

冻结前提：§18 的 10 项待决问题逐条签字（整数溢出默认、未初始化声明、可见性命名、泛型值参数、goto 取舍、
`onexit` 在 panic 时的行为、内联汇编占位风格、`str` 索引 API、`erased` 泛型、正式名与关键字集合）。

阶段零能力：`i64` 类型、`let`/`return`/表达式语句、`+ - * / %`、一元负号、括号、十进制/十六进制/二进制字面量、
最多 4 参数的函数调用、内建 `print`、`//` 与可嵌套 `/* */` 注释；输出为可直接运行的 PE32+（Subsystem CUI）。
不支持：控制流、字符串、复合类型、指针、泛型、模式匹配、宏、FFI、内联汇编、ELF/裸机目标（按路线图引入）。

## 构建与使用

```powershell
# 需要 NASM 2.16.03：放到 tools\\nasm-2.16.03\\nasm.exe，或让 nasm 在 PATH 中
pwsh -NoProfile -File build.ps1        # 两遍汇编：量节长 → 写 PE 头 → build\flint-seed.exe

build\flint-seed.exe --version                     # 版本
build\flint-seed.exe --tokens src.fl               # Token 流（调试接口）
build\flint-seed.exe src.fl out.exe                # 编译：源码 → PE32+
pwsh -NoProfile -File tests\run_p0.ps1             # 阶段零验收
```

示例（`tests\p0\pos\ai_arith.fl` 的期望：stdout `14 / 20 / -2 / 1`，退出码 33）：

```
fn main() -> i64 {
    let a: i64 = 2 + 3 * 4;
    let b: i64 = (2 + 3) * 4;
    let c: i64 = -7 + 20 / 4;
    let d: i64 = 7 % 3;
    print(a); print(b); print(c); print(d);
    return a + b + c + d;
}
```

## 目录

```
build.ps1                 两遍汇编构建脚本
src\seed\                 seed.asm / defines.inc / data / memory / diag / fileio / lexer / parser / codegen1 / codegen2 / main
tests\p0\pos\             正例（期望输出与退出码写在 tests\run_p0.ps1）
tests\p0\neg\             反例（期望消息与行列写在 tests\run_p0.ps1）
tests\spec\examples\        46 份规格示例（按特性分组）
tests\spec\manifest.csv     示例期望清单（ok / cerr 错误码 / rerr）
tests\spec\check_examples.ps1  示例集结构自检
docs\p0-design.md         阶段零设计（数据结构、内存、ABI、PE 布局、代价与锁死项）
docs\p0-acceptance.md     阶段零验收报告（含本轮修复的 14 类缺陷）
docs\p1-spec.md           阶段一语言规格草案（未冻结，§18 待决）
docs\p1-errors.md         阶段一错误分类清单（E1xxx–E9xxx）
tools\nasm-2.16.03\       汇编器（仅用于种子阶段）
build\                    产物与中间文件
```

## 恢复工作指引（关机后下次继续）

```powershell
cd Flint
pwsh -NoProfile -File build.ps1                 # 重新构建种子
pwsh -NoProfile -File tests\run_p0.ps1          # 阶段零回归：应为 17/17
pwsh -NoProfile -File tests\spec\check_examples.ps1   # 示例集自检：46 例
```

阶段一未完成项：§18 的 10 项待决问题签字 → 规格冻结 → 补充“每条语法对应示例索引”（示例已有 46 份，需与 §3 产生
逐条映射表）→ 输出 EBNF 机器可读副本（供阶段三解析器一致性测试）。

## 工程约束（长期有效）

- 语言语义唯一：同一语法结构只有一种解释，不设特例分支。
- 错误必须带“文件:行:列 + 源码片段 + 插入符”，内核场景可编译期关闭。
- 可控优先：无隐式分配、隐式拷贝、隐式生命周期；隐式转换严格受限。
- 错误尽前置到编译期；运行时检查必须是可关闭的编译选项。
- 每个特性都要写明代价（二进制体积、编译耗时、运行时开销），并给出取舍记录。
- 核心语法保持精简，能放标准库的不进语法。
- 全工具链复用同一套 Lexer/AST（格式化、LSP、文档、调试信息）。
- 不做 GC、不做所有权/借用检查、不做强制 RAII、不默认边界检查、不做隐式全局状态。

## 路线图（按阶段推进，逐阶段确认）

阶段零 汇编种子编译器 → 阶段一 语言规格定稿（EBNF/语义/类型/错误分类/≥40 示例）→ 阶段二 用种子编译新语言的 Lexer 与 REPL →
阶段三 递归下降 + Pratt + AST + 反解析 → 阶段四 语义分析/符号表/类型/泛型实例化/穷尽检查 → 阶段五 高层 IR 与基础优化 →
阶段六 低层 IR 与手写 x86-64 机器码（寄存器分配）→ 阶段七 自研链接器与 PE/ELF 生成 → 阶段八 标准库/FFI/内联汇编 →
阶段九 DWARF/单元测试/格式化 → 阶段十 自举 → 阶段十一 并发原子、卫生宏、LSP、包管理器。

每阶段只做本阶段的事；跨阶段改动必须先评估对既有规格与旧代码的影响。
