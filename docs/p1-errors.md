# Error Taxonomy · Stage One Deliverable II

Rule: every error has a stable `E<three/four digits>` code. A published code is never reused and never changes meaning; retired codes are kept and marked deprecated.
Placeholders in message templates are `{name}`, `{type}`, and `{path}`. Message bodies may be localized; codes and English keywords are stable for tooling.

Location rule: `file:line:col` must point at the triggering character. Name-related errors also report the definition location; generic errors include the full instantiation chain.

---

## Number ranges

| Range | Area | Stage |
| --- | --- | --- |
| E1xxx | Lexing | Stage 2 |
| E2xxx | Parsing | Stage 3 |
| E3xxx | Names / scope / modules | Stage 4 |
| E4xxx | Types / conversions / error handling / FFI types | Stage 4 |
| E5xxx | Generics / pattern matching / constant evaluation | Stage 4/5 |
| E6xxx | IR / optimization / instruction encoding / assembler | Stage 5/6/8 |
| E7xxx | Linking / PE / ELF / relocations / debug info | Stage 7/9 |
| E8xxx | Runtime (panic / checks / allocator / stack guard) | Stage 8+ |
| E9xxx | Driver / CLI / files / IO / configuration | Stage 0+ |
| Wxxxx | Warnings (can be promoted to errors) | Always |

Recovery strategies: `skip1` skips one byte; `to-eof` advances to end of file; `to-stmt` advances to `;`, `}`, or `fn`; `to-param` advances to `,`, `)`, or `{`; `to-typeargs` advances to `]`; `to-item` advances to the next `fn` or top-level item.
`fatal` means unrecoverable (environment or resource failure): terminate immediately with the exit code.

---

## Lexing (E1xxx)

| Code | Message template | Trigger | Recovery |
| --- | --- | --- | --- |
| E1001 | invalid character `{ch}` | not in any token start set | skip1 |
| E1002 | unterminated string literal | end of line or EOF before closing quote | to-eof |
| E1003 | unterminated block comment (started at {line}:{col}) | depth never returns to zero | to-eof |
| E1004 | integer literal out of range for {type} (value {text}) | accumulation overflow or suffix range check | skip remaining digits |
| E1005 | numeric literal has no valid digits | no digit after `0x` or `0b` | skip1 |
| E1006 | illegal underscore position (consecutive `__` or leading/trailing `_`) | literal separator rules | continue |
| E1007 | unknown escape sequence `\{ch}` | not in the string/character escape table | continue |
| E1008 | character literal must contain exactly one scalar | empty or multiple code points | skip1 |
| E1009 | invalid UTF-8 byte sequence | source decoding failure | to-eof |
| E1010 | identifier normalization collision: `{a}` and `{b}` are the same name | identical after NFC normalization | continue |

## Parsing (E2xxx)

| Code | Message template | Trigger | Recovery |
| --- | --- | --- | --- |
| E2001 | expected `{expected}`, found `{actual}` | generic expect failure | context-dependent |
| E2002 | expected identifier | declaration position is not an identifier | to-stmt |
| E2003 | expected type | token after `:` is not a type start | to-stmt |
| E2004 | expected `->` return type or `{` | function header | to-item |
| E2005 | expression missing operand | operator or terminator in prefix position | to-stmt |
| E2006 | negative number cannot directly follow `..` (use parentheses) | ambiguous `a..-1` | to-stmt |
| E2007 | generic argument list missing `]` | after `::[` | to-typeargs |
| E2008 | `.*` is not allowed here (dereference requires a pointer) | syntactic misuse | to-stmt |
| E2009 | `match` arm missing `=>` | arm parsing | to-stmt |
| E2010 | missing `;` after statement | expression statement / let / return | to-stmt |
| E2011 | `if` condition missing block `{` | non-`{` after condition | to-stmt |
| E2012 | unexpected top-level item `{tok}` | top level is not an item start | to-item |
| E2013 | `label` must be followed by a block | label statement | to-stmt |
| E2014 | `onexit` must be followed by a block | onexit | to-stmt |
| E2015 | `break`/`continue` label must be an identifier | non-identifier | to-stmt |

## Names / scope / modules (E3xxx)

