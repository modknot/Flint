# Flint

Flint 是一套从零实现的系统级编程语言与编译器工具链，不依赖 LLVM、GCC、Clang、ANTLR、Bison、Yacc、Tree-sitter、语法生成器或现成 VM。

编译器从源码构建：

```text
src/seed/*.asm + bootstrap/asm.ps1 -> flint0 -> flintc -> 下一版 flintc -> ...
```

第一代编译器以 x86-64 汇编源码形式放在 `src/seed/`。`bootstrap/asm.ps1` 是项目自带的
两遍汇编器，从这些源码生成 `build/flint0.exe`；仓库不放入现成编译器二进制，也不需要
NASM、C 编译器、链接器或 Python。`flint0` 再把 `src/flintc` 编译成 `build/flintc.exe`，
后续版本由上一版编译器生成。

英文说明与完整状态见 [README.md](README.md)。

## 构建

需要 PowerShell 7。

```powershell
pwsh -NoProfile -File build-flintc.ps1
```

## 运行

```powershell
build\flintc.exe
build\flintc-pe.exe
```

自举模式会编译整个编译器源码并生成 PE32+、ELF64、Mach-O 64 三个目标；第二阶段与第三阶段编译器已做到逐字节相同（固定点）。

## 测试

```powershell
pwsh -NoProfile -File bootstrap\bootstrap.ps1
pwsh -NoProfile -File bootstrap\gate.ps1
pwsh -NoProfile -File tests\run_p0.ps1
pwsh -NoProfile -File tests\run_all.ps1
```

## 约束

- 不做 GC、所有权/借用检查或强制 RAII。
- 默认不开边界检查。
- 语法保持小，库功能不进入语法。
- 诊断信息包含文件、行、列、源码片段与插入符。

许可证：MIT，见 [LICENSE](LICENSE)。
