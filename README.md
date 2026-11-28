# Flint

Flint is a from-scratch systems-level programming language and compiler toolchain.
It does not depend on LLVM, GCC, Clang, ANTLR, Bison, Yacc, Tree-sitter, parser
generators, third-party code generators, or an existing VM framework.

The compiler is built from source at every stage:

```text
src/seed/*.asm + bootstrap/asm.ps1 -> flint0 (cold start only)
current build/flintc.exe -> next flintc -> fixed point
```

## Status

- Cold-start stage-0 acceptance tests: **17 / 17** with `build/flint0.exe`
  (`tests/run_p0.ps1`; legacy seed check, not part of the normal build).
- Next-generation fixed point reached: the current compiler compiles the split
  source into a new compiler, that compiler compiles the same source again, and
  both outputs are byte-identical (`bootstrap/bootstrap.ps1`).
- The compiler expands `// include:` itself from split sources. Normal builds do
  not run the PowerShell preprocessor and do not invoke the assembly seed.
- `flintc` supports `fn`, `let`, `return`, `if/else`, `while`, assignment,
  `+ - * / %`, comparisons, local variables, multiple functions, parameters,
  calls, and recursion.
- It also supports `struct` with field access, pointer indexing, dereference
  (`.*`), casts (`as u8` / `as i64`), `+=`, `byte`, character literals,
  function-pointer types and indirect calls, fixed arrays `[T; N]`, array
  literals, struct literals, arrays of structs with per-element field access,
  half-open numeric loops (`for i in a..b { ... }`), `break`/`continue`,
  and `else if`.
- The bootstrap ladder passes **15 / 15** (`bootstrap/gate.ps1`). The current
  fixed point is
  `FCBA43EACD03EFF75BFA606B9A3E6E6E057D6466583F187D83C8B6F4828063A6`.
- One compiler source produces three target formats:
  **PE32+**, **ELF64**, and **Mach-O 64** for x86-64.
- The generated sample returns exit code `20` on Windows PE, Linux ELF, and
  macOS Mach-O.

## Bootstrap chain

Normal builds use the compiler that already exists:

```text
src/seed/*.asm + bootstrap/asm.ps1
        |
        |  bootstrap/cold-start.ps1 (once, only when build/flintc.exe is absent)
        v
build/flintc.exe
        |
        |  build-flintc.ps1 / bootstrap/bootstrap.ps1
        |  compiles split src/flintc (built-in include loader)
        v
build/flintc-next1.exe
        |
        |  compiles the same split source again
        v
build/flintc-next2.exe   ==  flintc-next1.exe   (fixed point)
```

`bootstrap/cold-start.ps1` is the only path that assembles the seed and expands
the translation unit with PowerShell. It installs the first fixed-point
compiler as `build/flintc.exe`. After that, `build-flintc.ps1` and
`bootstrap/bootstrap.ps1` compile the compiler with the current compiler.

The runtime library is assembled from `src/runtime/runtime.asm` by
`bootstrap/gen-runtime.ps1`, which regenerates `src/flintc/runtime.fl`. Its PE
import table has nine KERNEL32 entries; `rt_readfile` reads the Win32 byte count
as a DWORD and zero-extends it, and all Win32 calls keep 16-byte stack alignment.

## Source layout

```text
src/seed/seed.asm          cold-start compiler in x86-64 assembly
src/seed/*.asm             lexer, parser, codegen, memory, diagnostics, file IO
bootstrap/asm.ps1          project's own two-pass x86-64 assembler
bootstrap/build-flint0.ps1 assemble seed into build/flint0.exe
bootstrap/cold-start.ps1   one-time cold start; installs build/flintc.exe
bootstrap/bootstrap.ps1    current compiler -> next compiler fixed-point check
bootstrap/gen-runtime.ps1  assemble src/runtime and regenerate runtime.fl
flintc.ps1                 compatibility wrapper for -AllTargets
build-flintc.ps1           current compiler builds the next compiler
scripts/flint-source.ps1   cold-start-only // include: expansion
src/flintc/source.fl       compiler-side // include: loader
src/flintc/flintc.fl       source root; includes the modules below
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
bootstrap/                 assembler, cold start, fixed-point check
tests/                     stage-0 regression and specification examples
docs/                      design, acceptance, and bootstrap notes
```

## Build

Requirements: PowerShell 7. No external assembler, C compiler, linker, or
package manager is required; the repository carries its own assembler.

```powershell
pwsh -NoProfile -File build-flintc.ps1
```

On a fresh machine with no `build/flintc.exe`, run the cold start once:

```powershell
pwsh -NoProfile -File bootstrap\cold-start.ps1
pwsh -NoProfile -File build-flintc.ps1
```

## Run

```powershell
build\flintc.exe src\flintc\sample.fl build\sample.exe
build\sample.exe   # exit code 20
pwsh -NoProfile -File flintc.ps1 src\flintc\sample.fl build\sample.exe -AllTargets
```

`build\flintc.exe` parses `argc/argv`, expands `// include:` itself, and writes
the PE directly. `-AllTargets` is handled by the compatibility wrapper, which
also copies the ELF64 and Mach-O files. With no arguments the compiler keeps the
bootstrap defaults (`build/flintc.unit.fl` -> `build/flintc-out.exe`).

## Tests

Normal self-hosted regression:

```powershell
pwsh -NoProfile -File bootstrap\bootstrap.ps1
pwsh -NoProfile -File tests\spec\check_examples.ps1
pwsh -NoProfile -File tests\run_all.ps1
```

Expected results:

- bootstrap fixed point: pass
- specification examples: `46`
- `run_all`: no hard failures

`tests/run_p0.ps1` is the legacy cold-start acceptance suite and requires
`build/flint0.exe`. It is not invoked by `run_all` or by the normal build.

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
  (`GetCommandLineA` supplies native `argc/argv`). The import table and IAT
  occupy RVA `0x30000` upward; the entry stub reserves `0x28` bytes of shadow
  space before calling `main`, and the exit stub calls `ExitProcess`.
- ELF64: one `PT_LOAD`, entry `0x400078`, Linux `exit` syscall 60.
- Mach-O 64: static `__TEXT` / `__DATA` / `__LINKEDIT` segments,
  `LC_UNIXTHREAD` entry at file offset `0x300`, a `0x4000`-byte zero-filled
  stack in `__DATA`, and the macOS `exit` syscall `0x2000001`. It does not use
  dyld or libSystem.

## Roadmap

1. String literals, arrays with bounds, globals, and modules.
2. Port file I/O and the `argc/argv` runtime from Win32 to Linux/macOS syscalls
   so `flintc` can run natively there.
3. Finalize the stage-one language specification decisions in
   `docs/p1-spec.md`.

## Engineering constraints

- No GC, ownership/borrow checking, or mandatory RAII.
- No default bounds checks; runtime checks must be optional.
- No implicit allocation, implicit copies, or hidden global state.
- Every feature must document its cost in binary size, compile time, and runtime
  overhead.
- The core grammar stays small; library features stay out of the grammar.
- Diagnostics must include file, line, column, source excerpt, and a caret.
- Documentation and code comments are written in English.

## License

MIT. See `LICENSE`.
