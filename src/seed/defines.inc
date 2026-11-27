; ===========================================================================
; Flint 种子编译器 —— 全局常量 / 结构偏移 / 寄存器约定
; ---------------------------------------------------------------------------
; 内部调用约定（种子自身专用，非 FlintCall，阶段 6 才冻结正式 ABI）：
;   参数：rdi, rsi, rdx, rcx, r8, r9
;   返回：rax（必要时 rdx 作为第二返回值）
;   易失：rax rcx rdx rsi rdi r8 r9 r10 r11
;   保留：rbx rbp r12 r13 r14 r15
; 栈：函数入口 rsp%16 == 8；push rbp + sub 16 倍数后 rsp%16 == 0；
;     每个函数至少预留 0x30 字节帧，满足 Win32 影子空间与第 5 参数槽。
; ===========================================================================

%define HDR_SIZE        0x200
%define SEC_RVA         0x1000
%define IMAGE_BASE      0x140000000

; 阶段 0 缓冲区上限（超限即报错，阶段 2 换成可增长 arena）
%define SRC_MAX         0x800000        ; 源文件 8 MiB
%define MAX_TOKENS      65536
%define TOK_BYTES       (MAX_TOKENS * TK_SIZE)
%define AST_BYTES       0x1000000       ; 16 MiB AST arena
%define FN_BYTES        0x100000        ; 1 MiB 函数表 arena
%define SEC_BYTES       0x800000        ; 8 MiB 输出节缓冲
%define POOL_SIZE       0x10000         ; 生成程序的静态分配池（64 KiB）
%define POOL_BLOCK      0x1000          ; 每个 alloc 调用点占 4 KiB
%define DIAG_MAX        32              ; 单次编译最多上报错误数

; ------------------------- Token（32 字节）---------------------------------
%define TK_KIND         0
%define TK_LINE         4
%define TK_COL          8
%define TK_START        12              ; 源码字节偏移（含）
%define TK_END          16              ; 源码字节偏移（不含）
%define TK_PAD          20
%define TK_IVAL         24              ; 整数字面量值 / 关键字无用
%define TK_SIZE         32

%define TK_EOF          0
%define TK_IDENT        1
%define TK_INT          2
%define TK_KW_FN        3
%define TK_KW_LET       4
%define TK_KW_RETURN    5
%define TK_LPAREN       6
%define TK_RPAREN       7
%define TK_LBRACE       8
%define TK_RBRACE       9
%define TK_COMMA        10
%define TK_COLON        11
%define TK_SEMI         12
%define TK_ARROW        13
%define TK_PLUS         14
%define TK_MINUS        15
%define TK_STAR         16
%define TK_SLASH        17
%define TK_PERCENT      18
%define TK_ASSIGN       19
%define TK_KW_WHILE     20
%define TK_KW_IF        21
%define TK_KW_ELSE      22
%define TK_LT           23
%define TK_GT           24
%define TK_LE           25
%define TK_GE           26
%define TK_EQ           27
%define TK_NE           28
%define TK_PLUS_ASSIGN  29
%define TK_MINUS_ASSIGN 30
%define TK_LBRACKET     31
%define TK_RBRACKET     32
%define TK_CARET        33
%define TK_AS           34
%define TK_CHAR         35
%define TK_DOT          36
%define TK_DOTSTAR      37
%define TK_KW_STRUCT    38

; ------------------------- AST（56 字节）-----------------------------------
%define ND_KIND         0
%define ND_LINE         4
%define ND_COL          8
%define ND_PAD          12
%define ND_NEXT         16              ; 兄弟链
%define ND_A            24
%define ND_B            32
%define ND_C            40
%define ND_VAL          48
%define ND_SIZE         56

