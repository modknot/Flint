# Language Specification Draft v0.1 (Stage One Deliverable I)

Status: **draft, not frozen**. This document describes the full target language, not only the subset implemented in Stage 0. The Stage 0 subset must remain compatible with this specification (see §17).
Working name: `Flint`. Extension: `.fl`. Goal: a systems-level language with predictable semantics, zero-overhead abstractions, and no mandatory runtime.

---

## §1 Basic conventions

- Source files are UTF-8 (with or without BOM) and use `\n` or `\r\n` line endings. The compiler records positions as byte offsets.
- Every token carries a span: `{file_id, byte_start, byte_end, line, col}`. Lines and columns are 1-based; columns are display columns (tabs expand to four columns, UTF-8 continuation bytes have width 0).
- Keywords and identifiers are case-sensitive; no case folding is performed.
- "Must" and "must not" are normative. "Should" diagnostics are warnings and may be promoted to errors by compiler options.

---

## §2 Lexing

### §2.1 Identifiers and keywords

An identifier starts with `XID_Start` or `_`, followed by `XID_Continue` (Unicode 15.0). A lone `_` is not an identifier; it is the pattern wildcard.
Identifiers are normalized to NFC before comparison and output. Different normalization forms are the same name; diagnostics mention the original code points.

Reserved keywords:

```text
fn let const static struct union enum bits type impl operator
import pub pkg priv as
if else while for in step match
break continue goto label return onexit
true false null
and or not xor shl shr
asm volatile
extern link export
try panic
```

Contextual keywords, valid as ordinary identifiers outside their specific positions: `auto`, `c`, `packed`, `bare`, `mut`, `ro`, `erased`.

### §2.2 Literals

- Integers: `0b`, `0o`, `0x`, or decimal, with optional `_` separators (no doubled `_`, no leading/trailing `_`). Optional suffixes: `i8 i16 i32 i64 u8 u16 u32 u64`.
  An unsuffixed integer is an untyped integer constant and needs context. Without context it defaults to `i64` with warning W1001.
  Range checks run at compile time; overflow is E1004.
- Floats: decimal fraction or exponent form, with optional `f32`/`f64`; unsuffixed defaults to `f64`. No implicit precision conversion.
- Booleans: `true` / `false`.
- Characters: `'x'`, with escapes `\n \r \t \\ \' \" \0 \xNN \u{...}`. Type `char` is a Unicode scalar value, excluding surrogate code points.
- Bytes: `b'x'`, type `byte`.
- Strings: `"..."` with ordinary escapes; raw strings `r"..."` (no escapes, `""` is one quote); multiline strings `"""..."""` preserve internal newlines and strip the shortest common indentation. The type is `str` (§5.6); literals live in a read-only constant pool with no copy.
- `null`: the only null-pointer literal. It may only be assigned to or compared with pointer types.

### §2.3 Comments

`//` line comments; `/* */` block comments with **nesting**; `///` documentation comments attached to the next declaration; `//!` module-level documentation.
Comments stay in a side table attached to the token stream, not in the grammar, for formatting, documentation, and LSP use.

### §2.4 Lexical errors and recovery

Invalid character: E1001, skip one byte and continue. Unterminated block comment: E1003, advance to EOF. Unterminated string: E1002, advance to end of line.
Numeric literal without digits: E1005. Overflow: E1004, skip remaining digits.
A lexical error does not terminate compilation by itself; the default limit is 32 errors, configurable.

---

## §3 Grammar (EBNF)

Conventions: `{ }` means 0..n, `[ ]` optional, `( )` grouping, `'x'` terminal, `(* *)` comment. EBNF defines shape only; semantics follow later sections.

