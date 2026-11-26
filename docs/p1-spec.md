# 语言规格草案 v0.1（阶段一交付物之一）

状态：**草案，未冻结**。冻结需项目负责人逐条签字；冻结后任何语义变更都必须附“影响评估”（已有规格、示例、阶段零代码）。
代号：`Flint`（正式名待定）。扩展名：`.fl`。目标：系统级高级语言，可控、可预测、零开销抽象、无强制运行时。

本文件是**目标语言**的完整规格骨架，不是阶段零已实现子集的描述。阶段零已实现的子集必须继续满足本规格（见 §18 兼容性）。

---

## §1 基本约定

- 源文件为 UTF-8（无 BOM 亦可），行终止 `\n` 或 `\r\n`；编译器内部统一按字节偏移记录位置。
- 所有词法单元携带 Span：`{file_id, byte_start, byte_end, line, col}`，行列 1 基，列按显示列（Tab 展开 4 列，UTF-8 续字节宽度 0）。
- 关键字、标识符大小写敏感；不做大小写折叠。
- “必须/禁止”为规范性要求；“建议”为诊断（warning），可由编译选项提升为错误。

---

## §2 词法

### §2.1 标识符与关键字

标识符：`XID_Start` 后接 `XID_Continue`（Unicode 15.0），允许 `_` 作为首字符（便于底层命名），禁止纯 `_`（`_` 是模式通配符）。
标识符规范化：源码按 **NFC** 归一后再比较与输出；不同归一形式视为同名，诊断中提示原始码位。
关键字（保留，不可作标识符）：

```
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

上下文关键字（仅在特定位置生效，可作普通标识符）：`auto`、`c`、`packed`、`bare`、`mut`、`ro`、`erased`。

### §2.2 字面量

- 整数：`0b`/`0o`/`0x`/十进制，允许 `_` 分隔（不得出现连续两个 `_` 或首尾 `_`）；可选后缀 `i8 i16 i32 i64 u8 u16 u32 u64`。
  无后缀时为“未定型整数常量”，必须有上下文类型；上下文缺失时**默认 i64**并给出提示（warning W1001）。
  编译期按目标类型做范围检查，越界为错误 E1004。
- 浮点：十进制小数/指数形式，后缀 `f32`/`f64`；无后缀默认 `f64`。不做隐式精度转换。
- 布尔：`true` / `false`。
- 字符：`'x'`，支持转义 `\n \r \t \\ \' \" \0 \xNN \u{...}`；类型 `char`（Unicode 标量值，非代理区）。
- 字节：`b'x'`，类型 `byte`。
- 字符串：`"..."`，普通转义；原始字符串 `r"..."`（无转义，`""` 表示一个引号）；多行字符串 `"""..."""`（保留内部换行，起始行缩进按最短公共前缀剥离）。
  类型为 `^ro byte` + 长度？否：字符串字面量类型是 `str`（见 §5.6），编译期放入只读常量池，零拷贝。
- `null`：唯一的空指针字面量，仅可赋给指针类型或与指针比较。

### §2.3 注释

`//` 行注释；`/* */` 块注释，**支持嵌套**；`///` 文档注释（附着到下一个声明），`//!` 模块级文档注释。
所有注释保留在 Token 流附属区（不进入语法），供格式化、文档生成、LSP 复用。

### §2.4 词法错误与恢复

非法字符：报 E1001，跳过 1 字节继续；未闭合块注释：报 E1003 并直接推进到 EOF；未闭合字符串：报 E1002，推进到行尾。
数字字面量无有效数字：E1005；溢出：E1004（跳过剩余数字字符）。
单词法错误不终止编译，上限 32 条后强制终止（可配置）。

---

## §3 语法（EBNF）

约定：`{ }` 表示 0..n，`[ ]` 表示可选，`( )` 分组，`'x'` 终结符，`(* *)` 注释。EBNF 只定义外形，语义见后续章节。

