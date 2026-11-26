# Flint

Flint is a from-scratch systems-level programming language and compiler toolchain.
It does not depend on LLVM, GCC, Clang, ANTLR, Bison, Yacc, Tree-sitter, parser
generators, third-party code generators, or an existing VM framework.

The compiler is built by its previous version:

```text
bootstrap/flintc0.exe -> flintc -> next flintc -> ...
```

`bootstrap/flintc0.exe` is the checked-in stage-0 compiler. It starts the chain;
later stages are compiled from `src/flintc` by the compiler that came before
them. No assembler is required to build the project.

## Status

- Stage 0 acceptance tests: **17 / 17**.
- Bootstrap gate: **13 / 13** (`bootstrap/gate.ps1`).
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

`flintc` currently writes three files and prints `6`: three successful writes
plus three successful magic-number checks. The actual program result is verified
by the target executable's exit code.

## Bootstrap chain

The earliest assembly seed of the prototype has been retired. The repository now
starts from an opaque stage-0 binary and keeps the rest of the chain in Flint.

```text
stage-0 binary -> first flintc -> next flintc -> ...
```

`build-flintc.ps1` expands the `// include:` directives in
`src/flintc/flintc.fl` into one translation unit, then passes it to
`bootstrap/flintc0.exe`. Build outputs stay in `build/` and are never committed.

## Source layout

```text
bootstrap/flintc0.exe      checked-in stage-0 compiler used for the first build
build-flintc.ps1           expand Flint includes and compile flintc
scripts/flint-source.ps1   recursive // include: expansion
src/flintc/flintc.fl       flintc source root; includes the modules below
src/flintc/common.fl       token/node/local/function/struct structures
src/flintc/lexer.fl        lexer and keyword table
src/flintc/parser.fl       AST, types, expressions, statements, calls, structs
src/flintc/codegen.fl      x86-64 code generation and call patching
src/flintc/backend_pe.fl   PE32+ writer
src/flintc/backend_elf.fl  ELF64 writer
src/flintc/backend_macho.fl Mach-O 64 writer
src/flintc/main.fl         flintc entry point
src/flintc/sample.fl       sample input compiled into the three targets
bootstrap/                 gate, ladder, and the stage-0 binary
tests/                     stage-0 regression and specification examples
docs/                      design, acceptance, and bootstrap notes
```

## Build

Requirements: PowerShell 7. No assembler, C compiler, linker, or package
manager is required.

```powershell
pwsh -NoProfile -File build-flintc.ps1 # build build/flintc.exe from split sources
```

## Run

```powershell
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
- command-line input; `sample.fl` is currently fixed
- relocations, symbol tables, dynamic linking
- a fixed-point self-hosted build

## Backend notes

- PE: one `.text` section, entry RVA `0x1000`, IAT at RVA `0x2000`, imports
  `KERNEL32.dll!ExitProcess`, exit stub after the generated code.
- ELF64: one `PT_LOAD`, entry `0x400078`, Linux `exit` syscall 60.
- Mach-O 64: static `__TEXT` / `__DATA` / `__LINKEDIT` segments,
  `LC_UNIXTHREAD` entry at file offset `0x300`, a `0x4000`-byte zero-filled
  stack in `__DATA`, and the macOS `exit` syscall `0x2000001`. It does not use
  dyld or libSystem.

## Roadmap

1. Raise compiler buffers and backend capacities so `flintc` can parse its own
   full source.
2. Add runtime support for `alloc`, file I/O, and `print` in generated PE/ELF.
3. Compile `flintc` with `flintc` and validate a fixed-point bootstrap.
4. Add a native macOS `flintc` once file I/O is ported from Win32 to syscalls.

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
