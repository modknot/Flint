# 阶段二：自举准备

## 路线

**一套 Flint 编译器源码 + 三个目标后端**，不做三份平台专用引导移植。

- `src\seed\*.asm` 是仓库内置的第一代编译器源码；`bootstrap\asm.ps1` 是项目自带的两遍 x86-64 汇编器，从汇编源码生成 `build\flint0.exe`。仓库不放现成 exe，也不依赖 NASM、C 编译器或 Python。
- `flint0` 负责把第一版 `src\flintc\flintc.fl` 编译成 Windows PE。
- flintc 负责读取 `.fl` 源码、词法、语法、x86-64 代码生成，并写出 PE / ELF64 / Mach-O。
- Linux / macOS 原生编译器由 flintc 交叉编译自身得到；macOS 先保 x86-64，Apple Silicon arm64 后置。

## 源码拆分

`src\flintc\flintc.fl` 现在只是包含清单，实际代码按职责拆成：

```text
common.fl         结构体、字节工具、路径工具
lexer.fl          词法器
parser.fl         AST、表达式、语句、函数与调用解析
codegen.fl        x86-64 代码生成、函数标签、调用回填
backend_pe.fl     PE32+ 后端
backend_elf.fl    ELF64 后端
backend_macho.fl  Mach-O 64 后端
main.fl           flintc 入口
```

`build-flintc.ps1` 和 `bootstrap\gate.ps1` 会递归展开 `// include:` 指令，
生成 `build\flintc.unit.fl`；构建脚本先用 `bootstrap\asm.ps1` 汇编 `src\seed` 得到
`build\flint0.exe`，再由它编译该翻译单元。这样源码是多文件，第一代编译器仍只吃一个翻译单元；
以后 flintc 自己支持模块时，再由编译器接管 include。

## 自举固定点

`bootstrap\bootstrap.ps1` 现在跑完整链条：

```text
src/seed/*.asm -> flint0.exe -> flintc-stage1.exe
flintc-stage1.exe -> flintc-stage2.exe
flintc-stage2.exe -> flintc-stage3.exe
stage2 == stage3（SHA-256 相同）
```

运行库 `src\runtime\runtime.asm` 由 `bootstrap\gen-runtime.ps1` 汇编并生成
`src\flintc\runtime.fl`，运行库字节不再依赖外部工具或手写抄录。PE 导入表为
`VirtualAlloc / VirtualFree / CreateFileA / ReadFile / WriteFile / CloseHandle /
GetStdHandle / ExitProcess` 八项，IAT 和 ILT 都在节内 `0x2F000` 起。

## 当前闸门 13 / 13

| 级别 | 验证内容 |
| --- | --- |
| p0–p6 | 算术、循环、指针/堆、字节缓冲、结构体数组、机器码补丁、函数指针 |
| p7–p9 | 最小词法器、递归下降解析器、AST→字节码→栈式 VM |
| p10 | `build\flint0.exe` 编译整个 flintc；flintc 读 `build\flintc.unit.fl`，写出三个目标文件 |
| p11 | 生成程序自己写文件 |
| p12 | 生成程序自己读文件 |

`p10` 验证 `flint0` 能编译整个 flintc 并写出三个目标文件；目标程序内部的控制流、函数参数、调用与递归由 PE/ELF 退出码单独验证。

## 三个后端

### PE32+

- DOS 头 + PE 头 + 一个 `.text` 节，入口 RVA `0x1000`。
- 入口先 `sub rsp,0x28` 预留影子空间，再 `call main`；返回后跳到代码尾部追加的退出桩：`mov ecx,eax` → `call [ExitProcess]`。
- IAT / ILT / 导入描述符在节内 `0x2F000` 起，对应 RVA `0x30000` 起；导入 `KERNEL32.dll` 的
  `VirtualAlloc / VirtualFree / CreateFileA / ReadFile / WriteFile / CloseHandle /
  GetStdHandle / ExitProcess` 八项。
- 文件长度 `0x30200`，节区 `0x30000`，代码上限约 `0x2FD00` 字节。

### ELF64

- ELF 头 + 一个 `PT_LOAD`，映射整个文件，入口 `0x400078`。
- 入口先 `call main`，返回后跳到代码尾部追加的 `mov edi,eax` → `mov eax,60` → `syscall`。
- 文件长度 `0x1000`，代码上限 `0xF88` 字节。

### Mach-O 64

- `MH_MAGIC_64` + `__PAGEZERO` + `__TEXT`（含 `__text`）+ `__DATA` + `__LINKEDIT`。
- 静态可执行：`LC_UNIXTHREAD` 指定入口 `0x100000300` 与栈顶 `0x100006000`，不加载 dyld / libSystem。
- 入口先 `call main`，返回后跳到代码尾部追加的 `mov edi,eax` → `mov eax,0x2000001` → `syscall`。
- 文件长度 `0x2000`，代码区从 `0x300` 开始。

## 新增语言内建

```flint
writefile(path: ^u8, pathlen: i64, data: ^u8, len: i64) -> i64
readfile(path: ^u8, pathlen: i64, buf: ^u8, maxlen: i64) -> i64
```

- 路径按单字节 ANSI/UTF-8 传给 Win32 `CreateFileA`。
- `writefile` 成功返回 `1`，失败返回 `0`。
- `readfile` 返回实际读取字节数，失败返回 `0`。

## 当前边界

- flintc v0.4 已识别标识符、关键字、整数、运算符和 `^T` 指针类型。
- 已支持 `fn`、`let`、`return`、`if/else`、`while`、赋值、`+ - * / %`、比较、局部变量。
- 已支持多函数程序、函数参数、函数调用、递归；参数按栈传递，调用者清理实参，局部栈帧固定 `0x400`。
- 函数标签在全部函数生成后统一回填 `call rel32`，因此支持前向调用和自调用。
- 尚未在编译器内部接 `argc/argv`；自举模式固定读取 `build/flintc.unit.fl`，固定写 `build/flintc-out.exe`。仓库根的 `flintc.ps1` 已提供普通命令行前端：输入 `.fl`、输出 PE，并可用 `-AllTargets` 同时导出 ELF/Mach-O。
- Mach-O 已在 `macos-15-intel` 的 GitHub Actions 中实际运行，退出码 `20`；PE 已在 Windows 原生环境完成整条自举链并达到固定点，ELF 也已实际运行验证。
- 后端只支持固定入口，未实现重定位、符号表、动态链接。

## 下一段

- 把 `argc/argv` 做进编译器自身，去掉自举模式的固定输入路径。
- 解析器补字符串字面量、结构体、数组。
- 代码生成补字符串常量、字段/下标寻址、全局数据段。
- 阶段一规格 10 项待决签字。