```ebnf
program      = { item } EOF ;

item         = import_decl | fn_decl | struct_decl | union_decl | enum_decl
             | bits_decl | type_alias | const_decl | static_decl
             | extern_block | impl_block | link_decl ;

import_decl  = 'import' path [ 'as' ident ] ';'
             | 'import' path '::' '*' ';' ;
path         = ident { '::' ident } ;

vis          = [ 'priv' | 'pkg' | 'pub' ] ;            (* 缺省 priv *)

fn_decl      = vis [ 'extern' string ] [ 'bare' ] 'fn' ident [ type_params ]
               '(' [ params ] ')' [ '->' type ] ( block | ';' ) ;
params       = param { ',' param } [ ',' '...' ] ;
param        = ident ':' type [ '=' expr ] ;
type_params  = '[' type_param { ',' type_param } ']' ;
type_param   = ident [ ':' const_expr ] ;               (* 值参数用于数组长度 *)

struct_decl  = vis 'struct' [ layout_kw ] ident [ type_params ] '{' [ field_list ] '}' ;
layout_kw    = 'auto' | 'c' | 'packed' ;
field_list   = field { ',' field } [ ',' ] ;
field        = ident ':' type ;

union_decl   = vis 'union' ident '{' field_list '}' ;
enum_decl    = vis 'enum' ident [ type_params ] '{' variant { ',' variant } [ ',' ] '}' ;
variant      = ident [ '(' [ type_list ] ')' ] [ '{' field_list '}' ] ;
bits_decl    = vis 'bits' ident ':' type '{' bitfield { ',' bitfield } '}' ;
bitfield     = ident ':' const_expr ;                  (* 位宽 *)

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
slice_type   = '[' type ']' ;                          (* 视图：ptr+len *)
ptr_type     = '^' [ 'ro' ] type ;
fn_type      = 'fn' [ conv ] '(' [ type_list ] ')' [ '->' type ] ;
conv         = 'c' | 'bare' | 'flint' ;
path_type    = path [ type_args ] ;
type_args    = '[' type { ',' type } ']' ;

block        = '{' { stmt } [ expr ] '}' ;             (* 末表达式为块值 *)
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
assign_expr  = or_expr [ assign_op assign_expr ] ;     (* 右结合 *)
assign_op    = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '|=' | '&=' | 'xor=' | 'shl=' | 'shr=' ;
or_expr      = and_expr { 'or' and_expr } ;
and_expr     = bor_expr { 'and' bor_expr } ;
bor_expr     = bxor_expr { '|' bxor_expr } ;
bxor_expr    = band_expr { 'xor' band_expr } ;
band_expr    = eq_expr { '&' eq_expr } ;
eq_expr      = rel_expr { ( '==' | '!=' ) rel_expr } ;
rel_expr     = range_expr { ( '<' | '<=' | '>' | '>=' ) range_expr } ;
range_expr   = add_expr [ '..' add_expr ] ;             (* 半步区间 [a,b) *)
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
closure      = 'fn' '(' [ params ] ')' [ '->' type ] block ;   (* 见 §8.6 捕获规则 *)
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

解析策略（规范）：

- 表达式：Pratt，优先级表集中定义于 §6.2，新增运算符只改表；左结合除赋值、`..` 外均为左结合。
- 泛型实参：类型位置用 `T[a, b]`；表达式位置显式实例化**必须**写 `f::[a, b](...)`，裸 `f(...)` 仅做推断。该规则消除了 `[` 与索引、`<` 与比较的歧义，不使用回溯。
- `.*` 与 `.` 冲突：先匹配 `.`，若紧跟 `*` 且后一字符不是标识符起始则归约为 `.*`（仅一个 Token 的前瞻）。
- 语句/表达式歧义：`if`/`match`/`block` 作为表达式时，若出现在语句位置且后跟 `;`，按表达式语句处理；否则按语句处理（`if` 可控流）。
- 语法错误同步点：语句边界（`;`、`}`、`fn`）、参数边界（`,`、`)`、`{`）、类型实参边界（`]`）、函数边界（下一 `fn`）。一次编译上报多条。

---

## §4 声明、作用域、可见性、初始化

- **文件即模块**：模块名 = 文件基名（去 `.fl`）；目录构成命名空间；`import` 必须显式，无隐式全局命名空间。
- 可见性：缺省 `priv`（仅本模块）；`pkg`（同一命名空间树内可见）；`pub`（导出）。跨模块访问 `priv` 为错误 E3102。
- 名字解析顺序：局部 → 参数 → 本模块 item → 导入 item；四类命名空间独立：变量/函数、类型、模块、标签。
- 局部变量必须先声明后使用；item（函数/类型/const/static）在模块内**顺序无关**（两遍解析）。
- 遮蔽：同一块内禁止重名（E3103）；嵌套块允许遮蔽，但产生提示 W3102；参数与局部同名禁止。
- `static` 初始化只允许编译期可求值表达式；禁止运行期初始化与隐式惰性初始化。需要运行期初始化时显式调用 `init()` 模式（由调用方保证顺序）。理由：消除静态初始化顺序不确定与隐藏副作用；代价：某些常量表需要手写初始化函数。
- `const` 在编译期求值，失败为 E4101；`static mut` 的读写不自动加锁，跨线程使用由开发者负责（原子类型见阶段十一）。

---

## §5 类型系统

### §5.1 基本类型

| 类型 | 宽度 | 说明 |
| --- | --- | --- |
| `i8/i16/i32/i64` | 8/16/32/64 | 二补码有符号；溢出行为由编译选项或作用域策略决定（§6.5） |
| `u8/u16/u32/u64` | 8/16/32/64 | 无符号 |
| `f32/f64` | 32/64 | IEEE-754，无隐式精度提升 |
| `bool` | 1 字节存储 | 仅 `true`/`false`；`bool as u8` 显式 |
| `char` | 4 字节 | Unicode 标量值（0..=0x10FFFF 去代理区），越界构造为错误 |
| `byte` | 1 | 原始字节，可与 `u8` 显式互转 |
| `unit` | 0 | 写作 `()`，块无值时的类型 |
| `never` | 0 | 写作 `!`，`return`/`panic`/无限循环表达式的结果类型 |

### §5.2 复合类型

- 元组 `(T1, T2, ...)`：匿名、结构等价；访问 `.0`、`.1`。
- 数组 `[T; N]`：N 为编译期常量；值语义，按值传递/拷贝（无隐式大拷贝检查？→ 见 §12 性能提示，编译器对 >64 字节的按值传递给提示 W5201，不强制）。
- 切片 `[T]`：`{ptr, len}` 两字段视图，不拥有内存，无生命周期检查（越界检查见 §12）。
- 结构体：`struct` 默认 `auto` 布局（编译器可重排字段以优化对齐）；`struct c` 按 C ABI 布局；`struct packed` 无填充（`align = 1`）。
- 联合体：`union` 字段共享偏移 0，大小 = 最大字段对齐后大小；读取非最后写入字段的结果是**未定义值**（不是 UB，但值不确定），文档必须显式说明。
- 位域：`bits Name: uN { a: w, ... }`，总位宽不得超过底层类型；跨字节边界按小端位序定义（明确写入规范）。
  访问语义：`f.a` 的类型是 `bool`（置位为 true），可写；`Name::from_bits(v: uN) -> Name` 构造，`Name::bits(f) -> uN` 取原始值；
  越界宽度为 E4009。
- 枚举：`enum` 支持无负载与带负载（`V(T)` 或 `V{ x: T }`）；判别值显式可控 `A = 1`（仅无负载时），否则由编译器按声明顺序分配。

### §5.3 指针与函数类型

- `^T`：可变裸指针，可为 `null`，不做别名/生命周期检查；`^ro T`：只读视图（不能通过它写入，但可从 `^T` 隐式收窄）。
- 解引用 `p.*`；取地址 `^expr`（对左值）；指针算术 `p + n`、`p - n` 仅在 `^T`/`^ro T` 上允许，单位为元素大小；指针相减得到 `i64` 元素差。
- 整数 ↔ 指针：必须显式 `as`，无隐式转换；用于 MMIO：`(0xFFFF_FF00_0000_0000 as ^u32).*`。
- 函数类型：`fn(T1, T2) -> R`（默认 Flint 约定），`fn c(...)`（C ABI），`fn bare(...)`（无栈帧裸函数，仅允许内联汇编/`asm` 体）。
- 函数项到函数指针的转换是显式的：`&f as fn(i64) -> i64`。

### §5.4 类型别名与不透明类型

`type Name = T;` 完全透明；`type Name = opaque;`（阶段八引入）为不透明句柄，只允许按指针传递，禁止解引用与算术。

### §5.5 泛型

- 语法：声明 `fn f[T, N: usize](...)`、`struct Box[T]`、`enum Opt[T]`、`type Pair[T] = (T, T)`。
- 实例化：类型位置 `Box[i64]`；表达式显式 `f::[i64](x)`；否则由实参推断。
- **约束模型**：不做静态 trait/约束声明。泛型体在实例化时按实际类型做成员检查（需要的方法/运算符在实例化点必须存在）。错误必须打印完整实例链：`f[i64] -> g[i64] -> 需要 T: op_add`。
  取舍：语法极简、无 trait 系统复杂度；代价是错误暴露晚、泛型代码必须保留完整 AST（影响增量编译与二进制体积）。
- 默认单态化，零开销；`erased` 参数（`fn log[T: erased]`）为选择性类型擦除，通过显式 vtable 结构传参（阶段十一实现，代价：间接调用 + 不可内联）。

### §5.6 `str`

`str` = `{ ^ro byte, u64 len }`，UTF-8，字节索引与字符索引分离：`s.len_bytes`、`s.char_count()`（O(n)）；索引用 `s.byte(i)` / `s.char(i)`，禁止 `s[i]` 隐式选择其一。字符串拼接/切片返回新 `str` 视图或标准库 `String`，无隐式堆分配。
公开字段：`ptr`（`^ro byte`）与 `len`（字节数），供 FFI 直接取用；两者只读。

### §5.7 显式转换
禁止一切隐式数值转换（含 `i32 → i64` 拓宽）。`as` 允许：数值截断/符号改变、`bool→整数`、`char↔u32`、指针↔整数、指针类型互转、枚举判别值↔整数。
`as` **不**允许：结构体↔整数、数组↔指针（用 `cast` 内建）、浮点↔指针。越界/精度损失由开发者负责；调试模式下 `as` 可插入检查（开关）。

---

### §5.8 核心内建（无运行时依赖）

`alloc(size: u64, align: u64) -> ^byte`、`free(p: ^byte)`、`realloc(p: ^byte, size: u64, align: u64) -> ^byte`
（分配器可替换：`alloc_with(alloc: ^Allocator, ...)`，`Allocator` 是函数指针结构）；
`copy_bytes(dst: ^byte, src: ^ro byte, n: u64)`、`zero_bytes(p: ^byte, n: u64)`；
`size_of(T) -> u64`、`align_of(T) -> u64`（编译期常量）；`trap() -> !`；`uninit(T) -> T`（显式未初始化，使用前必须写入，否则读取为 UB）。
这些是语言核心的**唯一内建**，不依赖操作系统；标准库在此之上实现容器、字符串、IO。

---

## §6 表达式与运算符

### §6.1 块表达式

`{ stmt* expr? }` 的值 = 末尾表达式；无末尾表达式则为 `()`；`return`/`break`/`goto` 提前离开时类型为 `!`。

### §6.2 优先级表（固定，不可自定义）

| 级别 | 运算符 | 结合性 |
| --- | --- | --- |
| 1 | `=` `+=` `-=` `*=` `/=` `%=` `\|=` `&=` `xor=` `shl=` `shr=` | 右 |
| 2 | `or` | 左 |
| 3 | `and` | 左 |
| 4 | `\|` | 左 |
| 5 | `xor`（按位） | 左 |
| 6 | `&` | 左 |
| 7 | `==` `!=` | 左 |
| 8 | `<` `<=` `>` `>=` | 左 |
| 9 | `..` | 非结合 |
| 10 | `+` `-` | 左 |
| 11 | `*` `/` `%` | 左 |
| 12 | `shl` `shr` | 左 |
| 13 | 前缀 `-` `not` `^` `try` `panic` | 右 |
| 14 | 后缀 `()` `[]` `.` `.*` `as` `::[]` | 左 |

### §6.3 语义要点

- `and`/`or` 短路；`not` 仅布尔。
- `& | xor shl shr` 仅整数；移位量类型任意整数，超宽按位宽取模（定义为 `shift % bits`，不是 UB）。
- `==`/`!=` 对结构体/数组/元组按字段逐位比较（要求字段类型可比较）；浮点 NaN 遵循 IEEE（`NaN != NaN`），需要位比较时用 `bit_eq`。
- `..` 产生 `Range[T]`，半步区间 `[a, b)`；`for i in a..b` 语义为数值循环（溢出在调试模式检查）。
- 整数溢出策略（按作用域/编译选项三选一）：`wrap`（默认，静默环绕）、`trap`（运行时 panic）、`error`（编译期报错，仅常量可判定时）。通过 `overflow(wrap|trap|error)` 块或模块级设置，不写入每个表达式。
- 除零：整数除零在 `checked` 模式下 panic（E8002），发布模式为 UB（文档必须显式声明）；浮点除零遵循 IEEE。

### §6.4 运算符重载

允许集合：`+ - * / %`、`== != < <= > >=`、`[]`（索引）、`.*`（解引用）、`()`（调用）。不允许重载：赋值、逻辑、位运算、`as`、`..`、优先级。
实现形式：`impl Type { operator + (self: Type, rhs: Type) -> Type { ... } }`；`self` 为值或指针取决于签名。复合赋值按 `a op= b` → `a = a op b` 展开，不做原地优化（阶段五 IR 再做）。
代价：重载使 `+` 语义依赖类型，文档生成必须列出每个类型的运算符表；二进制体积随实现增长。

---

## §7 语句与控制流

- `if`/`while` 条件必须是 `bool`，无隐式真值转换。
- `for p in e`：若 `e` 为 `Range[T]` 走数值循环（无迭代器分配）；否则要求可迭代（`iter()` 返回带 `next` 的迭代器结构，阶段八进入标准库）。`step` 仅数值循环可用。
- `break`/`continue` 可带标签；标签由 `label name block` 引入，作用域为该块。
- `match` 必须穷尽：对 `enum` 要求覆盖全部变体（或有 `_`/绑定兜底）；对整数报“非穷尽”，除非有 `_`。缺失分支诊断列出缺失模式（E5203）。
- 守卫 `if` 中的名字可引用本分支绑定；守卫不得有副作用以外的控制流（不得 `return`）。
- `goto` 严格约束（满足全部条件才合法，否则 E3205）：
  同一函数内；目标标签在外层或同层块；不得跳入更深层块；不得跳过带初始化的 `let`/`const`；不得跨越 `onexit` 作用域；不得跳入 `match` 分支或循环体内部。
  用途限定：内核错误路径、状态机、性能关键的尾合并；文档要求每处 `goto` 写明理由。
- 循环/递归深度：`--stack-guard` 编译选项在函数入口插入计数器，超限 panic（E8004）；默认关闭（零开销）。

---

## §8 函数与调用约定

### §8.1 调用约定

- `flint`（默认）：整数/指针参数 `rdi,rsi,rdx,rcx,r8,r9`，浮点 `xmm0..xmm7`，返回 `rax`/`xmm0`；调用者清理栈；16 字节对齐；影子空间仅 Windows 目标需要。
- `c`：目标平台 C ABI（Windows x64 / System V AMD64 分别实现），用于 FFI。
- `bare`：无 prologue/epilogue，函数体只允许 `asm` 与常量返回；用于中断入口、上下文切换。
- 自定义约定：`fn conv(name) ...` 阶段八引入（寄存器分配表由声明给出）；本阶段只定义语法占位。

### §8.2 参数

- 默认参数：`fn f(a: i64, b: i64 = 10)`；实参从右往左省略；默认值必须编译期可求值。跨 FFI 边界禁止默认参数。
- 可变参数：仅 `extern "C"` 声明允许 `...`；Flint 函数不支持 varargs（用切片/结构体替代）。调用 C varargs 时浮点参数按 C 规则提升（`f32→f64`），由调用点显式转换。
- 参数传递：小类型（≤16 字节且无析构）按值；大类型按值仍复制（无隐式引用），编译器给性能提示 W5201。
- 返回值：≤16 字节用寄存器；更大用隐藏返回指针（由调用者分配，ABI 明确）。

### §8.3 尾调用

`return f(x);` 在**签名兼容**（参数/返回布局一致、同一约定）时保证尾调用优化（TCO），不依赖优化级别；不兼容时插入提示 W5202。需要强制 TCO 时写 `tail return f(x);`（阶段六进入语法，本版占位）。递归深度检查与 TCO 冲突时，`tail` 调用不增加计数。

### §8.4 一等函数与闭包

函数项可作为值（显式转函数指针）；闭包语法 `fn(a: i64) -> i64 { ... }`，捕获规则：
- 默认**按值捕获**使用到的外层局部（复制），需要引用捕获时显式 `fn[^] (...) {...}`（捕获指针，生命周期由开发者保证）。
- 闭包值类型为 `{ fn_ptr, env_ptr }`；env 分配位置由上下文决定：栈上（默认，不逃逸）或堆上（显式 `heap fn...`，使用当前分配器）。
- 无隐式装箱；无 GC。

### §8.5 裸函数

`bare fn` 不允许 `let`、表达式语句、`return` 值；只允许 `asm` 与 `trap`；ABI 完全由开发者负责。

---

## §9 错误处理

- 核心类型 `Outcome[T, E]`（`enum { ok(T), err(E) }`），无异常、无栈展开（可选栈展开为库特性，非语言默认）。
- 传播：`try expr` 在 `Outcome` 上展开：`ok(v)` 得 `v`，`err(e)` 立即 `return err(e)`（要求当前函数返回 `Outcome[_, E2]` 且 `E` 可转换为 `E2`，否则 E4202）。
- 错误上下文：标准库 `Context` 包装（`err.with(msg)`），形成错误链；`Outcome` 不隐式分配，链由调用者显式构造。
- `panic(msg)`：立即终止（`trap` 指令或平台 panic 处理器），不展开；内核可用 `trap()` 直接触发断点。panic 消息与位置写入只读常量区，可由 `--no-panic-msg` 去掉。
- FFI 边界：跨 C 边界不允许传播 `Outcome`；必须转换为返回码/输出参数，规则见阶段八。

---

## §10 资源管理（无 RAII）

- 作用域钩子：`onexit { ... }`，在离开作用域时**逆序**执行（正常离开、`return`、`break`、`goto` 均执行；`panic` 默认**不执行**，可用 `--onexit-on-panic` 开启）。
  `onexit` 内不得 `return`/`break`/`goto`（E3207）；不得捕获外部可变引用以外的资源（无借用检查，仅规范约束）。
- 显式释放：`free(p)`、`close(fd)` 等核心/标准库函数；无自动析构。
- 可选封装库：`Auto[T]` 模板（在标准库，调用 `onexit` 注册释放），不进入语言核心。
- 诊断：`--leak-report`（调试构建，基于分配器记账）检测未释放；发布构建零开销。

---

## §11 模块、FFI、链接

- 模块：文件即模块；目录为命名空间；`import a::b;`；循环依赖为错误 E3106，诊断输出完整环路径（`a -> b -> c -> a`）。
- `extern "C" { fn ... }` 调用 C；`extern "C" lib "kernel32" { ... }` 显式指定库；`pub extern "C" fn` 导出给 C。
- 字符串跨边界：C 侧 `char*` 与 `^ro byte` 互转必须显式 `cstr_to_str` / `str_to_cstr`（后者分配，所有权归调用者）。
- 内存归属：跨 FFI 分配的内存必须由分配它的模块释放；文档要求每个 extern 声明标注 `alloc_by`。
- 链接 C 静态库：`link "foo.lib";` 交给内部链接器（阶段七）解析；阶段零不支持。
- 跨边界 panic：禁止；C 回调中 panic 为 UB（E4205），必须返回错误码。

---

## §12 内存模型与未定义行为清单

明确 UB（编译器可利用，文档必须列出）：
- 解引用 `null`、已释放指针、越界指针（未开启检查时）。
- 数据竞争（非原子并发访问同一内存且至少一个写）。
- 整数除零（非 `checked` 模式）、`i64::MIN / -1`。
- 移位量为负、`as` 到非法枚举判别值后 `match`（未覆盖分支时）。
- 调用约定不匹配、栈对齐错误（ABI 层）。
- 违反 `^ro` 只读承诺的写入（由别名产生）——实现层不保证捕获。
- 读取未初始化内存（`let x: i64;` 不允许，必须初始化或显式 `uninit` 内建）。

不是 UB 但值不确定：读取联合体非活跃字段；填充字节内容；`static` 未初始化（零初始化，明确保证）。
可选运行时检查（编译开关，默认关闭）：数组/切片越界、空指针解引用、对齐、整数溢出（`trap` 策略）、分配器毒化。

---

## §13 编译期求值

`const` 与 `static` 初始化、数组长度、`bits` 位宽、`case` 常量、泛型值参数必须在编译期可求值。
允许的 const 表达式：字面量、算术/位运算、比较、`if`、块、`const fn` 调用、结构体/数组构造、`as`。
禁止：指针解引用（除 `const` 地址）、堆分配、I/O、`asm`、`panic`（除非作为编译期错误）。
代价：`const fn` 需要解释器（阶段五实现）；二进制中不保留 const 数据副本（去重）。

---

## §14 内联汇编

语法：`asm [volatile] ("模板" : out(reg) = expr, ... : in(expr), ... : clobber("rax","cc"), ...);`
- 模板占位 `{0}`、`{1}`…绑定到操作数；`{{`/`}}` 为字面花括号。
- 方言：Intel 语法，指令集由目标决定（x86-64 阶段八子集，ARM64 后续）。
- 约束：`reg`（通用）、`reg8/16/32/64`、`mem`、`imm`；clobber 必须显式列出被破坏的寄存器与 `cc`、`memory`。
- 编译器不分析 asm 语义；`volatile` 保证不被删除/重排。错误编码由内部汇编器在阶段八报告（E6101）。

---

## §15 诊断规范（详见 `p1-errors.md`）

格式：

```
<file>:<line>:<col>: error[E<code>]: <消息>
  <line> | <源码行>
         | <插入符>
  说明: <一句可执行建议>
  参见: <相关定义位置 file:line:col>