```ebnf
program      = { item } EOF ;

item         = import_decl | fn_decl | struct_decl | union_decl | enum_decl
             | bits_decl | type_alias | const_decl | static_decl
             | extern_block | impl_block | link_decl ;

import_decl  = 'import' path [ 'as' ident ] ';'
             | 'import' path '::' '*' ';' ;
path         = ident { '::' ident } ;

vis          = [ 'priv' | 'pkg' | 'pub' ] ;            (* default priv *)

fn_decl      = vis [ 'extern' string ] [ 'bare' ] 'fn' ident [ type_params ]
               '(' [ params ] ')' [ '->' type ] ( block | ';' ) ;
params       = param { ',' param } [ ',' '...' ] ;
param        = ident ':' type [ '=' expr ] ;
type_params  = '[' type_param { ',' type_param } ']' ;
type_param   = ident [ ':' const_expr ] ;               (* value parameter for array length *)

struct_decl  = vis 'struct' [ layout_kw ] ident [ type_params ] '{' [ field_list ] '}' ;
layout_kw    = 'auto' | 'c' | 'packed' ;
field_list   = field { ',' field } [ ',' ] ;
field        = ident ':' type ;

union_decl   = vis 'union' ident '{' field_list '}' ;
enum_decl    = vis 'enum' ident [ type_params ] '{' variant { ',' variant } [ ',' ] '}' ;
variant      = ident [ '(' [ type_list ] ')' ] [ '{' field_list '}' ] ;
bits_decl    = vis 'bits' ident ':' type '{' bitfield { ',' bitfield } '}' ;
bitfield     = ident ':' const_expr ;                  (* bit width *)

type_alias   = vis 'type' ident [ type_params ] '=' type ';' ;
const_decl   = vis 'const' ident ':' type '=' expr ';' ;
static_decl  = vis 'static' [ 'mut' ] ident ':' type '=' expr ';' ;

extern_block = vis 'extern' string [ 'lib' string ] '{' { extern_fn } '}' ;
extern_fn    = 'fn' ident '(' [ params ] ')' [ '->' type ] ';' ;

impl_block   = 'impl' type '{' { impl_item } '}' ;
impl_item    = fn_decl | operator_decl ;
operator_decl= 'operator' op_token '(' params ')' [ '->' type ] block ;

link_decl    = 'link' string ';' ;

type         = prim_type | tuple_type | array_type | slice_type | ptr_type
             | fn_type | path_type | '(' ')' ;
prim_type    = 'i8'|'i16'|'i32'|'i64'|'u8'|'u16'|'u32'|'u64'|'f32'|'f64'
             | 'bool'|'char'|'byte'|'unit'|'never' ;
tuple_type   = '(' type ',' [ type_list ] ')' ;
type_list    = type { ',' type } ;
array_type   = '[' type ';' const_expr ']' ;
slice_type   = '[' type ']' ;                          (* view: ptr + len *)
ptr_type     = '^' [ 'ro' ] type ;
fn_type      = 'fn' [ conv ] '(' [ type_list ] ')' [ '->' type ] ;
conv         = 'c' | 'bare' | 'flint' ;
path_type    = path [ type_args ] ;
type_args    = '[' type { ',' type } ']' ;

block        = '{' { stmt } [ expr ] '}' ;             (* final expression is the block value *)
stmt         = let_stmt | const_stmt | assign_or_expr_stmt
             | if_stmt | while_stmt | for_stmt | match_stmt
             | return_stmt | break_stmt | continue_stmt
             | goto_stmt | label_stmt | onexit_stmt | asm_stmt ;

let_stmt     = 'let' pattern [ ':' type ] [ '=' expr ] ';' ;
const_stmt   = 'const' ident ':' type '=' expr ';' ;
assign_or_expr_stmt = expr ';' ;

if_stmt      = 'if' expr block [ 'else' ( if_stmt | block ) ] ;
while_stmt   = 'while' expr block ;
for_stmt     = 'for' pattern 'in' expr [ 'step' expr ] block ;
match_stmt   = 'match' expr '{' arm { ',' arm } [ ',' ] '}' ;
arm          = pattern [ 'if' expr ] '=>' ( block | expr ) ;
return_stmt  = 'return' [ expr ] ';' ;
break_stmt   = 'break' [ ident ] ';' ;
continue_stmt= 'continue' [ ident ] ';' ;
goto_stmt    = 'goto' ident ';' ;
label_stmt   = 'label' ident block ;
onexit_stmt  = 'onexit' block ;
asm_stmt     = 'asm' [ 'volatile' ] '(' string [ asm_ops ] ')' ';' ;
asm_ops      = ':' asm_out { ',' asm_out } [ ':' asm_in { ',' asm_in } [ ':' clobber_list ] ] ;

expr         = assign_expr ;
assign_expr  = or_expr [ assign_op assign_expr ] ;     (* right-associative *)
assign_op    = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '|=' | '&=' | 'xor=' | 'shl=' | 'shr=' ;
or_expr      = and_expr { 'or' and_expr } ;
and_expr     = bor_expr { 'and' bor_expr } ;
bor_expr     = bxor_expr { '|' bxor_expr } ;
bxor_expr    = band_expr { 'xor' band_expr } ;
band_expr    = eq_expr { '&' eq_expr } ;
eq_expr      = rel_expr { ( '==' | '!=' ) rel_expr } ;
rel_expr     = range_expr { ( '<' | '<=' | '>' | '>=' ) range_expr } ;
range_expr   = add_expr [ '..' add_expr ] ;             (* half-open [a,b) *)
add_expr     = mul_expr { ( '+' | '-' ) mul_expr } ;
mul_expr     = shift_expr { ( '*' | '/' | '%' ) shift_expr } ;
shift_expr   = unary_expr { ( 'shl' | 'shr' ) unary_expr } ;
unary_expr   = ( '-' | 'not' | '^' | 'try' | 'panic' ) unary_expr | postfix_expr ;
postfix_expr = primary { postfix } ;
postfix      = '(' [ args ] ')' | '[' expr ']' | '.' ident | '.' const_int
             | '.*' | 'as' type | '::' '[' type { ',' type } ']' ;

args         = expr { ',' expr } [ ',' '...' ] ;
primary      = literal | path | '(' expr ')' | block | if_stmt | match_expr
             | closure | '.' const_int | 'null' | 'true' | 'false' ;
closure      = 'fn' '(' [ params ] ')' [ '->' type ] block ;   (* capture rules in §8.4 *)
match_expr   = 'match' expr '{' arm { ',' arm } [ ',' ] '}' ;

pattern      = '_' | ident | literal | tuple_pat | struct_pat | enum_pat
             | array_pat | range_pat | or_pat | '(' pattern ')' ;
tuple_pat    = '(' [ pattern { ',' pattern } ] ')' ;
struct_pat   = path '{' [ ident [ ':' pattern ] { ',' ident [ ':' pattern ] } ] '}' ;
enum_pat     = path [ '(' [ pattern { ',' pattern } ] ')' ] ;
array_pat    = '[' [ pattern { ',' pattern } [ ',' '..' [ ident ] ] ] ']' ;
range_pat    = const_expr '..' const_expr ;
or_pat       = pattern '|' pattern ;
```

