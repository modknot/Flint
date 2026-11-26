; ===========================================================================
; 词法分析器（阶段 0）
; 支持：ASCII 标识符、十进制/0x/0b 整数字面量（允许 _ 分隔）、
;       行注释 //、嵌套块注释 /* */、单字符运算符与 ->。
; 每个 Token 记录 行/列/字节区间；错误就地恢复，不中断扫描。
; ===========================================================================

; tok_emit(eax=kind, rsi=start, rdx=end, rcx=ival) —— 行/列取 cur_line/cur_col
tok_emit:
    mov rdi, [rel tk_count]
    imul rdi, rdi, TK_SIZE
    add rdi, [rel tk_ptr]
    mov [rdi + TK_KIND], eax
    mov eax, [rel cur_line]
    mov [rdi + TK_LINE], eax
    mov eax, [rel cur_col]
    mov [rdi + TK_COL], eax
    mov [rdi + TK_START], esi
    mov [rdi + TK_END], edx
    mov dword [rdi + TK_PAD], 0
    mov [rdi + TK_IVAL], rcx
    inc qword [rel tk_count]
    ret

; ------------------------------ 跳过空白/注释 ------------------------------
lex_skip_ws:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
.loop:
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .ret
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]
    cmp cl, 9
    je .tab
    cmp cl, 13
    je .cr
    cmp cl, 10
    je .nl
    cmp cl, ' '
    je .sp
    cmp cl, '/'
    jne .ret
    lea rdx, [rax + 1]
    cmp rdx, [rel src_len]
    jae .ret
    movzx ecx, byte [rsi + rdx]
    cmp cl, '/'
    je .line_comment
    cmp cl, '*'
    je .block_comment
    jmp .ret

.tab:
    mov eax, [rel lex_col]
    dec eax
    shr eax, 2
    inc eax
    shl eax, 2
    inc eax
    mov [rel lex_col], eax
    inc qword [rel lex_pos]
    jmp .loop
.cr:
    inc qword [rel lex_pos]
    jmp .loop
.nl:
    inc qword [rel lex_pos]
    mov dword [rel lex_col], 1
    inc dword [rel lex_line]
    jmp .loop
.sp:
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .loop

.line_comment:
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
.lc_loop:
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .ret
    mov rsi, [rel src_ptr]
    cmp byte [rsi + rax], 10
    je .lc_nl
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .lc_loop
.lc_nl:
    ; 行注释把行尾换行一并吃掉，然后回到跳过循环，避免下一行注释被当成标点
    inc qword [rel lex_pos]
    mov dword [rel lex_col], 1
    inc dword [rel lex_line]
    jmp .loop

.block_comment:
    mov r8, [rel lex_pos]              ; 起始偏移（错误定位）
    mov r9d, [rel lex_line]
    mov r10d, [rel lex_col]
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    mov dword [rbp - 8], 1             ; depth
.bc_loop:
    mov rax, [rel lex_pos]
    lea rdx, [rax + 1]
    cmp rdx, [rel src_len]
    jae .bc_unterminated
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]
    movzx edx, byte [rsi + rax + 1]
    cmp cl, '/'
    jne .bc_try_close
    cmp dl, '*'
    jne .bc_single
    inc dword [rbp - 8]
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .bc_loop
.bc_try_close:
    cmp cl, '*'
    jne .bc_single
    cmp dl, '/'
    jne .bc_single
    dec dword [rbp - 8]
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    cmp dword [rbp - 8], 0
    jne .bc_loop
    jmp .loop
.bc_single:
    ; 单字节推进（处理换行 / Tab）
    mov rsi, [rel src_ptr]
    mov rax, [rel lex_pos]
    movzx ecx, byte [rsi + rax]
    cmp cl, 10
    je .bc_nl
    cmp cl, 9
    je .bc_tab
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .bc_loop
.bc_nl:
    inc qword [rel lex_pos]
    mov dword [rel lex_col], 1
    inc dword [rel lex_line]
    jmp .bc_loop
.bc_tab:
    mov eax, [rel lex_col]
    dec eax
    shr eax, 2
    inc eax
    shl eax, 2
    inc eax
    mov [rel lex_col], eax
    inc qword [rel lex_pos]
    jmp .bc_loop