| Code | Message template | Trigger |
| --- | --- | --- |
| E3101 | undefined name `{name}` (with nearest definition hint) | resolution failure |
| E3102 | `{name}` is {priv/pkg} and is not accessible from this module | visibility |
| E3103 | duplicate declaration `{name}` in the same scope (first at {loc}) | duplicate name |
| E3104 | use of uninitialized variable `{name}` | data-flow check |
| E3105 | `{name}` references itself during initialization | initialization cycle |
| E3106 | cyclic import: `{path}` | module graph cycle; print the full cycle |
| E3107 | imported name collision `{name}` (from {a} and {b}) | import merging |
| E3108 | duplicate label `{label}` / missing `goto` target | control-flow resolution |
| E3109 | illegal `goto`: {reason} (jump into a deeper block / across initialization / across onexit / across functions) | goto rules |
| E3110 | missing `main` or signature must be `fn main() -> i64` or `fn main() -> ()` | entry-point check |
| E3111 | `static` initializer must be compile-time evaluable | §4 |
| E3112 | `{kw}` is forbidden inside `onexit` | §10 |
| E3113 | unused local/import `{name}` (can be disabled) | warning W3101, can be promoted |

## Types (E4xxx)

| Code | Message template | Trigger |
| --- | --- | --- |
| E4001 | type mismatch: expected `{expected}`, found `{actual}` | assignment / return / argument |
| E4002 | cannot infer the type of the literal/expression (annotation required) | no context |
| E4003 | implicit conversion `{from}` → `{to}` is not allowed (use `as`) | implicit-conversion rules |
| E4004 | `as` does not support `{from}` → `{to}` | §5.7 |
| E4005 | operator `{op}` does not support type `{type}` | operator check |
| E4006 | dereference of non-pointer type `{type}` | `.*` |
| E4007 | write through read-only pointer `^ro {T}` | §5.3 |
| E4008 | array length must be a non-negative compile-time integer (found {v}) | type |
| E4009 | bitfield width exceeds the underlying type `{type}` (total {sum} > {bits}) | bits |
| E4010 | union field type cannot contain non-trivial construction (other than pointer/scalar) | union restriction (Stage 4) |
| E4011 | recursive struct definition without a pointer break: `{name}` | infinite size |
| E4012 | duplicate enum discriminant `{value}` | explicit discriminant |
| E4013 | enum mixes payload and payload-less variants with discriminants | enum rules |
| E4014 | function argument count mismatch: expected {n}, found {m} | call |
| E4015 | default arguments may only be omitted from right to left | call |
| E4016 | varargs are only allowed on `extern "C"` declarations | function declaration |
| E4017 | `Outcome`/closures/generic instances are not allowed across FFI | FFI validation |
| E4018 | `panic` is forbidden in `extern "C"` exported functions (return an error code) | §11 |
| E4019 | `try` requires `Outcome`, found `{type}` | §9 |
| E4020 | `try` error type `{E}` cannot convert to `{E2}` | §9 |
| E4021 | `match` arm types differ: `{a}` vs `{b}` | expression |
| E4022 | non-exhaustive match; missing: `{patterns}` | §7 |
| E4023 | unreachable arm (covered by an earlier pattern) | warning W4201 |
| E4024 | guard expression must be `bool` | match |
| E4025 | function name cannot be used as a value (use `&{name}`) | §5.3 |
| E4026 | bare function body only allows `asm`/`trap` | bare |
| E4027 | no implicit conversion between `fn c` and `fn` (explicit wrapper required) | function pointer |

## Generics / constants (E5xxx)

| Code | Message template | Trigger |
| --- | --- | --- |
| E5001 | generic argument count mismatch: expected {n}, found {m} | instantiation |
| E5002 | type argument does not satisfy the value constraint on `{param}` (requires `{req}`) | value parameter |
| E5101 | constant evaluation failed: {reason} | const |
| E5102 | constant expression contains a forbidden operation `{op}` (allocation/IO/asm/pointer dereference) | §13 |
| E5103 | compile-time division by zero | const |
| E5104 | array length/bit width is not constant | type |
| E5201 | instantiation depth exceeds the limit ({n}); possible infinite recursion | generics |
| E5202 | instantiation failed: `{item}[{args}]` requires `{req}`, in `{chain}` | full instantiation chain |
| E5203 | generic member check failed: `{type}` is missing `{member}` | instantiation point |

## IR / encoding / assembler (E6xxx, Stage 5+)

| Code | Message template | Trigger |
| --- | --- | --- |
| E6001 | IR verification failed: {detail} (block {bb}) | internal |
| E6002 | unreachable basic block has side effects (kept conservatively) | warning W6001 |
| E6101 | invalid assembly template: {detail} (line {n}) | inline assembly |
| E6102 | constraint not satisfied: `{constraint}` used for `{operand}` | asm |
| E6103 | clobber list missing `{reg}` (written by the template) | asm check |
| E6104 | unsupported instruction `{mnemonic}` (target {arch}) | asm |
| E6201 | register allocation failed (cannot spill) | backend internal |
| E6202 | stack frame exceeds limit: {bytes} bytes | backend |

## Linking / object files / debug info (E7xxx, Stage 7/9)

