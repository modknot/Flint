; ===========================================================================
; Seed compiler runtime data (inside .text, which is RWX in stage 0 for simplicity).
; The loader fills the IAT; all internal references are RIP-relative, with no relocations.
; ===========================================================================

%macro MSG 2
%1:
    db %2, 0
%1 %+ _len equ $ - %1 - 1
%endmacro

sec_start:
align 8

; ------------------------------ IAT ---------------------------------------
iat_table:
__imp_GetStdHandle:        dq hint_GetStdHandle        - sec_start + SEC_RVA
__imp_WriteFile:           dq hint_WriteFile           - sec_start + SEC_RVA
__imp_ExitProcess:         dq hint_ExitProcess         - sec_start + SEC_RVA
__imp_GetCommandLineW:     dq hint_GetCommandLineW     - sec_start + SEC_RVA
__imp_WideCharToMultiByte: dq hint_WideCharToMultiByte - sec_start + SEC_RVA
__imp_SetConsoleOutputCP:  dq hint_SetConsoleOutputCP  - sec_start + SEC_RVA
__imp_GetConsoleOutputCP:  dq hint_GetConsoleOutputCP  - sec_start + SEC_RVA
__imp_CreateFileW:         dq hint_CreateFileW         - sec_start + SEC_RVA
__imp_ReadFile:            dq hint_ReadFile            - sec_start + SEC_RVA
__imp_CloseHandle:         dq hint_CloseHandle         - sec_start + SEC_RVA
__imp_VirtualAlloc:        dq hint_VirtualAlloc        - sec_start + SEC_RVA
__imp_GetLastError:        dq hint_GetLastError        - sec_start + SEC_RVA
                           dq 0

; --------------------------- import descriptor -----------------------------
imp_desc:
    dd 0                                        ; OriginalFirstThunk = 0 (IAT doubles as the lookup table)
    dd 0                                        ; TimeDateStamp
    dd 0                                        ; ForwarderChain
    dd dll_kernel32 - sec_start + SEC_RVA       ; Name RVA
    dd iat_table    - sec_start + SEC_RVA       ; FirstThunk RVA
    times 5 dd 0

dll_kernel32:
    db "KERNEL32.dll", 0

; --------------------------- Hint/Name ------------------------------------
hint_GetStdHandle:
    dw 0
    db "GetStdHandle", 0
hint_WriteFile:
    dw 0
    db "WriteFile", 0
hint_ExitProcess:
    dw 0
    db "ExitProcess", 0
hint_GetCommandLineW:
    dw 0
    db "GetCommandLineW", 0
hint_WideCharToMultiByte:
    dw 0
    db "WideCharToMultiByte", 0
hint_SetConsoleOutputCP:
    dw 0
    db "SetConsoleOutputCP", 0
hint_GetConsoleOutputCP:
    dw 0
    db "GetConsoleOutputCP", 0
hint_CreateFileW:
    dw 0
    db "CreateFileW", 0
hint_ReadFile:
    dw 0
    db "ReadFile", 0
hint_CloseHandle:
    dw 0
    db "CloseHandle", 0
hint_VirtualAlloc:
    dw 0
    db "VirtualAlloc", 0
hint_GetLastError:
    dw 0
    db "GetLastError", 0

imp_rva     equ imp_desc - sec_start + SEC_RVA
imp_size    equ 40

; --------------------------- runtime globals -------------------------------
align 8
h_stdout:       dq 0
old_cp:         dd 0
io_written:     dq 0
src_ptr:        dq 0
src_len:        dq 0
path8_ptr:      dq 0
path8_len:      dq 0
err_count:      dd 0
argc:           dd 0
args:           dq 0,0,0,0,0,0,0,0

ar_cur:         dq 0
ar_end:         dq 0

tk_ptr:         dq 0
tk_count:       dq 0
lex_pos:        dq 0
lex_line:       dd 0
lex_col:        dd 0
cur_line:       dd 0
cur_col:        dd 0

ps_cur:         dq 0
ps_base:        dq 0