.bc_unterminated:
    mov rax, [rel src_len]
    mov [rel lex_pos], rax             ; 直接到达 EOF，避免二次误报
    mov rdi, r8
    mov rsi, r9
    mov rdx, r10
    lea rcx, [rel m_block_comment]
    mov r8d, m_block_comment_len
    call diag_at
.ret:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 主扫描 ------------------------------------
; lex_run(rdi=src, rsi=len) -> rax=token 数组, rdx=token 数
lex_run:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rel src_ptr], rdi
    mov [rel src_len], rsi
    mov qword [rel lex_pos], 0
    mov dword [rel lex_line], 1
    mov dword [rel lex_col], 1
    mov qword [rel tk_count], 0

    cmp qword [rel tk_ptr], 0
    jne .loop
    mov edi, TOK_BYTES
    call arena_alloc
    mov [rel tk_ptr], rax
    mov qword [rel tk_count], 0

.loop:
    call lex_skip_ws
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .eof
    mov eax, [rel lex_line]
    mov [rel cur_line], eax
    mov eax, [rel lex_col]
    mov [rel cur_col], eax

    mov rax, [rel lex_pos]
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]

    ; 标识符
    cmp cl, 'A'
    jb .try_lower
    cmp cl, 'Z'
    jbe .ident
.try_lower:
    cmp cl, 'a'
    jb .try_digit
    cmp cl, 'z'
    jbe .ident
.try_digit:
    cmp cl, '0'
    jb .try_us
    cmp cl, '9'
    jbe .number
.try_us:
    cmp cl, '_'
    je .ident
.try_quote:
    cmp cl, '"'
    je .string_err
    cmp cl, 39
    je .char
    jmp .punct

; ------------------------------ 标识符 ------------------------------------
.ident:
    mov r8, [rel lex_pos]
.scan:
    mov r11, [rel lex_pos]
    cmp r11, [rel src_len]
    jae .ident_end
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + r11]
    cmp cl, 'A'
    jb .i_lower
    cmp cl, 'Z'
    jbe .i_adv
.i_lower:
    cmp cl, 'a'
    jb .i_digit
    cmp cl, 'z'
    jbe .i_adv
.i_digit:
    cmp cl, '0'
    jb .i_us
    cmp cl, '9'
    jbe .i_adv
.i_us:
    cmp cl, '_'
    jne .ident_end
.i_adv:
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .scan
.ident_end:
    mov rsi, [rel src_ptr]
    add rsi, r8
    mov rcx, [rel lex_pos]
    sub rcx, r8
    ; 关键字表（按长度分派，再逐字节比较）
    cmp rcx, 2
    jne .kw_len3
    cmp byte [rsi], 'f'
    jne .kw_if2
    cmp byte [rsi + 1], 'n'
    jne .kw_if2
    mov eax, TK_KW_FN
    jmp .emit
.kw_if2:
    cmp byte [rsi], 'i'
    jne .kw_as
    cmp byte [rsi + 1], 'f'
    jne .kw_as
    mov eax, TK_KW_IF
    jmp .emit
.kw_as:
    cmp byte [rsi], 'a'
    jne .ident_plain
    cmp byte [rsi + 1], 's'
    jne .ident_plain
    mov eax, TK_AS
    jmp .emit
.kw_len3:
    cmp rcx, 3
    jne .kw_len6
    cmp byte [rsi], 'l'
    jne .ident_plain
    cmp byte [rsi + 1], 'e'
    jne .ident_plain
    cmp byte [rsi + 2], 't'
    jne .ident_plain
    mov eax, TK_KW_LET
    jmp .emit
.kw_len6:
    cmp rcx, 6
    jne .kw_len5
    cmp byte [rsi], 'r'
    jne .kw6_struct
    cmp byte [rsi + 1], 'e'
    jne .kw6_struct
    cmp byte [rsi + 2], 't'
    jne .kw6_struct
    cmp byte [rsi + 3], 'u'
    jne .kw6_struct
    cmp byte [rsi + 4], 'r'
    jne .kw6_struct
    cmp byte [rsi + 5], 'n'
    jne .kw6_struct
    mov eax, TK_KW_RETURN
    jmp .emit
.kw6_struct:
    cmp byte [rsi], 's'
    jne .ident_plain
    cmp byte [rsi + 1], 't'
    jne .ident_plain
    cmp byte [rsi + 2], 'r'
    jne .ident_plain
    cmp byte [rsi + 3], 'u'
    jne .ident_plain
    cmp byte [rsi + 4], 'c'
    jne .ident_plain
    cmp byte [rsi + 5], 't'
    jne .ident_plain
    mov eax, TK_KW_STRUCT
    jmp .emit