%define NK_PROGRAM      0               ; A=首个函数节点
%define NK_FN           1               ; A=名字 Token, B=参数链, C=函数体块
%define NK_PARAM        2               ; A=名字 Token, B=下一个参数
%define NK_BLOCK        3               ; A=首条语句
%define NK_LET          4               ; A=名字 Token, B=初始化表达式, C=类型 Token
%define NK_RETURN       5               ; A=表达式 或 0
%define NK_EXPRSTMT     6               ; A=表达式
%define NK_BIN          7               ; A=运算符 Token, B=左, C=右
%define NK_UNARY        8               ; A=运算符 Token, B=操作数
%define NK_CALL         9               ; A=被调名字 Token, B=实参链
%define NK_IDENT        10              ; A=名字 Token
%define NK_INT          11              ; A=字面量 Token, VAL=值
%define NK_ARG          12              ; A=表达式, B=下一个实参
%define NK_WHILE        13              ; A=条件, B=循环体块
%define NK_IF           14              ; A=条件, B=then 块, C=else 块或 0
%define NK_ASSIGN       15              ; A=名字 Token, B=右值, C=赋值运算符 Token
%define NK_INDEX        16              ; A=基址表达式, B=下标表达式
%define NK_CAST         17              ; A=操作数, VAL=目标类型码
%define NK_DEREF        18              ; A=指针表达式（.* 后缀）
%define NK_FIELD        19              ; A=基址表达式, B=字段名 Token
%define NK_STRUCTLIT    20              ; VAL=结构体类型码, B=字段初始化链
%define NK_ARRAYLIT     21              ; B=元素表达式链

; 结构体/字段/数组描述表
%define ST_ID           0
%define ST_NAME         8
%define ST_LEN          16
%define ST_SZ           20
%define ST_FIELDS       24
%define ST_NEXT         32
%define ST_REC          40

%define SF_NAME         0
%define SF_LEN          8
%define SF_OFF          12
%define SF_TYPE         16
%define SF_NEXT         24
%define SF_REC          32

%define AR_ID           0
%define AR_ELEM         4
%define AR_COUNT        8
%define AR_SZ           12
%define AR_NEXT         16
%define AR_REC          24

; 类型码：低 4 位是基类型，0x10 位表示指针
%define TY_I64          0
%define TY_BYTE         1
%define TY_U32          2
%define TY_I32          3
%define TY_U8           4
%define TY_PTR          0x10
%define TY_FN           0x20
%define TY_STRUCT       0x40            ; 0x40|结构体编号
%define TY_ARRAY        0x80            ; 0x80|数组编号

; ------------------------- 函数表项（48 字节）------------------------------
%define FN_NAME         0               ; qword 指向源码文本
%define FN_LEN          8
%define FN_ARITY        12
%define FN_OFF          16              ; 代码偏移（节内）
%define FN_NODE         24
%define FN_NEXT         32
%define FN_FLAGS        40
%define FN_SIZE         48

; ------------------------- 局部变量表项（24 字节）--------------------------
%define LV_NAME         0
%define LV_LEN          8
%define LV_SLOT         12
%define LV_TYPE         16              ; 类型码（TY_*）
%define LV_NEXT         20
%define LV_SIZE         32

; ------------------------- 调用回填项（40 字节）----------------------------
%define FX_OFF          0               ; call rel32 的位移字段偏移
%define FX_PAD          4
%define FX_NAME         8
%define FX_LEN          16
%define FX_LINE         20
%define FX_COL          24
%define FX_SRCOFF       28
%define FX_NEXT         32
%define FX_SIZE         40

; ------------------------- 输出 PE 数据布局字段 ----------------------------
%define G_IAT           0x0000          ; 由 cg 运行期记录，不参与常量

; ------------------------- Win32 ----------------------------
%define STD_OUTPUT_HANDLE   -11
%define GENERIC_READ        0x80000000
%define GENERIC_WRITE       0x40000000
%define OPEN_EXISTING       3
%define CREATE_ALWAYS       2
%define FILE_ATTRIBUTE_NORMAL 0x80
%define MEM_COMMIT_RESERVE  0x3000
%define PAGE_READWRITE      4
%define CP_UTF8             65001
%define INVALID_HANDLE      -1

; ------------------------- 编译选项开关（阶段 0 预留）----------------------
%define OPT_BOUNDS_CHECK    0