```

- 编译期错误必须带 Span；涉及名字的错误必须附定义位置。
- 泛型实例化错误必须输出完整实例链（E5202）。
- 运行时错误（panic/检查失败）带 `file:line:col` + 函数名 + 调用链（开启 `--runtime-trace` 时）。

---

## §16 特性代价表（设计阶段的账）

| 特性 | 收益 | 代价 | 备选（已放弃） |
| --- | --- | --- | --- |
| 无隐式转换 | 语义可预测 | 代码更啰嗦 | C 式隐式提升（放弃：隐式符号/精度错误） |
| 泛型无约束声明 | 语法极简 | 错误晚、AST 必须保留、单态化膨胀 | trait 系统（放弃：复杂度与实现成本） |
| 单态化默认 | 零开销 | 二进制体积、编译时间 | 全类型擦除（放弃：间接调用） |
| 无 RAII | 显式生命周期 | 手工释放负担 | 析构函数（放弃：隐式控制流、与 goto 冲突） |
| 无借用检查 | 无运行时开销、无学习曲线 | 内存安全靠开发者 | Rust 式借用（放弃：语法与实现复杂度） |
| `onexit` 钩子 | 可控清理 | panic 语义需明确 | defer（更短但语义相近，未采用以避免文本替换式直觉） |
| `..` 半步区间 | 循环无歧义 | 需要 Range 类型 | 闭区间（放弃：易错） |
| 指针可为 null | 与 C/硬件一致 | 空检查需显式 | Option 包装（放弃：额外分支与 ABI 负担） |
| 单节 RWX（阶段零） | 无重定位即可运行 | 安全加固缺失 | 多节 + 自研重定位（阶段七） |

---

## §17 与阶段零的兼容性

阶段零实现子集必须视为本规格的**前缀**：`fn`/`let`/`return`/`i64`/四则/`print`/字面量/注释均符合本规格。
已知偏差（必须在阶段二消除）：
- `print` 是内建保留名；规格中它是标准库函数（阶段八迁移，保留语法但走库调用）。
- 阶段零错误码未编号（纯文本）；阶段二起统一为 `E<code>`。
- 阶段零无 `const/static/struct/...`，解析器拒绝；规格不要求阶段零支持。
- 阶段零函数名查找为链表；规格不约束实现。
- 阶段零生成的 PE 为单节 RWX；规格允许，阶段七改为多节。

---

## §18 待决项（需签字确认后才冻结）

1. 整数溢出默认策略：`wrap` 作为默认，还是 `trap` 作为默认（安全 vs 性能）。
2. `let x: i64;` 是否允许“声明未初始化”（当前禁止，要求显式 `uninit`）。
3. 可见性第三级命名：`pkg` 是否保留，还是改为 `pub(in ...)` 形式。
4. 泛型值参数语法 `[N: usize]` 与数组长度 `[T; N]` 是否统一为 `[N: u64]`。
5. `goto` 是否保留（当前保留但严格约束）；若删除，内核场景用状态机/`onexit` 替代。
6. `onexit` 在 panic 时默认是否执行（当前不执行）。
7. 内联汇编模板占位风格 `{0}` 与 `[]` 约束语法是否最终采用。
8. `str` 的字符索引 API 命名（`byte/char`）是否接受。
9. 是否引入 `erased` 泛型（当前标记为阶段十一，语法占位）。
10. 语言正式名与关键字集合的最终冻结（改名影响 `.fl`、`build.ps1`、文档）。