.kw_len5:
    cmp rcx, 5
    jne .kw_len4
    cmp byte [rsi], 'w'
    jne .ident_plain
    cmp byte [rsi + 1], 'h'
    jne .ident_plain
    cmp byte [rsi + 2], 'i'
    jne .ident_plain
    cmp byte [rsi + 3], 'l'
    jne .ident_plain
    cmp byte [rsi + 4], 'e'
    jne .ident_plain
    mov eax, TK_KW_WHILE
    jmp .emit
.kw_len4:
    cmp rcx, 4
    jne .ident_plain
    cmp byte [rsi], 'e'
    jne .ident_plain
    cmp byte [rsi + 1], 'l'
    jne .ident_plain
    cmp byte [rsi + 2], 's'
    jne .ident_plain
    cmp byte [rsi + 3], 'e'
    jne .ident_plain
    mov eax, TK_KW_ELSE
    jmp .emit
.ident_plain:
    mov eax, TK_IDENT
.emit:
    mov rsi, r8
    mov rdx, [rel lex_pos]
    xor ecx, ecx
    call tok_emit
    jmp .loop

; ------------------------------ 数字 --------------------------------------
.number:
    mov r8, [rel lex_pos]
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + r8]
    mov r11, 10
    cmp cl, '0'
    jne .num_start
    lea rdx, [r8 + 1]
    cmp rdx, [rel src_len]
    jae .num_start
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rdx]
    cmp cl, 'x'
    je .hex
    cmp cl, 'X'
    je .hex
    cmp cl, 'b'
    je .bin
    cmp cl, 'B'
    je .bin
    jmp .num_start
.hex:
    mov r11, 16
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .num_start
.bin:
    mov r11, 2
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2

.num_start:
    mov qword [rbp - 8], 0             ; acc
    xor r10d, r10d                     ; 数字计数
.num_loop:
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .num_end
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]
    cmp cl, '_'
    je .num_skip
    cmp r11, 16
    je .hex_digit
    cmp r11, 2
    je .bin_digit
    ; 十进制
    cmp cl, '0'
    jb .num_end
    cmp cl, '9'
    ja .num_end
    movzx ecx, cl
    sub ecx, '0'
    jmp .num_acc
.hex_digit:
    cmp cl, '0'
    jb .hex_alpha
    cmp cl, '9'
    jbe .hex_dec
.hex_alpha:
    cmp cl, 'a'
    jb .hex_upper
    cmp cl, 'f'
    ja .hex_upper
    movzx ecx, cl
    sub ecx, 'a'
    add ecx, 10
    jmp .num_acc
.hex_upper:
    cmp cl, 'A'
    jb .num_end
    cmp cl, 'F'
    ja .num_end
    movzx ecx, cl
    sub ecx, 'A'
    add ecx, 10
    jmp .num_acc
.hex_dec:
    movzx ecx, cl
    sub ecx, '0'
    jmp .num_acc
.bin_digit:
    cmp cl, '0'
    jb .num_end
    cmp cl, '1'
    ja .num_end
    movzx ecx, cl
    sub ecx, '0'
.num_acc:
    mov rdx, [rbp - 8]
    mov rax, r11
    imul rdx, rax
    movzx rax, cl
    add rdx, rax
    test rdx, rdx
    js .num_overflow
    mov [rbp - 8], rdx
    inc r10d
.num_skip:
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .num_loop
.num_end:
    test r10d, r10d
    jz .num_empty
    mov rcx, [rbp - 8]
    mov rdx, [rel lex_pos]
    mov rsi, r8
    mov eax, TK_INT
    call tok_emit
    jmp .loop
.num_empty:
    mov rdi, [rel lex_pos]
    mov esi, [rel lex_line]
    mov edx, [rel lex_col]
    lea rcx, [rel m_bad_number]
    mov r8d, m_bad_number_len
    call diag_at
    jmp .loop
.num_overflow:
    mov rdi, r8
    mov esi, [rel cur_line]
    mov edx, [rel cur_col]
    lea rcx, [rel m_int_overflow]
    mov r8d, m_int_overflow_len
    call diag_at
    ; 跳过剩余数字字符
