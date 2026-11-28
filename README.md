# Flint

Flint is a from-scratch systems-level programming language and compiler toolchain.
It does not depend on LLVM, GCC, Clang, ANTLR, Bison, Yacc, Tree-sitter, parser
generators, third-party code generators, or an existing VM framework.

The compiler is built from source at every stage:

```text
src/seed/*.asm + bootstrap/asm.ps1 -> flint0 -> flintc -> next flintc -> ...
```

The first-generation compiler is checked in as x86-64 assembly source under
`src/seed/`. `bootstrap/asm.ps1` is the project's own two-pass assembler; it
turns that source into `build/flint0.exe`. No prebuilt compiler binary, NASM,
C compiler, linker, or Python interpreter is required. `flint0` then compiles
`src/flintc` into the first self-hosted stage. Later stages are built by the
compiler that came before them; from stage 2 onward the compiler expands
`// include:` itself instead of relying on the PowerShell preprocessor.

## Status

- Stage 0 acceptance tests: **17 / 17**.
- Bootstrap gate: **13 / 13** (`bootstrap/gate.ps1`).
- Next-generation fixed point reached: stage 2, stage 3 and stage 4 are
  byte-identical (`bootstrap/bootstrap.ps1`). Stage 3 and stage 4 are built from
  the split `src/flintc` source by the compiler's built-in `// include:` loader.
- `flintc` supports `fn`, `let`, `return`, `if/else`, `while`, assignment,
  `+ - * / %`, comparisons, local variables, multiple functions, parameters,
  calls, and recursion.
- The parser and code generator also carry `struct`, field access, pointer
  indexing, dereference (`.*`), casts (`as u8` / `as i64`), and `+=`.
- One compiler source produces three target formats:
  **PE32+**, **ELF64**, and **Mach-O 64** for x86-64.
- The generated sample (`add`, recursive `fact`, and `main`) returns exit code
  `20` on Windows PE, Linux ELF, and macOS Mach-O.
- GitHub Actions builds the targets on Windows and runs the generated ELF on
  Linux and the generated Mach-O on macOS (`macos-15-intel`).

`flintc` writes PE32+, ELF64, and Mach-O files and exits with status 0 on
success, 1 on a compile failure. The target executable's exit code verifies the
compiled program itself.

## Bootstrap chain

The first-generation compiler is assembly source, not a checked-in executable.

```text
src/seed/seed.asm + modules
        |
        |  bootstrap/asm.ps1 (project's own two-pass x86-64 assembler)
        v
build/flint0.exe
        |
        |  compiles the expanded src/flintc translation unit
        v
build/flintc-stage1.exe
        |
        |  compiles the same expanded unit
        v
build/flintc-stage2.exe
        |
        |  compiles the split src/flintc tree (built-in include loader)
        v
build/flintc-stage3.exe
        |
        |  compiles the split tree again (built-in include loader)
        v
build/flintc-stage4.exe   ==  stage2  ==  stage3   (fixed point)
```

`bootstrap/bootstrap.ps1` performs the whole chain and fails unless stage 2,
stage 3 and stage 4 are byte-identical. The runtime library itself is assembled
from `src/runtime/runtime.asm` by `bootstrap/gen-runtime.ps1`, which regenerates
`src/flintc/runtime.fl`; no runtime bytes are copied from an external toolchain.

`build-flintc.ps1` expands `src/flintc/flintc.fl` into one translation unit only
for the assembly seed and the first self-hosted stages, which cannot read
`// include:` yet. From stage 2 onward the compiler reads the split tree
directly; the script compiles stage 2 with the compiler loader into stage 3,
stage 3 into stage 4, checks the fixed point, and installs stage 3 as
`build/flintc.exe`. Build outputs stay in `build/` and are never committed.

`flintc` parses native `argc/argv`, reads the input `.fl` file, recursively
expands `// include:` relative to the including file, and writes the target
output. With no arguments it keeps the bootstrap defaults
(`build/flintc.unit.fl` -> `build/flintc-out.exe`).

## Source layout

