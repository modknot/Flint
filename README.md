# Flint

Flint is a from-scratch systems-level programming language and compiler toolchain.
The bootstrap starts with a hand-written x86-64 NASM seed compiler. No C, Rust,
or Python host is used, and the project does not depend on LLVM, GCC, Clang,
ANTLR, Bison, Yacc, Tree-sitter, parser generators, third-party code generators,
or an existing VM framework.

The goal is to grow the seed into a self-hosted Flint compiler written in Flint.

## Status

- Stage 0 seed compiler: **17 / 17** acceptance tests.
- Bootstrap gate: **13 / 13** (`bootstrap/gate.ps1`).
- `flintc` v0.4 supports `fn`, `let`, `return`, `if/else`, `while`, assignment,
  `+ - * / %`, comparisons, local variables, multiple functions, function
  parameters, function calls, and recursion.
- One compiler source produces three target formats:
  **PE32+**, **ELF64**, and **Mach-O 64** for x86-64.
- The generated sample (`add`, recursive `fact`, and `main`) returns exit code
  `20` on Windows PE, Linux ELF, and macOS Mach-O.
- GitHub Actions builds the targets on Windows and runs the generated ELF on
  Linux and the generated Mach-O on macOS (`macos-15-intel`).

`flintc` currently writes three files and prints `6`: three successful writes
plus three successful magic-number checks. The actual program result is verified
by the target executable's exit code.

## Bootstrap chain

```text
NASM seed -> first flintc -> next flintc -> ...
```

The NASM seed is only the first step. Once `flintc` can compile its own Flint
source, the next compiler version is built by the previous `flintc`; the seed is
no longer part of the chain. The three operating systems are not three seeds:
they are three backends of the same compiler source.

Until `flintc` can parse its own complete source, build scripts expand the
`// include:` directives in `src/flintc/flintc.fl` into one translation unit
before invoking the seed. The source is modular; the include expansion is a
bootstrap-era build step.

## Source layout

```text
build.ps1                  assemble the NASM seed (two-pass PE build)
build-flintc.ps1           expand Flint includes and compile flintc
scripts/flint-source.ps1   recursive // include: expansion
src/seed/                  NASM seed compiler and its runtime
src/flintc/flintc.fl       flintc source root; includes the modules below
src/flintc/common.fl       token/node/local/function structures, byte helpers
src/flintc/lexer.fl        lexer and keyword table
src/flintc/parser.fl       AST, expressions, statements, functions, calls
src/flintc/codegen.fl      x86-64 code generation and call patching
src/flintc/backend_pe.fl   PE32+ writer
src/flintc/backend_elf.fl  ELF64 writer
src/flintc/backend_macho.fl Mach-O 64 writer
src/flintc/main.fl         flintc entry point
src/flintc/sample.fl       sample input compiled into the three targets
bootstrap/                 bootstrap gate and ladder tests
tests/                     stage-0 regression and specification examples
docs/                      design, acceptance, specification, bootstrap notes
```

## Build

Requirements: PowerShell 7 and NASM 2.16.03.

Place NASM at `tools/nasm-2.16.03/nasm.exe`, or make `nasm` available on `PATH`.

```powershell
pwsh -NoProfile -File build.ps1        # build build/flint-seed.exe
pwsh -NoProfile -File build-flintc.ps1 # build build/flintc.exe from split sources
```

The build scripts intentionally do not write absolute local paths into the
repository. Tool binaries and build outputs are ignored by Git.

## Run

```powershell
build\flint-seed.exe --version
build\flint-seed.exe --tokens src\flintc\sample.fl
build\flint-seed.exe src\flintc\sample.fl build\sample.exe

build\flintc.exe
build\flintc-pe.exe
```

`flintc` reads `src/flintc/sample.fl`, writes `build/flintc-pe.exe`,
`build/flintc-elf`, and `build/flintc-macho`, and prints `6`. The sample exits
with `20` on Windows, Linux, and macOS.

## Tests

```powershell
pwsh -NoProfile -File bootstrap\gate.ps1
pwsh -NoProfile -File tests\run_p0.ps1
pwsh -NoProfile -File tests\run_all.ps1
```

Expected results:

- bootstrap gate: `13 / 13`
- stage-0 acceptance: `17 / 17`
- specification examples: `46`
- `run_all`: no hard failures

## Language support

Implemented in `flintc`:

- `fn` declarations with typed parameters and an `i64` return type
- `let`, `return`, `if/else`, `while`, assignment
- integer arithmetic `+ - * / %`, comparisons, unary minus
- local variables and stack frames
- multiple functions, calls, forward calls, recursion
- stack-passed arguments with caller cleanup
- PE32+, ELF64, and Mach-O 64 output

Not implemented yet:

- string literals
- structs, arrays, field/index access
- global variables and modules
- command-line input; `sample.fl` is currently fixed
- relocations, symbol tables, dynamic linking
- a self-hosted `flintc` build

## Backend notes

- PE: one `.text` section, entry RVA `0x1000`, IAT at RVA `0x2000`, imports
  `KERNEL32.dll!ExitProcess`, exit stub after the generated code.
- ELF64: one `PT_LOAD`, entry `0x400078`, Linux `exit` syscall 60.
- Mach-O 64: static `__TEXT` / `__DATA` / `__LINKEDIT` segments, `LC_UNIXTHREAD`
  entry at file offset `0x300`, a `0x4000`-byte zero-filled stack in `__DATA`,
  and the macOS `exit` syscall `0x2000001`. It does not use dyld or libSystem.

## Roadmap

1. Add string literals and a read-only data section.
2. Add structs, arrays, field and index addressing.
3. Add global variables and command-line arguments.
4. Compile `flintc` with `flintc` and validate a fixed-point bootstrap.
5. Add a native macOS `flintc` once file I/O is ported from Win32 to syscalls.

## Engineering constraints

- No GC, ownership/borrow checking, or mandatory RAII.
- No default bounds checks; runtime checks must be optional.
- No implicit allocation, implicit copies, or hidden global state.
- Every feature must document its cost in binary size, compile time, and runtime
  overhead.
- The core grammar stays small; library features stay out of the grammar.
- Diagnostics must include file, line, column, source excerpt, and a caret.

## License

MIT. See `LICENSE`.