.ov_skip:
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .loop
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]
    cmp cl, '_'
    je .ov_adv
    cmp cl, '0'
    jb .loop
    cmp cl, '9'
    ja .ov_hex
.ov_adv:
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .ov_skip
.ov_hex:
    cmp cl, 'a'
    jb .ov_up
    cmp cl, 'f'
    ja .ov_up
    jmp .ov_adv
.ov_up:
    cmp cl, 'A'
    jb .loop
    cmp cl, 'F'
    ja .loop
    jmp .ov_adv

; ------------------------------ 字符串（暂不支持）-------------------------
; ------------------------------ 字符字面量 --------------------------------
; 形如 'a'、'\n'；值写入 TK_IVAL，类型 TK_CHAR
.char:
    mov r8, [rel lex_pos]
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .char_err
    mov rdx, [rel src_ptr]
    movzx ecx, byte [rdx + rax]
    mov r9, rcx
    lea r11, [r8 + 2]
    cmp cl, 92                          ; 反斜杠
    jne .char_check
    lea rax, [r8 + 2]
    cmp rax, [rel src_len]
    jae .char_err
    movzx ecx, byte [rdx + rax]
    cmp cl, 'n'
    je .esc_n
    cmp cl, 't'
    je .esc_t
    cmp cl, 'r'
    je .esc_r
    cmp cl, '0'
    je .esc_0
    mov r9, rcx                         ; '\\'、'\'' 等原样取值
    jmp .char_esc_done
.esc_n:
    mov r9d, 10
    jmp .char_esc_done
.esc_t:
    mov r9d, 9
    jmp .char_esc_done
.esc_r:
    mov r9d, 13
    jmp .char_esc_done
.esc_0:
    xor r9d, r9d
.char_esc_done:
    lea r11, [r8 + 3]
.char_check:
    cmp r11, [rel src_len]
    jae .char_err
    mov rdx, [rel src_ptr]
    cmp byte [rdx + r11], 39
    jne .char_err
    lea rax, [r11 + 1]
    mov [rel lex_pos], rax
    mov eax, [rel lex_col]
    mov rcx, r11
    sub rcx, r8
    inc rcx
    add eax, ecx
    mov [rel lex_col], eax
    mov eax, TK_CHAR
    mov rsi, r8
    mov rdx, [rel lex_pos]
    mov rcx, r9
    call tok_emit
    jmp .loop
.char_err:
    mov [rbp - 16], r8                  ; diag_at 会破坏易失寄存器
    mov rdi, r8
    mov esi, [rel lex_line]
    mov edx, [rel lex_col]
    lea rcx, [rel m_char_unterminated]
    mov r8d, m_char_unterminated_len
    call diag_at
    mov rax, [rbp - 16]
.c_err_skip:
    cmp rax, [rel src_len]
    jae .c_err_done
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], 10
    je .c_err_done
    inc rax
    jmp .c_err_skip
.c_err_done:
    mov [rel lex_pos], rax
    jmp .loop

.string_err:
    mov rdi, [rel lex_pos]
    mov esi, [rel cur_line]
    mov edx, [rel cur_col]
    lea rcx, [rel m_string_unsupported]
    mov r8d, m_string_unsupported_len
    call diag_at
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
.s_skip:
    mov rax, [rel lex_pos]
    cmp rax, [rel src_len]
    jae .loop
    mov rsi, [rel src_ptr]
    movzx ecx, byte [rsi + rax]
    cmp cl, '"'
    je .s_close
    cmp cl, 10
    je .loop
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .s_skip
.s_close:
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .loop

; ------------------------------ 标点 --------------------------------------
.punct:
    mov r8, [rel lex_pos]
    mov rsi, r8
    inc rsi
    mov rdx, [rel src_ptr]
    movzx eax, byte [rdx + r8]
    xor ecx, ecx
    cmp al, '('
    je .p_lparen
    cmp al, ')'
    je .p_rparen
    cmp al, '{'
    je .p_lbrace
    cmp al, '}'
    je .p_rbrace
    cmp al, ','
    je .p_comma
    cmp al, ':'
    je .p_colon
    cmp al, ';'
    je .p_semi
    cmp al, '+'
    je .p_plus
    cmp al, '-'
    je .p_minus
    cmp al, '*'
    je .p_star
    cmp al, '/'
    je .p_slash
    cmp al, '%'
    je .p_percent
    cmp al, '='
    je .p_eq
    cmp al, '<'
    je .p_lt
    cmp al, '>'
    je .p_gt
    cmp al, '!'
    je .p_bang
    cmp al, '['
    je .p_lbracket
    cmp al, ']'
    je .p_rbracket
    cmp al, '^'
    je .p_caret
    cmp al, '.'
    je .p_dot
    jmp .bad