| Code | Message template | Trigger |
| --- | --- | --- |
| E7001 | undefined symbol `{symbol}` (referenced from {loc}) | linking |
| E7002 | duplicate symbol definition `{symbol}` ({a} and {b}) | linking |
| E7003 | relocation overflow: {type} out of range | relocation |
| E7004 | overlapping section / illegal alignment: {detail} | layout |
| E7005 | unsupported object format: {fmt} | output |
| E7006 | missing entry point | PE/ELF |
| E7101 | DWARF line-table generation failed: {detail} | debug |
| E7102 | source path unavailable (build reproducibility) | warning W7101 |

## Runtime (E8xxx)

| Code | Message template | Trigger |
| --- | --- | --- |
| E8001 | null pointer dereference ({func} @ {loc}) | checks enabled |
| E8002 | integer division by zero ({func} @ {loc}) | checked/trap |
| E8003 | array out of bounds: index {i}, length {n} ({func} @ {loc}) | checks enabled |
| E8004 | stack overflow / recursion too deep ({func}, depth {n}) | stack guard |
| E8005 | misaligned access: address {addr} requires {align} | checks enabled |
| E8006 | allocation failed: {bytes} bytes (allocator {name}) | allocator |
| E8007 | double free / invalid free {ptr} | allocator check |
| E8008 | `panic`: {msg} ({func} @ {loc}) | panic |
| E8009 | assertion failed: {expr} ({func} @ {loc}) | assert |
| E8010 | `onexit` skipped during panic (warning) | warning W8010 |

## Driver / IO (E9xxx)

| Code | Message template | Trigger |
| --- | --- | --- |
| E9001 | failed to open input file: {path} (win32={code}) | implemented in Stage 0 |
| E9002 | failed to read input file: {path} | Stage 0 |
| E9003 | source file exceeds the {limit} limit | Stage 0 |
| E9004 | failed to create output file: {path} | Stage 0 |
| E9005 | failed to write output file: {path} | Stage 0 |
| E9006 | invalid command-line argument: {detail} (see --help) | Stage 0 |
| E9007 | compiler memory allocation failed | Stage 0 |
| E9008 | internal error: {detail} (attach a minimal repro) | Stage 0 |
| E9009 | error count exceeds the limit ({n}); compilation aborted | Stage 0 |
| E9010 | unsupported target platform/format: {target} | Stage 7 |

## Warnings (Wxxxx)

| Code | Message | Default |
| --- | --- | --- |
| W1001 | untyped integer defaults to i64 | warning |
| W3101 | unused local variable/import | warning |
| W3102 | nested block shadows `{name}` | warning |
| W3201 | unreachable code | warning |
| W4201 | unreachable `match` arm | warning |
| W5201 | type larger than 64 bytes passed by value | warning |
| W5202 | tail-call signatures incompatible; no TCO | warning |
| W6001 | optimizer kept an unreachable block with side effects | warning |
| W7101 | debug info contains an absolute build-machine path | warning |

---

## Stage 0 mapping (migration table)

| Stage 0 message | New code |
| --- | --- |
| invalid character | E1001 |
| integer literal out of i64 range | E1004 |
| unterminated block comment | E1003 |
| string literals not supported in Stage 0 | E1002 (strings arrive in Stage 2) |
| expected `X` | E2001 |
| expected identifier | E2002 |
| expected type name | E2003 |
| Stage 0 only supports i64 | removed when the Stage 4 type system lands; merged into E4001 |
| duplicate function definition | E3103 |
| duplicate parameter name | E3103 |
| duplicate local variable (Stage 0 forbids shadowing) | E3103 + W3102 (Stage 4 allows nested shadowing) |
| undefined identifier | E3101 |
| undefined function | E3101 |
| argument count mismatch | E4014 |
| print is a builtin name | removed when Stage 8 moves print to the standard library |
| Stage 0 supports at most four parameters | removed when Stage 6 extends the ABI |
| function name cannot be used as a value | E4025 |
| missing main function | E3110 |
| failed to open input file | E9001 |
| memory allocation failed | E9007 |
| error count exceeds the limit | E9009 |
| internal error | E9008 |

---

## Implementation constraints (effective from Stage 2)

- Diagnostics use the structured `Diagnostic{code, severity, span, message, notes[], related[]}` object; rendering and collection are separate. Formatting, LSP, and documentation share the same structure.
- Every diagnostic must serialize to both JSON (LSP) and human-readable text with equivalent content.
- Error recovery must not create cascading noise: the same location and cause are reported once. After an undefined name is reported, its uses do not repeat type errors.
- The default limit is 32 diagnostics (`--max-errors` adjusts it). Reaching the limit emits E9009 and terminates.
- Exit codes: 0 success; 1 compile error (any E-level diagnostic); 2 driver/usage error; 3 internal/resource failure; 4 runtime panic. A generated program's own exit code is defined by that program; runtime panic is fixed at 4.