Parsing rules:

- Expressions use Pratt parsing with the fixed precedence table in §6.2. New operators change only the table. Assignment and `..` are right-associative/non-associative as marked; other binary operators are left-associative.
- Generic arguments: types use `T[a, b]`; explicit instantiation in expression position **must** use `f::[a, b](...)`. A bare `f(...)` only performs inference. This removes ambiguity between `[`/indexing and `<`/comparison without backtracking.
- `.*` versus `.`: match `.` first; if immediately followed by `*` and the next character is not an identifier start, reduce to `.*` with one token of lookahead.
- Statement/expression ambiguity: when `if`, `match`, or a block appears in statement position and is followed by `;`, treat it as an expression statement; otherwise treat it as a statement.
- Syntax-error synchronization: statement boundaries (`;`, `}`, `fn`), parameter boundaries (`,`, `)`, `{`), type-argument boundary (`]`), and function boundary (next `fn`). One compilation may report multiple errors.

---

## §4 Declarations, scope, visibility, initialization

- **A file is a module.** The module name is the file basename without `.fl`; directories form namespaces. `import` is explicit; there is no implicit global namespace.
- Visibility: default `priv` (module only); `pkg` (visible anywhere in the same namespace tree); `pub` (exported). Accessing a `priv` item across modules is E3102.
- Name resolution order: local → parameter → module item → imported item. Four namespaces are independent: values/functions, types, modules, labels.
- Locals must be declared before use. Module items (functions/types/const/static) are order-independent within a module (two-pass parsing).
- Shadowing: duplicate names in the same block are forbidden (E3103). Nested blocks may shadow, with warning W3102. A parameter may not share a local's name.
- `static` initializers must be compile-time evaluable. Runtime initialization and implicit lazy initialization are forbidden. When runtime initialization is required, call an explicit `init()` pattern and let the caller order it. This removes initialization-order uncertainty and hidden side effects; the cost is that some constant tables need hand-written initializer functions.
- `const` is evaluated at compile time; failure is E4101. `static mut` reads and writes are not automatically synchronized; cross-thread use is the developer's responsibility (atomic types arrive in Stage 11).