```text
src/seed/seed.asm          first-generation compiler in x86-64 assembly
src/seed/*.asm             lexer, parser, codegen, memory, diagnostics, file I/O
bootstrap/asm.ps1          project's own two-pass x86-64 assembler
bootstrap/build-flint0.ps1 assemble seed into build/flint0.exe
bootstrap/bootstrap.ps1    full seed -> flint0 -> flintc -> fixed point check
bootstrap/gen-runtime.ps1  assemble src/runtime and regenerate runtime.fl
flintc.ps1                 compatibility front end; the compiler now expands includes itself
build-flintc.ps1           assemble flint0, bootstrap stage1/stage2, build stage3/stage4
scripts/flint-source.ps1   bootstrap-only recursive // include: expansion
src/flintc/source.fl       compiler-side // include: loader
src/flintc/flintc.fl       flintc source root; includes the modules below
src/flintc/common.fl       token/node/local/function/struct structures
src/flintc/lexer.fl        lexer and keyword table
src/flintc/parser.fl       AST, types, expressions, statements, calls, structs
src/flintc/codegen.fl      x86-64 code generation and call patching
src/flintc/backend_pe.fl   PE32+ writer
src/flintc/backend_elf.fl  ELF64 writer
src/flintc/backend_macho.fl Mach-O 64 writer
src/flintc/main.fl         flintc entry point
src/runtime/runtime.asm    runtime library assembled into generated programs
src/flintc/sample.fl       small sample input for the three targets
bootstrap/                 assembler, flint0 builder, gate, ladder
tests/                     stage-0 regression and specification examples
docs/                      design, acceptance, and bootstrap notes
```

## Build

Requirements: PowerShell 7. No external assembler, C compiler, linker, or
package manager is required; the repository carries its own assembler.

```powershell
pwsh -NoProfile -File build-flintc.ps1 # build build/flintc.exe from split sources
```

## Run

```powershell
build\flintc.exe src\flintc\sample.fl build\sample.exe
build\sample.exe   # exit code 20
pwsh -NoProfile -File flintc.ps1 src\flintc\sample.fl build\sample.exe -AllTargets
```

`build\flintc.exe` parses `argc/argv` at runtime, expands `// include:` itself,
and writes the PE directly; `-AllTargets` is handled by the compatibility
wrapper, which also copies the ELF64 and Mach-O files. With no arguments the
compiler keeps the bootstrap defaults (`build/flintc.unit.fl` ->
`build/flintc-out.exe`), and `bootstrap/bootstrap.ps1` drives the fixed-point
chain.

## Tests

```powershell
pwsh -NoProfile -File bootstrap\bootstrap.ps1
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

- `fn` declarations with typed parameters and return types
- `struct` declarations with named fields
- field access, pointer indexing, dereference, and `as` casts
- `let`, `return`, `if/else`, `while`, assignment, `+=`
- integer arithmetic `+ - * / %`, comparisons, unary minus
- local variables and stack frames
- multiple functions, calls, forward calls, recursion
- stack-passed arguments with caller cleanup
- PE32+, ELF64, and Mach-O 64 output

Not implemented yet:

- string literals
- arrays with declared bounds and aggregate values
- global variables and modules
- relocations, symbol tables, dynamic linking

## Backend notes

- PE: one `.text` section, entry RVA `0x1000`, nine KERNEL32 imports
  (`GetCommandLineA` was added for native `argc/argv`). The import table and IAT
  occupy RVA `0x30000` upward; the entry stub reserves `0x28` bytes of shadow
  space before calling `main`, and the exit stub calls `ExitProcess` after the
  generated code.
- ELF64: one `PT_LOAD`, entry `0x400078`, Linux `exit` syscall 60.
- Mach-O 64: static `__TEXT` / `__DATA` / `__LINKEDIT` segments,
  `LC_UNIXTHREAD` entry at file offset `0x300`, a `0x4000`-byte zero-filled
  stack in `__DATA`, and the macOS `exit` syscall `0x2000001`. It does not use
  dyld or libSystem.

## Roadmap

1. String literals, arrays with bounds, globals, and modules.
2. Port file I/O and the `argc/argv` runtime from Win32 to Linux/macOS syscalls
   so `flintc` can run natively there.
3. Freeze the stage-one language specification and sign off the ten pending
   decisions in `docs/p1-spec.md`.

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