.p_dot:
    ; '.' 或 '.*'（指针解引用后缀）
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_dot1
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '*'
    jne .p_dot1
    mov eax, TK_DOTSTAR
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_dot1:
    mov eax, TK_DOT
    jmp .p_emit1
.p_lparen:
    mov eax, TK_LPAREN
    jmp .p_emit1
.p_rparen:
    mov eax, TK_RPAREN
    jmp .p_emit1
.p_lbrace:
    mov eax, TK_LBRACE
    jmp .p_emit1
.p_rbrace:
    mov eax, TK_RBRACE
    jmp .p_emit1
.p_comma:
    mov eax, TK_COMMA
    jmp .p_emit1
.p_colon:
    mov eax, TK_COLON
    jmp .p_emit1
.p_semi:
    mov eax, TK_SEMI
    jmp .p_emit1
.p_plus:
    ; '+' 或 '+='
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_plus1
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '='
    jne .p_plus1
    mov eax, TK_PLUS_ASSIGN
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_plus1:
    mov eax, TK_PLUS
    jmp .p_emit1
.p_star:
    mov eax, TK_STAR
    jmp .p_emit1
.p_slash:
    mov eax, TK_SLASH
    jmp .p_emit1
.p_percent:
    mov eax, TK_PERCENT
    jmp .p_emit1
.p_eq:
    ; '=' 或 '=='
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_assign
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '='
    jne .p_assign
    mov eax, TK_EQ
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_assign:
    mov eax, TK_ASSIGN
    jmp .p_emit1
.p_lt:
    ; '<' 或 '<='
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_lt1
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '='
    jne .p_lt1
    mov eax, TK_LE
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_lt1:
    mov eax, TK_LT
    jmp .p_emit1
.p_gt:
    ; '>' 或 '>='
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_gt1
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '='
    jne .p_gt1
    mov eax, TK_GE
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_gt1:
    mov eax, TK_GT
    jmp .p_emit1
.p_bang:
    ; 仅支持 '!='
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .bad
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '='
    jne .bad
    mov eax, TK_NE
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_lbracket:
    mov eax, TK_LBRACKET
    jmp .p_emit1
.p_rbracket:
    mov eax, TK_RBRACKET
    jmp .p_emit1
.p_caret:
    mov eax, TK_CARET
    jmp .p_emit1
.p_minus:
    ; '-' 或 '->'
    lea rax, [r8 + 1]
    cmp rax, [rel src_len]
    jae .p_minus_plain
    mov rdx, [rel src_ptr]
    cmp byte [rdx + rax], '>'
    jne .p_minus_plain
    mov eax, TK_ARROW
    mov rsi, r8
    add rsi, 2
    add qword [rel lex_pos], 2
    add dword [rel lex_col], 2
    jmp .p_emit
.p_minus_plain:
    mov eax, TK_MINUS
.p_emit1:
    add qword [rel lex_pos], 1
    add dword [rel lex_col], 1
.p_emit:
    mov rsi, r8
    mov rdx, [rel lex_pos]
    xor ecx, ecx
    call tok_emit
    jmp .loop

.bad:
    mov rdi, [rel lex_pos]
    mov esi, [rel cur_line]
    mov edx, [rel cur_col]
    lea rcx, [rel m_bad_char]
    mov r8d, m_bad_char_len
    call diag_at
    inc qword [rel lex_pos]
    inc dword [rel lex_col]
    jmp .loop

.eof:
    mov rsi, [rel src_len]
    mov rdx, rsi
    xor ecx, ecx
    xor eax, eax
    mov eax, TK_EOF
    mov r8d, [rel lex_line]
    mov [rel cur_line], r8d
    mov r8d, [rel lex_col]
    mov [rel cur_col], r8d
    call tok_emit
    mov rax, [rel tk_ptr]
    mov rdx, [rel tk_count]
    mov rsp, rbp
    pop rbp
    ret