---

## §5 Type system

### §5.1 Primitive types

| Type | Width | Description |
| --- | --- | --- |
| `i8/i16/i32/i64` | 8/16/32/64 | two's-complement signed; overflow policy is per option or scope (§6.3) |
| `u8/u16/u32/u64` | 8/16/32/64 | unsigned |
| `f32/f64` | 32/64 | IEEE-754; no implicit precision promotion |
| `bool` | 1 byte storage | only `true`/`false`; `bool as u8` is explicit |
| `char` | 4 bytes | Unicode scalar value (0..=0x10FFFF excluding surrogates); out-of-range construction is an error |
| `byte` | 1 | raw byte; explicit conversion to/from `u8` |
| `unit` | 0 | written `()`, the type of a value-less block |
| `never` | 0 | written `!`, the result type of `return`/`panic`/infinite loops |

### §5.2 Composite types

- Tuples `(T1, T2, ...)`: anonymous, structurally equivalent; access with `.0`, `.1`.
- Arrays `[T; N]`: N is a compile-time constant; value semantics, copied on assignment/passing. Passing a value larger than 64 bytes emits warning W5201 but is not forbidden.
- Slices `[T]`: a `{ptr, len}` view that owns no memory and has no lifetime checking. Bounds checks are described in §12.
- Structs: `struct` defaults to `auto` layout (the compiler may reorder fields for alignment); `struct c` uses the C ABI layout; `struct packed` has no padding (`align = 1`).
- Unions: all fields share offset 0; size is the maximum field size after alignment. Reading a field other than the last written one produces an **indeterminate value**, not undefined behavior, but the value is unspecified; documentation must state this.
- Bitfields: `bits Name: uN { a: w, ... }`; total width may not exceed the underlying type. Cross-byte boundaries use little-endian bit order. `f.a` has type `bool` (set bit means true) and is writable. `Name::from_bits(v: uN) -> Name` constructs; `Name::bits(f) -> uN` returns the raw value. An oversized field is E4009.
- Enums: payload-less and payload variants (`V(T)` or `V{ x: T }`). Discriminants are explicit only for payload-less variants (`A = 1`); otherwise the compiler assigns them in declaration order.

### §5.3 Pointers and function types

- `^T`: mutable raw pointer, may be `null`, no aliasing or lifetime checks. `^ro T`: read-only view; writes through it are forbidden, and `^T` implicitly narrows to it.
- Dereference with `p.*`; take address with `^expr` on an lvalue. Pointer arithmetic `p + n` and `p - n` is allowed only on `^T`/`^ro T`, in element-size units. Pointer subtraction yields an `i64` element difference.
- Integer ↔ pointer conversions require explicit `as`. MMIO example: `(0xFFFF_FF00_0000_0000 as ^u32).*`.
- Function types: `fn(T1, T2) -> R` (Flint convention), `fn c(...)` (C ABI), `fn bare(...)` (frameless bare function, body limited to inline assembly/`asm`).
- Conversion from a function item to a function pointer is explicit: `&f as fn(i64) -> i64`.

### §5.4 Type aliases and opaque types

`type Name = T;` is fully transparent. `type Name = opaque;` (Stage 8) is an opaque handle that may only be passed by pointer; dereference and arithmetic are forbidden.

### §5.5 Generics

- Syntax: `fn f[T, N: usize](...)`, `struct Box[T]`, `enum Opt[T]`, `type Pair[T] = (T, T)`.
- Instantiation: type position `Box[i64]`; expression position explicit `f::[i64](x)`; otherwise infer from arguments.
- **Constraint model**: no static trait or constraint declarations. A generic body is checked against the actual type at instantiation; required members/operators must exist at that point. Diagnostics print the full instantiation chain: `f[i64] -> g[i64] -> requires T: op_add`.
  Trade-off: minimal syntax and no trait-system complexity; the cost is later error discovery and the need to retain the full generic AST, which affects incremental compilation and binary size.