ast_cur:        dq 0
ast_end:        dq 0
fn_head:        dq 0
fix_head:       dq 0

sec_buf:        dq 0
sec_len:        dq 0
g_entry_off:    dq 0
g_desc_off:     dq 0
g_iat_off:      dq 0
g_hstdout_off:  dq 0
g_nl_off:       dq 0
g_help_off:     dq 0
g_pool_off:     dq 0
cg_alloc_n:     dd 0
cg_scr1:        dd 0
cg_scr2:        dd 0
g_dll_off:      dq 0
g_hint_gs:      dq 0
g_hint_wf:      dq 0
g_hint_ep:      dq 0
g_hint_va:      dq 0
g_hint_vf:      dq 0
g_hint_cf:      dq 0
g_hint_ch:      dq 0
g_hint_rf:      dq 0
cg_depth:       dd 0
cg_no_fnval:    dd 0
next_off:       dd 0
struct_head:    dq 0
struct_count:   dd 0
array_head:     dq 0
array_count:    dd 0
local_head:     dq 0
next_slot:      dd 0
cur_fn:         dq 0

diag_name_ptr:  dq 0
diag_name_len:  dq 0

; --------------------------- precedence table -----------------------------
; Index = Token kind; value = left-associative precedence (0 means not a binary operator).
prec_table:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,10,20,20,20,0
    db 0,0,0,5,5,5,5,5,5,0,0
    db 0,0,0,0,0,0,0,0,0

; --------------------------- token name table ------------------------------
; Entries are 32-bit offsets relative to tk_names (PE has no relocations, so absolute addresses cannot be stored).
tk_names:
    dd n_eof - tk_names, n_ident - tk_names, n_int - tk_names
    dd n_kwfn - tk_names, n_kwlet - tk_names, n_kwreturn - tk_names
    dd n_lparen - tk_names, n_rparen - tk_names
    dd n_lbrace - tk_names, n_rbrace - tk_names
    dd n_comma - tk_names, n_colon - tk_names, n_semi - tk_names
    dd n_arrow - tk_names, n_plus - tk_names, n_minus - tk_names
    dd n_star - tk_names, n_slash - tk_names, n_percent - tk_names
    dd n_assign - tk_names
    dd n_kwwhile - tk_names, n_kwif - tk_names, n_kwelt - tk_names
    dd n_lt - tk_names, n_gt - tk_names, n_le - tk_names, n_ge - tk_names
    dd n_eq - tk_names, n_ne - tk_names
    dd n_plusassign - tk_names, n_minusassign - tk_names
    dd n_lbracket - tk_names, n_rbracket - tk_names, n_caret - tk_names
    dd n_as - tk_names, n_char - tk_names, n_dot - tk_names, n_dotstar - tk_names
    dd n_kwstruct - tk_names

n_eof:      db "EOF", 0
n_ident:    db "IDENT", 0
n_int:      db "INT", 0
n_kwfn:     db "KW_FN", 0
n_kwlet:    db "KW_LET", 0
n_kwreturn: db "KW_RETURN", 0
n_lparen:   db "LPAREN", 0
n_rparen:   db "RPAREN", 0
n_lbrace:   db "LBRACE", 0
n_rbrace:   db "RBRACE", 0
n_comma:    db "COMMA", 0
n_colon:    db "COLON", 0
n_semi:     db "SEMI", 0
n_arrow:    db "ARROW", 0
n_plus:     db "PLUS", 0
n_minus:    db "MINUS", 0
n_star:     db "STAR", 0
n_slash:    db "SLASH", 0
n_percent:  db "PERCENT", 0
n_assign:   db "ASSIGN", 0
n_kwwhile:  db "KW_WHILE", 0
n_kwif:     db "KW_IF", 0
n_kwelt:    db "KW_ELSE", 0
n_lt:       db "LT", 0
n_gt:       db "GT", 0
n_le:       db "LE", 0
n_ge:       db "GE", 0
n_eq:       db "EQ", 0
n_ne:       db "NE", 0
n_plusassign:  db "PLUS_ASSIGN", 0
n_minusassign: db "MINUS_ASSIGN", 0
n_lbracket: db "LBRACKET", 0
n_rbracket: db "RBRACKET", 0
n_caret:    db "CARET", 0
n_as:       db "AS", 0
n_char:     db "CHAR", 0
n_dot:      db "DOT", 0
n_dotstar:  db "DOTSTAR", 0
n_kwstruct: db "KW_STRUCT", 0

