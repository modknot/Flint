# Stage Two: Bootstrap Preparation

## Route

**One Flint compiler source tree plus three target backends.** There are no three platform-specific bootstraps.

- `src\seed\*.asm` is the cold-start source. `bootstrap\asm.ps1` assembles it into `build\flint0.exe` without NASM, a C compiler, or Python.
- `flint0` produces the first self-hosted compiler from one expanded translation unit. It is used only by `bootstrap\cold-start.ps1` on a machine that has no `build\flintc.exe`.
- Normal builds and the bootstrap check use the current fixed-point `build\flintc.exe` to compile `src\flintc\flintc.fl` directly. The compiler expands `// include:` itself; PowerShell does not preprocess the source.
- One compiler source produces PE32+, ELF64, and Mach-O output. Linux and macOS native compilers are cross-compiled from the same source.

## Source split

`src\flintc\flintc.fl` is an include manifest. The implementation is split by responsibility:

```text
common.fl         structures, byte helpers, path helpers
source.fl         compiler-side // include: loader
lexer.fl          lexer
parser.fl         AST, expressions, statements, functions, calls
codegen.fl        x86-64 code generation, function labels, call patching
backend_pe.fl     PE32+ backend
backend_elf.fl    ELF64 backend
backend_macho.fl  Mach-O 64 backend
main.fl           flintc entry point
```

`expand_source` in `source.fl` resolves a directive relative to the file that contains it and recurses up to 16 levels. Missing files, read failures, or buffer overflow return zero; `main` reports `11` and exits 1.

`bootstrap\cold-start.ps1` is the only place that expands the unit with `scripts\flint-source.ps1`. It feeds the expanded unit to the assembly seed, produces the first self-hosted compiler, and verifies its fixed point before installing `build\flintc.exe`. After that, every normal build is compiler-driven.

## Self-host loop

`build-flintc.ps1` and `bootstrap\bootstrap.ps1` run the same loop:

```text
current build/flintc.exe
        |
        |  compiles split src/flintc (built-in include loader)
        v
build/flintc-next1.exe
        |
        |  compiles the same split source again
        v
build/flintc-next2.exe
        |
        |  next1 and next2 must be byte-identical
        v
install next1 as build/flintc.exe
```

The assembly seed and `flint0` are not invoked. The current compiler reads the same split tree that it will later compile.

A cold machine runs the one-time chain:

```text
src/seed/*.asm -> flint0.exe -> cold stage1 -> cold stage2
cold stage2 -> cold stage3 -> cold stage4   (split source, built-in loader)
cold stage2 == cold stage3 == cold stage4
install cold stage3 as build/flintc.exe
```

## Runtime

`src\runtime\runtime.asm` is assembled by `bootstrap\gen-runtime.ps1`, which regenerates `src\flintc\runtime.fl`. The runtime is 1122 bytes. Its PE import table has nine entries:

`VirtualAlloc / VirtualFree / CreateFileA / ReadFile / WriteFile / CloseHandle / GetStdHandle / ExitProcess / GetCommandLineA`

The IAT and ILT live inside the section starting at `0x2F000`. `rt_readfile` reads the Win32 byte count as a DWORD and zero-extends it; function prologues and Win32 calls maintain 16-byte stack alignment.

## Backends

### PE32+

- DOS header + PE header + one `.text` section, entry RVA `0x1000`.
- The entry stub reserves `0x28` bytes of shadow space, calls `main`, then jumps to an exit stub: `mov ecx,eax` → `call [ExitProcess]`.
- IAT / ILT / import descriptors start at section offset `0x2F000` (RVA `0x30000`). Imports are the nine KERNEL32 entries listed above.
- File length `0x30200`; section size `0x30000`; code budget about `0x2FD00` bytes.

### ELF64

- ELF header + one `PT_LOAD` mapping the whole file; entry `0x400078`.
- Entry calls `main`, then jumps to `mov edi,eax` → `mov eax,60` → `syscall`.
- File length `0x1000`; code budget `0xF88` bytes.

### Mach-O 64

- `MH_MAGIC_64` + `__PAGEZERO` + `__TEXT` (with `__text`) + `__DATA` + `__LINKEDIT`.
- Static executable: `LC_UNIXTHREAD` sets entry `0x100000300` and stack top `0x100006000`; dyld/libSystem are not loaded.
- Entry calls `main`, then jumps to `mov edi,eax` → `mov eax,0x2000001` → `syscall`.
- File length `0x2000`; code starts at `0x300`.

## Language builtins

```flint
writefile(path: ^u8, pathlen: i64, data: ^u8, len: i64) -> i64
readfile(path: ^u8, pathlen: i64, buf: ^u8, maxlen: i64) -> i64
```

- Paths are passed as single-byte ANSI/UTF-8 to Win32 `CreateFileA`.
- `writefile` returns 1 on success and 0 on failure.
- `readfile` returns the number of bytes read and 0 on failure.

## Current boundaries

- `flintc` recognizes identifiers, keywords, integers, operators, and `^T` pointer types.
- It supports `fn`, `let`, `return`, `if/else`, `while`, assignment, `+ - * / %`, comparisons, and local variables.
- It supports multiple functions, parameters, calls, and recursion. Arguments are passed on the stack; the caller cleans them; the local frame is fixed at `0x400` bytes.
- Function labels are patched after all functions are generated, so forward calls and self-calls work.
- The runtime parses `argc/argv` with `GetCommandLineA` on the first `alloc`. `flintc.exe` accepts a `.fl` input and a PE output path. With no arguments it keeps `build/flintc.unit.fl` → `build/flintc-out.exe`.
- The compiler expands `// include:` relative to the including file, with a recursion limit of 16. It does not normalize `..` or provide a dedicated missing-include diagnostic; failures report `11` and exit 1.
- Mach-O runs on `macos-15-intel` in GitHub Actions with exit code 20; PE completes the self-host loop on Windows; ELF runs natively.
- Backends use fixed entry points and do not implement relocations, symbol tables, or dynamic linking.

## Next

- Parser: string literals, structs, arrays.
- Code generation: string constants, field/index addressing, global data.
- Port file IO and `argc/argv` runtime from Win32 to Linux/macOS syscalls so `flintc` runs natively on all three platforms.