- Monomorphization is the default and zero-overhead. An `erased` parameter (`fn log[T: erased]`) is opt-in type erasure through an explicit vtable argument (Stage 11; cost: indirect calls and no inlining).

### §5.6 `str`

`str` is `{ ^ro byte, u64 len }`, UTF-8. Byte and character indexing are separate: `s.len_bytes`, `s.char_count()` (O(n)); index with `s.byte(i)` or `s.char(i)`; `s[i]` is forbidden because it would hide the choice. Concatenation/slicing returns a new `str` view or a standard-library `String`; there is no implicit heap allocation.
Public fields: `ptr` (`^ro byte`) and `len` (byte count), directly usable by FFI; both are read-only.

### §5.7 Explicit conversions

All implicit numeric conversions are forbidden, including widening `i32 → i64`. `as` allows numeric truncation/sign changes, `bool → integer`, `char ↔ u32`, pointer ↔ integer, pointer-type casts, and enum discriminant ↔ integer.
`as` does **not** allow struct ↔ integer, array ↔ pointer (use a `cast` builtin), or float ↔ pointer. Out-of-range values and precision loss are the developer's responsibility; debug builds may insert checks behind an option.

### §5.8 Core builtins (no runtime dependency)

`alloc(size: u64, align: u64) -> ^byte`, `free(p: ^byte)`, `realloc(p: ^byte, size: u64, align: u64) -> ^byte` (the allocator is replaceable through `alloc_with(alloc: ^Allocator, ...)`, where `Allocator` is a function-pointer struct);
`copy_bytes(dst: ^byte, src: ^ro byte, n: u64)`, `zero_bytes(p: ^byte, n: u64)`;
`size_of(T) -> u64`, `align_of(T) -> u64` (compile-time constants); `trap() -> !`; `uninit(T) -> T` (explicitly uninitialized; it must be written before reading, otherwise the read is undefined behavior).
These are the only core builtins. They do not depend on an operating system; the standard library builds containers, strings, and IO on top.

---

## §6 Expressions and operators

### §6.1 Block expressions

`{ stmt* expr? }` evaluates to its final expression, or `()` when absent. If `return`/`break`/`goto` exits early, the block type is `!`.

### §6.2 Precedence table (fixed, not user-extensible)

| Level | Operators | Associativity |
| --- | --- | --- |
| 1 | `=` `+=` `-=` `*=` `/=` `%=` `\|=` `&=` `xor=` `shl=` `shr=` | right |
| 2 | `or` | left |
| 3 | `and` | left |
| 4 | `\|` | left |
| 5 | `xor` (bitwise) | left |
| 6 | `&` | left |
| 7 | `==` `!=` | left |
| 8 | `<` `<=` `>` `>=` | left |
| 9 | `..` | non-associative |
| 10 | `+` `-` | left |
| 11 | `*` `/` `%` | left |
| 12 | `shl` `shr` | left |
| 13 | prefix `-` `not` `^` `try` `panic` | right |
| 14 | postfix `()` `[]` `.` `.*` `as` `::[]` | left |

### §6.3 Semantic rules

- `and`/`or` short-circuit; `not` is boolean-only.
- `& | xor shl shr` are integer-only. The shift amount may be any integer; an oversized amount is reduced modulo the bit width (`shift % bits`), not undefined behavior.
- `==`/`!=` compare structs/arrays/tuples field by field (all field types must be comparable). Floating-point NaN follows IEEE (`NaN != NaN`); use `bit_eq` for bitwise comparison.
- `..` produces `Range[T]`, a half-open interval `[a, b)`. `for i in a..b` is a numeric loop; overflow checks apply in debug mode.
- Integer overflow policy (per scope or compiler option): `wrap` (default, silent wrapping), `trap` (runtime panic), `error` (compile-time error when constants make it decidable). Set it with an `overflow(wrap|trap|error)` block or module-level option, not on each expression.
- Integer division by zero panics in `checked` mode (E8002); in release mode it is undefined behavior and must be documented. Floating-point division follows IEEE.