s_i64:  db "i64", 0
s_u64:  db "u64", 0
s_i32:  db "i32", 0
s_u32:  db "u32", 0
s_byte: db "byte", 0
s_u8:   db "u8", 0
s_alloc: db "alloc", 0
s_free:  db "free", 0

; --------------------------- static buffers --------------------------------
align 16
cmd_w:       times 4096*2 db 0
arg_buf:     times 4096*2 db 0
path8:       times 2048   db 0
numbuf:      times 64     db 0
hdr_buf:     times HDR_SIZE db 0
zero_buf:    times 512    db 0

; --------------------------- diagnostic text ------------------------------
MSG m_oom,                 "内存分配失败"
MSG m_src_too_large,       "源文件超过 8 MiB 上限"
MSG m_read_fail,         "读取输入文件失败"
MSG m_write_fail,          "写出输出文件失败"
MSG m_open_fail,           "打开输入文件失败"
MSG m_out_open_fail,       "创建输出文件失败"
MSG m_bad_char,            "无效字符"
MSG m_int_overflow,        "整数字面量超出 i64 范围"
MSG m_block_comment,       "块注释未闭合"
MSG m_string_unsupported,  "阶段 0 不支持字符串字面量"
MSG m_char_unterminated,   "字符字面量未闭合"
MSG m_unknown_type,        "未知类型"
MSG m_bad_index,           "下标必须是指针或数组"
MSG m_expect_ident,        "期望标识符"
MSG m_expect_lparen,       "期望 '('"
MSG m_expect_rparen,       "期望 ')'"
MSG m_expect_colon,        "期望 ':'"
MSG m_expect_lbrace,       "期望 '{'"
MSG m_expect_rbrace,       "期望 '}'"
MSG m_expect_rbracket,     "期望 ']'"
MSG m_expect_semi,         "期望 ';'"
MSG m_expect_type,         "期望类型名"
MSG m_only_i64,            "阶段 0 仅支持 i64 类型"
MSG m_syntax,              "语法错误"
MSG m_dup_fn,              "重复的函数定义"
MSG m_dup_param,           "重复的参数名"
MSG m_dup_local,           "重复的局部变量（阶段 0 不允许遮蔽）"
MSG m_undef,               "未定义的标识符"
MSG m_undef_fn,            "未定义的函数"
MSG m_arity,               "参数数量不匹配"
MSG m_print_reserved,      "print 为内建函数名，禁止定义"
MSG m_too_many_args,       "阶段 0 最多支持 4 个参数"
MSG m_fn_as_value,         "函数名不能作为值使用"
MSG m_main_missing,        "缺少 main 函数"
MSG m_no_entry,            "内部错误：入口偏移未记录"
MSG m_internal,            "内部错误"
MSG m_usage,               "用法: flint-seed <input.fl> <output.exe> | --tokens <input.fl> | --version"
MSG m_banner,              "flint-seed 0.0.1 (阶段 0 种子编译器)"
MSG m_toomany_err,         "错误数超过上限，终止编译"
MSG m_expect_fn,           "期望 fn 定义"
MSG m_bad_number,          "数字字面量缺少有效数字"
MSG m_expect_assign,       "期望 '='"

; --------------------------- fixed text ------------------------------------
s_bar:          db " | ", 0
s_ellipsis:     db " ...", 0
s_err_prefix:   db ": error: ", 0
s_flint_prefix: db "flint: ", 0
s_win32_prefix: db " (win32=", 0
spaces80:       times 80 db ' '
