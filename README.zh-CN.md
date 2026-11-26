# Flint

Flint 是一套从零实现的系统级编程语言与编译器工具链，不依赖 LLVM、GCC、Clang、ANTLR、Bison、Yacc、Tree-sitter、语法生成器或现成 VM。

编译器由上一版编译器构建：

```text
bootstrap/flintc0.exe -> flintc -> 下一版 flintc -> ...
```

`bootstrap/flintc0.exe` 是仓库内置的 stage-0 编译器，只负责启动链条；后续版本由 `src/flintc` 的源码交给上一版编译器生成。构建不需要汇编器。

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

样例会生成 PE32+、ELF64、Mach-O 64 三个目标，打印 `6`；目标程序退出码为 `20`。

## 测试

```powershell
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