### §6.4 Operator overloading

Allowed operators: `+ - * / %`, `== != < <= > >=`, `[]` (index), `.*` (dereference), `()` (call). Assignment, logical, bitwise, `as`, `..`, and precedence cannot be overloaded.
Form: `impl Type { operator + (self: Type, rhs: Type) -> Type { ... } }`; `self` is a value or pointer according to the signature. Compound assignment expands as `a op= b` → `a = a op b`; no in-place optimization until the Stage 5 IR.
Cost: overloads make `+` type-dependent, so generated documentation must list each type's operator table; binary size grows with implementations.

---

## §7 Statements and control flow

- `if`/`while` conditions must be `bool`; no implicit truthiness.
- `for p in e`: when `e` is `Range[T]`, it is a numeric loop with no iterator allocation. Otherwise `e` must be iterable (`iter()` returns an iterator with `next`; standard library in Stage 8). `step` is only valid on numeric loops.
- `break`/`continue` may carry labels. `label name block` introduces a label scoped to that block.
- `match` must be exhaustive. For enums, every variant must be covered (or a `_`/binding fallback must exist). For integers, a missing `_` is reported as non-exhaustive. Missing patterns are listed in E5203? Use E4022 for the missing-pattern diagnostic; E5203 is for generic member checks.
- Names bound in a guard `if` are visible in that arm. A guard may not contain control flow other than side effects (no `return`).
- `goto` is strictly constrained (all conditions must hold, otherwise E3205): same function; target label in an outer or same-level block; no jump into a deeper block; no jump across an initialized `let`/`const`; no jump across an `onexit` scope; no jump into a `match` arm or loop body. Intended uses are kernel error paths, state machines, and performance-critical tail merges. Every `goto` must document its reason.
- Loop/recursion depth: `--stack-guard` inserts a counter at function entry and panics when exceeded (E8004). Off by default (zero overhead).

---

## §8 Functions and calling conventions

### §8.1 Calling conventions

- `flint` (default): integer/pointer arguments in `rdi,rsi,rdx,rcx,r8,r9`, floats in `xmm0..xmm7`, return in `rax`/`xmm0`; caller cleans the stack; 16-byte alignment; shadow space only on Windows targets.
- `c`: the target platform C ABI (Windows x64 / System V AMD64), for FFI.
- `bare`: no prologue/epilogue; body only allows `asm` and constant returns; used for interrupt entries and context switches.
- Custom conventions `fn conv(name) ...` arrive in Stage 8 (the declaration supplies the register table); this version only reserves the syntax.

### §8.2 Parameters

- Default arguments: `fn f(a: i64, b: i64 = 10)`; omit from right to left; defaults must be compile-time evaluable. Default arguments are forbidden across FFI.
- Varargs: only `extern "C"` declarations may use `...`. Flint functions do not support varargs; use slices or structs. When calling C varargs, float arguments follow C promotion rules (`f32→f64`), with explicit conversion at the call site.
- Passing: small types (≤16 bytes and no destructor) pass by value. Large types still copy by value (no implicit references); the compiler emits performance warning W5201.
- Return values: ≤16 bytes in registers; larger values use a hidden return pointer allocated by the caller, as defined by the ABI.

### §8.3 Tail calls

`return f(x);` guarantees tail-call optimization when signatures are compatible (same argument/return layout and convention), independent of optimization level. Incompatible signatures emit W5202. `tail return f(x);` forces TCO (reserved for Stage 6). When a stack guard is active, `tail` calls do not increment the counter.

### §8.4 First-class functions and closures

Function items may be used as values with an explicit function-pointer conversion. Closure syntax: `fn(a: i64) -> i64 { ... }`.
Capture rules:
- By default, captured outer locals are copied by value. For reference capture, write `fn[^] (...) {...}`; the pointer's lifetime is the developer's responsibility.
- A closure value is `{ fn_ptr, env_ptr }`. The environment is allocated on the stack by default (non-escaping) or on the heap with explicit `heap fn...` using the current allocator.
- No implicit boxing and no GC.

### §8.5 Bare functions

A `bare fn` may not contain `let`, expression statements, or `return` values; only `asm` and `trap` are allowed. The ABI is entirely the developer's responsibility.

---

## §9 Error handling

- Core type `Outcome[T, E]` (`enum { ok(T), err(E) }`). No exceptions and no stack unwinding by default; unwinding is an optional library feature.
- Propagation: `try expr` on an `Outcome` yields `v` for `ok(v)` and immediately returns `err(e)` for `err(e)`. The current function must return `Outcome[_, E2]` and `E` must convert to `E2`, otherwise E4202.
- Error context: the standard-library `Context` wrapper (`err.with(msg)`) forms an error chain. `Outcome` never allocates implicitly; the caller builds chains explicitly.
- `panic(msg)` terminates immediately (via `trap` or a platform panic handler) without unwinding. Kernels may use `trap()` directly. Panic messages and locations live in read-only constants and can be removed with `--no-panic-msg`.
- FFI boundary: `Outcome` may not cross a C boundary; convert it to a return code or out-parameter as defined in Stage 8.

---

## §10 Resource management (no RAII)

- Scope hooks: `onexit { ... }` runs in **reverse order** when leaving scope (normal exit, `return`, `break`, and `goto`). `panic` does **not** run hooks by default; `--onexit-on-panic` enables it.
  `onexit` may not contain `return`/`break`/`goto` (E3207). It may not capture resources other than outer mutable references; there is no borrow checker, only this rule.
- Explicit release: `free(p)`, `close(fd)`, and similar core/standard-library calls. No automatic destruction.
- Optional wrapper library: an `Auto[T]` template in the standard library registers release through `onexit`; it is not part of the language core.
- Diagnostics: `--leak-report` in debug builds uses allocator accounting to find leaks; release builds have zero overhead.

---

## §11 Modules, FFI, and linking

- Modules: a file is a module; directories are namespaces; `import a::b;`. Cyclic dependencies are E3106 and print the full cycle path (`a -> b -> c -> a`).
- `extern "C" { fn ... }` calls C. `extern "C" lib "kernel32" { ... }` names the library. `pub extern "C" fn` exports to C.
- Strings across the boundary: C `char*` and `^ro byte` require explicit `cstr_to_str` / `str_to_cstr`; the latter allocates and ownership goes to the caller.
- Memory ownership: memory allocated across FFI must be freed by the module that allocated it. Every extern declaration must document `alloc_by`.
- Linking C static libraries: `link "foo.lib";` is resolved by the internal linker in Stage 7. Stage 0 does not support it.
- Panic across the boundary is forbidden. Panic in a C callback is undefined behavior (E4205); return an error code instead.

---

## §12 Memory model and undefined behavior

Explicit undefined behavior (the compiler may exploit it; documentation must list it):

- Dereferencing `null`, a freed pointer, or an out-of-bounds pointer when checks are disabled.
- Data races: non-atomic concurrent access to the same memory with at least one write.
- Integer division by zero outside `checked` mode; `i64::MIN / -1`.
- A negative shift count; `match` on an invalid enum discriminant not covered by an arm.
- Calling-convention mismatch or incorrect stack alignment at the ABI layer.
- Writing through `^ro` despite the read-only promise (for example through an alias); the implementation does not guarantee detection.
- Reading uninitialized memory (`let x: i64;` is forbidden; initialize it or use the explicit `uninit` builtin).

Indeterminate but not undefined: reading an inactive union field; padding bytes; uninitialized `static` data (which is guaranteed zero-initialized).

Optional runtime checks, off by default: array/slice bounds, null dereference, alignment, integer overflow (`trap` policy), and allocator poisoning.

---

## §13 Compile-time evaluation

`const` and `static` initializers, array lengths, `bits` widths, `case` constants, and generic value parameters must be compile-time evaluable.
Allowed constant expressions: literals, arithmetic/bitwise operations, comparisons, `if`, blocks, `const fn` calls, struct/array construction, and `as`.
Forbidden: pointer dereference (except constant addresses), heap allocation, IO, `asm`, and `panic` (unless used as a compile-time error).
Cost: `const fn` requires an interpreter (Stage 5). Constant data is deduplicated and not duplicated in the binary.

---

## §14 Inline assembly

Syntax: `asm [volatile] ("template" : out(reg) = expr, ... : in(expr), ... : clobber("rax","cc"), ...);`

- Template placeholders `{0}`, `{1}`, ... bind to operands; `{{`/`}}` are literal braces.
- Dialect: Intel syntax; the instruction set is target-defined (x86-64 subset in Stage 8, ARM64 later).
- Constraints: `reg` (general), `reg8/16/32/64`, `mem`, `imm`. Clobbers must explicitly list modified registers plus `cc` and `memory`.
- The compiler does not analyze asm semantics; `volatile` prevents deletion and reordering. Invalid encodings are reported by the internal assembler in Stage 8 (E6101).

---

## §15 Diagnostic format (details in `p1-errors.md`)

```text
<file>:<line>:<col>: error[E<code>]: <message>
  <line> | <source line>
         | <caret>
  note: <one actionable suggestion>
  see: <related definition location file:line:col>
```

- Compile-time errors must carry a span. Name-related errors must include the definition location.
- Generic instantiation errors must print the full instantiation chain (E5202).
- Runtime errors (panic/check failure) include `file:line:col`, the function name, and a call chain when `--runtime-trace` is enabled.

---

## §16 Feature cost table (design accounting)

| Feature | Benefit | Cost | Rejected alternative |
| --- | --- | --- | --- |
| No implicit conversions | predictable semantics | more verbose code | C-style implicit promotion (rejected: sign/precision bugs) |
| Unconstrained generic declarations | minimal syntax | late errors, retained AST, monomorphization growth | trait system (rejected: complexity and implementation cost) |
| Monomorphization by default | zero overhead | binary size and compile time | full type erasure (rejected: indirect calls) |
| No RAII | explicit lifetimes | manual release burden | destructors (rejected: implicit control flow and goto conflicts) |
| No borrow checker | no runtime cost, no learning curve | memory safety is the developer's responsibility | Rust-style borrowing (rejected: syntax and implementation complexity) |
| `onexit` hooks | controllable cleanup | panic semantics must be explicit | defer (shorter but similar; not adopted to avoid textual-replacement intuition) |
| `..` half-open ranges | unambiguous loops | requires a Range type | closed intervals (rejected: error-prone) |
| Nullable pointers | matches C/hardware | explicit null checks | Option wrapping (rejected: extra branches and ABI burden) |
| Single RWX section (Stage 0) | runs without relocations | no hardening | multiple sections plus a custom relocator (Stage 7) |

---

## §17 Compatibility with Stage 0

The Stage 0 implementation is a **prefix** of this specification: `fn`/`let`/`return`/`i64`/arithmetic/`print`/literals/comments all conform.
Known deviations, to be removed in Stage 2:

- `print` is a reserved builtin name. The specification treats it as a standard-library function; Stage 8 keeps the syntax but routes it through the library.
- Stage 0 error codes are unnumbered plain text; Stage 2 standardizes them as `E<code>`.
- Stage 0 lacks `const/static/struct/...`; the parser rejects them. The specification does not require Stage 0 to support them.
- Stage 0 resolves function names through a linked list; the specification does not constrain the implementation.
- Stage 0 emits a single RWX PE section; the specification allows it, and Stage 7 moves to multiple sections.

---

## §18 Open decisions

1. Default integer-overflow policy: `wrap` or `trap` (safety versus performance).
2. Whether `let x: i64;` may declare an uninitialized variable (currently forbidden; explicit `uninit` required).
3. Naming of the third visibility level: keep `pkg`, or use `pub(in ...)`.
4. Whether generic value-parameter syntax `[N: usize]` and array length `[T; N]` should both use `[N: u64]`.
5. Whether to keep `goto` (currently kept with strict constraints); if removed, kernel scenarios use state machines/`onexit`.
6. Whether `onexit` runs during panic by default (currently it does not).
7. Whether to adopt `{0}` placeholders and `[]` constraint syntax for inline assembly.
8. Whether the `str` character-index API names `byte/char` are accepted.
9. Whether to introduce `erased` generics (currently a Stage 11 placeholder).
10. Final language name and keyword set (renaming affects `.fl` files, `build-flintc.ps1`, and documentation).
