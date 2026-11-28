; ===========================================================================
; Parsing (stage 0): recursive descent + Pratt expressions, single precedence table.
; Output: NK_PROGRAM root; syntax errors recover at statement/function boundaries.
; ===========================================================================

; ------------------------------ node construction --------------------------
; node_new(edi=kind, esi=line, edx=col) -> rax
node_new:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov [rbp - 16], esi
    mov [rbp - 24], edx
    mov edi, ND_SIZE
    call arena_alloc
    mov ecx, [rbp - 8]
    mov [rax + ND_KIND], ecx
    mov ecx, [rbp - 16]
    mov [rax + ND_LINE], ecx
    mov ecx, [rbp - 24]
    mov [rax + ND_COL], ecx
    mov dword [rax + ND_PAD], 0
    mov qword [rax + ND_NEXT], 0
    mov qword [rax + ND_A], 0
    mov qword [rax + ND_B], 0
    mov qword [rax + ND_C], 0
    mov qword [rax + ND_VAL], 0
    mov rsp, rbp
    pop rbp
    ret

; node_tok(edi=kind, rsi=token*) -> rax
node_tok:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov [rbp - 16], rsi
    mov edx, [rsi + TK_COL]
    mov esi, [rsi + TK_LINE]
    mov edi, [rbp - 8]
    call node_new
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ basic operations ---------------------------
adv:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_EOF
    je .done
    add rax, TK_SIZE
    mov [rel ps_cur], rax
.done:
    ret

; diag_tok(rdi=token*, rsi=msg, rdx=msglen)
diag_tok:
    mov r8, rdx
    mov rcx, rsi
    mov eax, [rdi + TK_START]
    mov r9d, [rdi + TK_LINE]
    mov r10d, [rdi + TK_COL]
    mov rdi, rax
    mov rsi, r9
    mov rdx, r10
    call diag_at
    ret

; err_cur(rsi=msg, rdx=msglen)
err_cur:
    mov rdi, [rel ps_cur]
    jmp diag_tok

; expect(edi=kind, rsi=msg, rdx=msglen) -> eax=1/0
expect:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov [rbp - 16], rsi
    mov [rbp - 24], rdx
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, [rbp - 8]
    je .ok
    mov rdi, [rel ps_cur]
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call diag_tok
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret
.ok:
    call adv
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret

; check_i64(rdi=token*) -> eax=1/0
check_i64:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
    mov eax, [rdi + TK_END]
    mov ecx, [rdi + TK_START]
    sub eax, ecx
    cmp eax, 3
    jne .bad
    mov rcx, [rel src_ptr]
    mov edx, [rdi + TK_START]
    add rcx, rdx
    cmp byte [rcx], 'i'
    jne .bad
    cmp byte [rcx + 1], '6'
    jne .bad
    cmp byte [rcx + 2], '4'
    jne .bad
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret
.bad:
    mov rdi, [rbp - 8]
    lea rsi, [rel m_only_i64]
    mov edx, m_only_i64_len
    call diag_tok
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; parse_type -> eax=type code (TY_*), consuming the type Token
parse_type:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov dword [rbp - 16], 0             ; base type code
    mov dword [rbp - 20], 0             ; prefix modifier (pointer)
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_KW_FN
    je .fn_sig
    cmp dword [rax + TK_KIND], TK_LBRACKET
    je .array_type
    cmp dword [rax + TK_KIND], TK_CARET
    jne .base
    mov dword [rbp - 20], TY_PTR
    call adv
.base:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .bad
    mov [rbp - 8], rax
    mov rdi, rax
    lea rsi, [rel s_i64]
    call tok_is
    test al, al
    jnz .t_i64
    mov rdi, [rbp - 8]
    lea rsi, [rel s_u64]
    call tok_is
    test al, al
    jnz .t_i64
    mov rdi, [rbp - 8]
    lea rsi, [rel s_i32]
    call tok_is
    test al, al
    jnz .t_i32
    mov rdi, [rbp - 8]
    lea rsi, [rel s_u32]
    call tok_is
    test al, al
    jnz .t_u32
    mov rdi, [rbp - 8]
    lea rsi, [rel s_byte]
    call tok_is
    test al, al
    jnz .t_byte
    mov rdi, [rbp - 8]
    lea rsi, [rel s_u8]
    call tok_is
    test al, al
    jnz .t_byte
    mov rdi, [rbp - 8]
    call st_find_tok
    test rax, rax
    jz .bad
    mov r9d, [rax + ST_ID]
    or r9d, TY_STRUCT
    mov [rbp - 16], r9d
    jmp .adv
.bad:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_unknown_type]
    mov edx, m_unknown_type_len
    call diag_tok
    mov dword [rbp - 16], TY_I64
    call adv
    jmp .fin
.array_type:
    call adv
    call parse_type
    mov [rbp - 16], eax                 ; element type
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_INT
    jne .array_bad
    mov esi, [rax + TK_IVAL]
    mov [rbp - 24], esi
    call adv
    lea rsi, [rel m_expect_rbracket]
    mov edx, m_expect_rbracket_len
    mov edi, TK_RBRACKET
    call expect
    mov edi, [rbp - 16]
    mov esi, [rbp - 24]
    call arr_add
    jmp .done
.array_bad:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_unknown_type]
    mov edx, m_unknown_type_len
    call diag_tok
    mov eax, TY_I64
    jmp .done

.fn_sig:
    call adv                            ; consume fn
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_LPAREN
    jne .bad
.fn_params:
    call adv
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_RPAREN
    je .fn_params_done
    cmp ecx, TK_EOF
    je .fn_params_done
    cmp ecx, TK_ARROW
    je .fn_params_done
    jmp .fn_params
.fn_params_done:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RPAREN
    jne .fn_no_rp
    call adv
.fn_no_rp:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_ARROW
    jne .fn_no_ret
    call adv
    call parse_type                     ; return type (not part of the type code yet)
.fn_no_ret:
    mov dword [rbp - 16], TY_FN
    jmp .fin

.t_i64:
    mov dword [rbp - 16], TY_I64
    jmp .adv
.t_i32:
    mov dword [rbp - 16], TY_I32
    jmp .adv
.t_u32:
    mov dword [rbp - 16], TY_U32
    jmp .adv
.t_byte:
    mov dword [rbp - 16], TY_BYTE
.adv:
    call adv
.fin:
    mov eax, [rbp - 16]
    or eax, [rbp - 20]
.done:
    mov rsp, rbp
    pop rbp
    ret
sync_stmt:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
.loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_SEMI
    je .semi
    cmp ecx, TK_RBRACE
    je .done
    cmp ecx, TK_EOF
    je .done
    cmp ecx, TK_KW_FN
    je .done
    call adv
    jmp .loop
.semi:
    call adv
.done:
    mov rsp, rbp
    pop rbp
    ret

; sync_fn: skip to the next fn
sync_fn:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
.loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_KW_FN
    je .done
    cmp ecx, TK_EOF
    je .done
    call adv
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ expressions --------------------------------
; parse_expr(edi=min_bp) -> rax=node
parse_expr:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], edi
    call parse_prefix
    mov [rbp - 16], rax

.postfix:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_LBRACKET
    jne .check_deref
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 32], rax
    lea rsi, [rel m_expect_rbracket]
    mov edx, m_expect_rbracket_len
    mov edi, TK_RBRACKET
    call expect
    mov esi, 1
    mov edx, 1
    mov edi, NK_INDEX
    call node_new
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 32]
    mov [rax + ND_B], rdx
    mov [rbp - 16], rax
    jmp .postfix
.check_deref:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_DOTSTAR
    jne .check_field
    call adv
    mov esi, 1
    mov edx, 1
    mov edi, NK_DEREF
    call node_new
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov [rbp - 16], rax
    jmp .postfix
.check_field:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_DOT
    jne .try_cast
    call adv
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .try_cast
    mov rsi, rax
    mov edi, NK_FIELD
    call node_tok
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov rdx, [rel ps_cur]
    mov [rax + ND_B], rdx
    mov [rbp - 16], rax
    call adv
    jmp .postfix
.try_cast:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_AS
    jne .loop
    call adv
    call parse_type
    mov [rbp - 32], rax
    mov esi, 1
    mov edx, 1
    mov edi, NK_CAST
    call node_new
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 32]
    mov [rax + ND_VAL], rdx
    mov [rbp - 16], rax
    jmp .postfix

.loop:
    mov r10, [rel ps_cur]
    mov ecx, [r10 + TK_KIND]
    lea rdx, [rel prec_table]
    movzx eax, byte [rdx + rcx]
    test eax, eax
    jz .done
    cmp eax, [rbp - 8]
    jle .done

    mov [rbp - 24], r10                ; operator Token
    call adv
    mov r10, [rbp - 24]
    mov ecx, [r10 + TK_KIND]
    lea rdx, [rel prec_table]
    movzx edi, byte [rdx + rcx]
    call parse_expr
    mov [rbp - 32], rax

    mov rsi, [rbp - 24]
    mov edi, NK_BIN
    call node_tok
    mov rdx, [rbp - 24]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 32]
    mov [rax + ND_C], rdx
    mov [rbp - 16], rax
    jmp .loop

.done:
    mov rax, [rbp - 16]
    mov rsp, rbp
    pop rbp
    ret

; parse_prefix -> rax=node
parse_prefix:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov r10, [rel ps_cur]
    mov ecx, [r10 + TK_KIND]

    cmp ecx, TK_INT
    je .int
    cmp ecx, TK_CHAR
    je .int
    cmp ecx, TK_IDENT
    je .ident
    cmp ecx, TK_LPAREN
    je .paren
    cmp ecx, TK_LBRACKET
    je .arraylit
    cmp ecx, TK_MINUS
    je .neg

    ; Syntax error: skip the current Token and emit a placeholder literal
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_syntax]
    mov edx, m_syntax_len
    call diag_tok
    mov rsi, [rel ps_cur]
    mov edi, NK_INT
    call node_tok
    mov qword [rax + ND_VAL], 0
    mov rdx, [rel ps_cur]
    mov [rax + ND_A], rdx
    call adv
    mov rsp, rbp
    pop rbp
    ret

.int:
    mov [rbp - 8], r10
    mov rsi, r10
    mov edi, NK_INT
    call node_tok
    mov [rbp - 16], rax
    mov rsi, [rbp - 8]
    mov rdx, [rsi + TK_IVAL]
    mov [rax + ND_VAL], rdx
    mov [rax + ND_A], rsi
    call adv
    mov rax, [rbp - 16]
    mov rsp, rbp
    pop rbp
    ret

.ident:
    mov [rbp - 8], r10
    call adv
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_LPAREN
    jne .ident_maybe_struct
    mov rdi, [rbp - 8]
    call parse_call                     ; returns rax
    mov rsp, rbp
    pop rbp
    ret
.ident_maybe_struct:
    cmp dword [rax + TK_KIND], TK_LBRACE
    jne .ident_plain
    mov rdi, [rbp - 8]
    call st_find_tok
    test rax, rax
    jz .ident_plain
    mov rdi, [rbp - 8]
    call parse_struct_lit
    mov rsp, rbp
    pop rbp
    ret
.ident_plain:
    mov rsi, [rbp - 8]
    mov edi, NK_IDENT
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rsp, rbp
    pop rbp
    ret

.paren:
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax
    lea rsi, [rel m_expect_rparen]
    mov edx, m_expect_rparen_len
    mov edi, TK_RPAREN
    call expect
    mov rax, [rbp - 8]
    mov rsp, rbp
    pop rbp
    ret

.arraylit:
    call adv
    mov qword [rbp - 8], 0               ; first element
    mov qword [rbp - 16], 0              ; last element
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RBRACKET
    je .arraylit_done
.arraylit_loop:
    mov edi, 0
    call parse_expr
    cmp qword [rbp - 8], 0
    jne .arraylit_link
    mov [rbp - 8], rax
    mov [rbp - 16], rax
    jmp .arraylit_next
.arraylit_link:
    mov rcx, [rbp - 16]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 16], rax
.arraylit_next:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_COMMA
    jne .arraylit_done
    call adv
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RBRACKET
    je .arraylit_done
    jmp .arraylit_loop
.arraylit_done:
    lea rsi, [rel m_expect_rbracket]
    mov edx, m_expect_rbracket_len
    mov edi, TK_RBRACKET
    call expect
    mov esi, 1
    mov edx, 1
    mov edi, NK_ARRAYLIT
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_B], rdx
    mov rsp, rbp
    pop rbp
    ret

.neg:
    mov [rbp - 8], r10
    call adv
    mov edi, 30
    call parse_expr
    mov [rbp - 16], rax
    mov rsi, [rbp - 8]
    mov edi, NK_UNARY
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_struct_lit(rdi=struct name Token) -> rax=NK_STRUCTLIT
parse_struct_lit:
    push rbp
    mov rbp, rsp
    sub rsp, 0x70
    mov [rbp - 8], rdi
    call st_find_tok
    test rax, rax
    jz .bad
    mov [rbp - 16], rax                 ; struct record
    mov eax, [rax + ST_ID]
    or eax, TY_STRUCT
    mov [rbp - 24], eax                 ; type code
    mov rax, [rel ps_cur]
    lea rsi, [rel m_expect_lbrace]
    mov edx, m_expect_lbrace_len
    mov edi, TK_LBRACE
    call expect
    mov qword [rbp - 32], 0             ; first field
    mov qword [rbp - 40], 0             ; last field
.field_loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_RBRACE
    je .fields_done
    cmp ecx, TK_EOF
    je .fields_done
    cmp ecx, TK_IDENT
    jne .skip
    mov [rbp - 48], rax                 ; field name Token
    call adv
    lea rsi, [rel m_expect_colon]
    mov edx, m_expect_colon_len
    mov edi, TK_COLON
    call expect
    mov edi, 0
    call parse_expr
    mov [rbp - 56], rax                 ; value expression
    mov rsi, [rbp - 48]
    mov edi, NK_ASSIGN
    call node_tok
    mov rdx, [rbp - 48]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 56]
    mov [rax + ND_B], rdx
    cmp qword [rbp - 32], 0
    jne .link
    mov [rbp - 32], rax
    mov [rbp - 40], rax
    jmp .next
.link:
    mov rcx, [rbp - 40]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 40], rax
.next:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_COMMA
    je .comma
    cmp ecx, TK_SEMI
    jne .field_loop
.comma:
    call adv
    jmp .field_loop
.skip:
    call adv
    jmp .field_loop
.fields_done:
    lea rsi, [rel m_expect_rbrace]
    mov edx, m_expect_rbrace_len
    mov edi, TK_RBRACE
    call expect
    mov rax, [rel ps_cur]
    mov edi, NK_STRUCTLIT
    mov rsi, [rbp - 8]
    call node_tok
    mov rdx, [rbp - 32]
    mov [rax + ND_B], rdx
    mov edx, [rbp - 24]
    mov [rax + ND_VAL], rdx
    mov rsp, rbp
    pop rbp
    ret
.bad:
    mov rdi, [rbp - 8]
    lea rsi, [rel m_unknown_type]
    mov edx, m_unknown_type_len
    call diag_tok
    mov esi, 1
    mov edx, 1
    mov edi, NK_STRUCTLIT
    call node_new
    mov rsp, rbp
    pop rbp
    ret

; parse_call(rdi=callee token*) -> rax=NK_CALL
parse_call:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi

    lea rsi, [rel m_expect_lparen]
    mov edx, m_expect_lparen_len
    mov edi, TK_LPAREN
    call expect

    mov qword [rbp - 16], 0            ; first arg
    mov qword [rbp - 24], 0            ; last arg
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RPAREN
    je .args_done

.arg_loop:
    mov edi, 0
    call parse_expr
    mov [rbp - 32], rax
    mov esi, NK_ARG
    mov edx, 1
    mov edi, NK_ARG
    call node_new
    mov rdx, [rbp - 32]
    mov [rax + ND_A], rdx
    cmp qword [rbp - 16], 0
    jne .link
    mov [rbp - 16], rax
    mov [rbp - 24], rax
    jmp .after_link
.link:
    mov rcx, [rbp - 24]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 24], rax
.after_link:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_COMMA
    jne .args_done
    call adv
    jmp .arg_loop

.args_done:
    lea rsi, [rel m_expect_rparen]
    mov edx, m_expect_rparen_len
    mov edi, TK_RPAREN
    call expect

    mov rsi, [rbp - 8]
    mov edi, NK_CALL
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ statements --------------------------------
; parse_block: current Token is '{' -> rax=NK_BLOCK
parse_block:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    lea rsi, [rel m_expect_lbrace]
    mov edx, m_expect_lbrace_len
    mov edi, TK_LBRACE
    call expect

    mov qword [rbp - 8], 0
    mov qword [rbp - 16], 0
.loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_RBRACE
    je .done
    cmp ecx, TK_EOF
    je .done
    call parse_stmt
    test rax, rax
    jz .loop
    cmp qword [rbp - 8], 0
    jne .link
    mov [rbp - 8], rax
    mov [rbp - 16], rax
    jmp .loop
.link:
    mov rcx, [rbp - 16]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 16], rax
    jmp .loop
.done:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RBRACE
    jne .no_rbrace
    call adv
    jmp .finish
.no_rbrace:
    lea rsi, [rel m_expect_rbrace]
    mov edx, m_expect_rbrace_len
    call err_cur
.finish:
    mov esi, 1
    mov edx, 1
    mov edi, NK_BLOCK
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_stmt -> rax=node (returns 0 on failure)
parse_stmt:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_KW_LET
    je .let
    cmp ecx, TK_KW_RETURN
    je .ret
    cmp ecx, TK_LBRACE
    je .block
    cmp ecx, TK_KW_WHILE
    je .while
    cmp ecx, TK_KW_IF
    je .if
    cmp ecx, TK_IDENT
    jne .expr
    call parse_expr_or_assign
    mov rsp, rbp
    pop rbp
    ret
.let:
    call parse_let
    mov rsp, rbp
    pop rbp
    ret
.ret:
    call parse_return
    mov rsp, rbp
    pop rbp
    ret
.block:
    call parse_block
    mov rsp, rbp
    pop rbp
    ret
.while:
    call parse_while
    mov rsp, rbp
    pop rbp
    ret
.if:
    call parse_if
    mov rsp, rbp
    pop rbp
    ret
.assign:
    call parse_assign
    mov rsp, rbp
    pop rbp
    ret
.expr:
    call parse_expr_stmt
    mov rsp, rbp
    pop rbp
    ret

; parse_while -> NK_WHILE: current Token is 'while'
parse_while:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax
    call parse_block
    mov [rbp - 16], rax
    mov esi, 1
    mov edx, 1
    mov edi, NK_WHILE
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_if -> NK_IF: current Token is 'if'
parse_if:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax
    call parse_block
    mov [rbp - 16], rax
    mov qword [rbp - 24], 0
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_KW_ELSE
    jne .no_else
    call adv
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_KW_IF
    je .else_if
    call parse_block
    mov [rbp - 24], rax
    jmp .no_else
.else_if:
    call parse_if
    mov [rbp - 24], rax
.no_else:
    mov esi, 1
    mov edx, 1
    mov edi, NK_IF
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 24]
    mov [rax + ND_C], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_assign -> NK_ASSIGN：IDENT (=|+=|-=) expr ;
parse_assign:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov rax, [rel ps_cur]
    mov [rbp - 8], rax
    call adv
    mov rax, [rel ps_cur]
    mov [rbp - 16], rax
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 24], rax
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    mov rsi, [rbp - 8]
    mov edi, NK_ASSIGN
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 24]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_C], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_let -> rax=node/0
parse_let:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    call adv                              ; 'let'
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .no_name
    mov [rbp - 8], rax                   ; name token
    call adv
    jmp .name_ok
.no_name:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_ident]
    mov edx, m_expect_ident_len
    call diag_tok
    call sync_stmt
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret
.name_ok:
    lea rsi, [rel m_expect_colon]
    mov edx, m_expect_colon_len
    mov edi, TK_COLON
    call expect
    mov qword [rbp - 16], 0               ; type code
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_CARET
    je .has_type
    cmp ecx, TK_KW_FN
    je .has_type
    cmp ecx, TK_LBRACKET
    je .has_type
    cmp ecx, TK_IDENT
    jne .no_type
.has_type:
    call parse_type
    mov [rbp - 16], rax
    jmp .type_done
.no_type:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_type]
    mov edx, m_expect_type_len
    call diag_tok
.type_done:
    lea rsi, [rel m_expect_assign]
    mov edx, m_expect_assign_len
    mov edi, TK_ASSIGN
    call expect
    mov edi, 0
    call parse_expr
    mov [rbp - 24], rax
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect

    mov rsi, [rbp - 8]
    mov edi, NK_LET
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 24]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_C], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_return -> rax=node
parse_return:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    call adv
    mov qword [rbp - 8], 0
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_SEMI
    je .no_expr
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax
.no_expr:
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    mov esi, 1
    mov edx, 1
    mov edi, NK_RETURN
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rsp, rbp
    pop rbp
    ret

; parse_expr_or_assign: starts with IDENT; may be an assignment (including an
; indexed lvalue) or an expression statement
parse_expr_or_assign:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax                   ; lvalue or expression
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_ASSIGN
    je .assign
    cmp ecx, TK_PLUS_ASSIGN
    je .assign
    cmp ecx, TK_MINUS_ASSIGN
    je .assign
    ; expression statement
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    mov esi, 1
    mov edx, 1
    mov edi, NK_EXPRSTMT
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    jmp .done
.assign:
    mov [rbp - 16], rax                  ; operator Token
    call adv
    mov edi, 0
    call parse_expr
    mov [rbp - 24], rax
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    ; += / -= desugar at parse time to x = x + y / x = x - y
    mov rax, [rbp - 16]
    mov eax, [rax + TK_KIND]
    cmp eax, TK_ASSIGN
    je .assign_node
    mov esi, 1
    mov edx, 1
    mov edi, NK_BIN
    call node_new
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 8]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 24]
    mov [rax + ND_C], rdx
    mov [rbp - 24], rax
.assign_node:
    mov esi, 1
    mov edx, 1
    mov edi, NK_ASSIGN
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 24]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_C], rdx
.done:
    mov rsp, rbp
    pop rbp
    ret

; parse_expr_stmt -> rax=node
parse_expr_stmt:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov edi, 0
    call parse_expr
    mov [rbp - 8], rax
    lea rsi, [rel m_expect_semi]
    mov edx, m_expect_semi_len
    mov edi, TK_SEMI
    call expect
    mov esi, 1
    mov edx, 1
    mov edi, NK_EXPRSTMT
    call node_new
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rsp, rbp
    pop rbp
    ret

; sync_param: recover inside a parameter list, stopping at , ) { EOF
sync_param:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
.loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_COMMA
    je .done
    cmp ecx, TK_RPAREN
    je .done
    cmp ecx, TK_LBRACE
    je .done
    cmp ecx, TK_EOF
    je .done
    call adv
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ functions ----------------------------------
; parse_fn: current Token is 'fn' -> rax=NK_FN or 0
parse_fn:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    call adv

    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .no_name
    mov [rbp - 8], rax                    ; name Token
    call adv
    jmp .name_ok
.no_name:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_ident]
    mov edx, m_expect_ident_len
    call diag_tok
    call sync_fn
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret
.name_ok:
    lea rsi, [rel m_expect_lparen]
    mov edx, m_expect_lparen_len
    mov edi, TK_LPAREN
    call expect

    mov qword [rbp - 16], 0               ; first parameter
    mov qword [rbp - 24], 0               ; last parameter
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_RPAREN
    je .params_done
.param_loop:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .param_bad
    mov [rbp - 32], rax
    call adv
    lea rsi, [rel m_expect_colon]
    mov edx, m_expect_colon_len
    mov edi, TK_COLON
    call expect
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_IDENT
    je .param_type
    cmp ecx, TK_KW_FN
    je .param_type
    cmp ecx, TK_CARET
    je .param_type
    cmp ecx, TK_LBRACKET
    je .param_type
    jmp .param_notype
.param_i64:
    call parse_type
    mov [rbp - 40], eax
    jmp .param_make
.param_type:
    call parse_type
    mov [rbp - 40], eax
    jmp .param_make
.param_notype:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_type]
    mov edx, m_expect_type_len
    call diag_tok
    mov dword [rbp - 40], TY_I64
.param_make:
    mov rsi, [rbp - 32]
    mov edi, NK_PARAM
    call node_tok
    mov rdx, [rbp - 32]
    mov [rax + ND_A], rdx
    mov edx, [rbp - 40]
    mov [rax + ND_C], rdx
    cmp qword [rbp - 16], 0
    jne .param_link
    mov [rbp - 16], rax
    mov [rbp - 24], rax
    jmp .param_next
.param_link:
    mov rcx, [rbp - 24]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 24], rax
.param_next:
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_COMMA
    jne .params_done
    call adv
    jmp .param_loop
.param_bad:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_ident]
    mov edx, m_expect_ident_len
    call diag_tok
    call sync_param
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_COMMA
    jne .params_done
    call adv
    jmp .param_loop
.params_done:
    lea rsi, [rel m_expect_rparen]
    mov edx, m_expect_rparen_len
    mov edi, TK_RPAREN
    call expect

    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_ARROW
    jne .no_ret
    call adv
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_IDENT
    je .ret_type
    cmp ecx, TK_KW_FN
    je .ret_type
    cmp ecx, TK_CARET
    je .ret_type
    cmp ecx, TK_LBRACKET
    je .ret_type
    jmp .ret_type_err
.ret_type:
    call parse_type
    jmp .no_ret
.ret_type_err:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_type]
    mov edx, m_expect_type_len
    call diag_tok
.no_ret:
    call parse_block
    mov [rbp - 40], rax

    mov rsi, [rbp - 8]
    mov edi, NK_FN
    call node_tok
    mov rdx, [rbp - 8]
    mov [rax + ND_A], rdx
    mov rdx, [rbp - 16]
    mov [rax + ND_B], rdx
    mov rdx, [rbp - 40]
    mov [rax + ND_C], rdx
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ top level ----------------------------------
; parse_run(rdi=token*, rsi=count) -> rax=NK_PROGRAM
parse_run:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rel ps_cur], rdi
    mov [rel ps_base], rdi

    mov esi, 1
    mov edx, 1
    mov edi, NK_PROGRAM
    call node_new
    mov [rbp - 8], rax                    ; root
    mov qword [rbp - 16], 0               ; first function
    mov qword [rbp - 24], 0               ; last function

.loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_EOF
    je .done
    cmp ecx, TK_KW_FN
    je .fn
    cmp ecx, TK_KW_STRUCT
    je .struct
    lea rsi, [rel m_expect_fn]
    mov edx, m_expect_fn_len
    call err_cur
    call sync_fn
    jmp .loop
.struct:
    call parse_struct
    jmp .loop
.fn:
    call parse_fn
    test rax, rax
    jz .loop
    cmp qword [rbp - 16], 0
    jne .link
    mov [rbp - 16], rax
    mov [rbp - 24], rax
    jmp .loop
.link:
    mov rcx, [rbp - 24]
    mov [rcx + ND_NEXT], rax
    mov [rbp - 24], rax
    jmp .loop
.done:
    mov rax, [rbp - 8]
    mov rdx, [rbp - 16]
    mov [rax + ND_A], rdx
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ struct declarations -------------------------
; Current Token is the struct keyword; parse fields and register the struct table
parse_struct:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    call adv
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_IDENT
    jne .bad_name
    mov [rbp - 8], rax                  ; struct name Token
    mov rdi, rax
    call tok_text
    mov [rbp - 16], rax
    mov rdi, [rbp - 8]
    call tok_len
    mov [rbp - 24], rax
    call adv
    lea rsi, [rel m_expect_lbrace]
    mov edx, m_expect_lbrace_len
    mov edi, TK_LBRACE
    call expect
    mov rdi, [rbp - 16]
    mov rsi, [rbp - 24]
    call st_add
    mov [rbp - 32], rax                 ; struct record
.field_loop:
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_RBRACE
    je .fields_done
    cmp ecx, TK_EOF
    je .fields_done
    cmp ecx, TK_IDENT
    jne .field_skip
    mov [rbp - 40], rax                 ; field name Token
    call adv
    lea rsi, [rel m_expect_colon]
    mov edx, m_expect_colon_len
    mov edi, TK_COLON
    call expect
    call parse_type
    mov [rbp - 48], eax
    mov rdi, [rbp - 40]
    call tok_text
    mov [rbp - 56], rax
    mov rdi, [rbp - 40]
    call tok_len
    mov edx, eax
    mov rdi, [rbp - 32]
    mov rsi, [rbp - 56]
    mov ecx, [rbp - 48]
    call sf_add
    mov rax, [rel ps_cur]
    mov ecx, [rax + TK_KIND]
    cmp ecx, TK_COMMA
    je .field_comma
    cmp ecx, TK_SEMI
    jne .field_loop
.field_comma:
    call adv
    jmp .field_loop
.field_skip:
    call adv
    jmp .field_loop
.fields_done:
    lea rsi, [rel m_expect_rbrace]
    mov edx, m_expect_rbrace_len
    mov edi, TK_RBRACE
    call expect
    mov rax, [rel ps_cur]
    cmp dword [rax + TK_KIND], TK_SEMI
    jne .done
    call adv
.done:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret
.bad_name:
    mov rdi, [rel ps_cur]
    lea rsi, [rel m_expect_ident]
    mov edx, m_expect_ident_len
    call diag_tok
    call sync_fn
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ struct table -------------------------------
; st_add(rdi=name pointer, rsi=length) -> rax=record
st_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov edi, ST_REC
    call arena_alloc
    mov [rbp - 24], rax
    mov edx, [rel struct_count]
    mov [rax + ST_ID], edx
    inc dword [rel struct_count]
    mov rdx, [rbp - 8]
    mov [rax + ST_NAME], rdx
    mov rdx, [rbp - 16]
    mov [rax + ST_LEN], edx
    mov dword [rax + ST_SZ], 0
    mov qword [rax + ST_FIELDS], 0
    mov rdx, [rel struct_head]
    mov [rax + ST_NEXT], rdx
    mov [rel struct_head], rax
    mov rsp, rbp
    pop rbp
    ret

; st_find(rdi=name pointer, rsi=length) -> rax=record / 0
st_find:
    mov rdx, [rel struct_head]
.loop:
    test rdx, rdx
    jz .no
    mov eax, [rdx + ST_LEN]
    cmp eax, esi
    jne .next
    mov r8, [rdx + ST_NAME]
    xor ecx, ecx
.cmp:
    cmp rcx, rsi
    jae .yes
    mov al, [r8 + rcx]
    cmp al, [rdi + rcx]
    jne .next
    inc rcx
    jmp .cmp
.yes:
    mov rax, rdx
    ret
.next:
    mov rdx, [rdx + ST_NEXT]
    jmp .loop
.no:
    xor eax, eax
    ret

; st_find_tok(rdi=Token) -> rax=record / 0
st_find_tok:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
    call tok_text
    mov [rbp - 16], rax
    mov rdi, [rbp - 8]
    call tok_len
    mov rsi, rax
    mov rdi, [rbp - 16]
    call st_find
    mov rsp, rbp
    pop rbp
    ret

; sf_add(rdi=struct record, rsi=field name pointer, edx=length, ecx=type) -> eax=offset
sf_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov edi, SF_REC
    call arena_alloc
    mov [rbp - 40], rax
    mov rdx, [rbp - 16]
    mov [rax + SF_NAME], rdx
    mov edx, [rbp - 24]
    mov [rax + SF_LEN], edx
    mov rdx, [rbp - 8]
    mov ecx, [rdx + ST_SZ]
    mov [rax + SF_OFF], ecx
    mov edx, [rbp - 32]
    mov [rax + SF_TYPE], edx
    mov rdi, [rbp - 40]
    mov rdi, [rdi + SF_TYPE]
    call type_size
    mov rdx, [rbp - 8]
    add [rdx + ST_SZ], eax
    mov rdx, [rbp - 8]
    mov rdx, [rdx + ST_FIELDS]
    mov rax, [rbp - 40]
    mov [rax + SF_NEXT], rdx
    mov rdx, [rbp - 8]
    mov [rdx + ST_FIELDS], rax
    mov rax, [rbp - 40]
    mov eax, [rax + SF_OFF]
    mov rsp, rbp
    pop rbp
    ret

; sf_find(rdi=struct record, rsi=name pointer, edx=length) -> rax=field record / 0
sf_find:
    mov r8, [rdi + ST_FIELDS]
.loop:
    test r8, r8
    jz .no
    mov eax, [r8 + SF_LEN]
    cmp eax, edx
    jne .next
    mov r9, [r8 + SF_NAME]
    xor ecx, ecx
.cmp:
    cmp rcx, rdx
    jae .yes
    mov al, [r9 + rcx]
    cmp al, [rsi + rcx]
    jne .next
    inc rcx
    jmp .cmp
.yes:
    mov rax, r8
    ret
.next:
    mov r8, [r8 + SF_NEXT]
    jmp .loop
.no:
    xor eax, eax
    ret

; sf_find_tok(edi=struct type code, rsi=field name Token) -> rax=field record
sf_find_tok:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rbp - 8], edi
    mov [rbp - 16], rsi
    and edi, 0x3F
    mov rdx, [rel struct_head]
.find_struct:
    test rdx, rdx
    jz .none
    cmp [rdx + ST_ID], edi
    je .got_struct
    mov rdx, [rdx + ST_NEXT]
    jmp .find_struct
.got_struct:
    mov [rbp - 24], rdx
    mov rdi, [rbp - 16]
    call tok_text
    mov [rbp - 32], rax
    mov rdi, [rbp - 16]
    call tok_len
    mov edx, eax
    mov rdi, [rbp - 24]
    mov rsi, [rbp - 32]
    call sf_find
.none:
    mov rsp, rbp
    pop rbp
    ret

; arr_add(edi=element type, esi=element count) -> eax=array type code
arr_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], edi
    mov [rbp - 16], esi
    mov edi, AR_REC
    call arena_alloc
    mov [rbp - 24], rax
    mov edx, [rel array_count]
    mov [rax + AR_ID], edx
    inc dword [rel array_count]
    mov edx, [rbp - 8]
    mov [rax + AR_ELEM], edx
    mov edx, [rbp - 16]
    mov [rax + AR_COUNT], edx
    mov edi, [rbp - 8]
    call type_size
    mov edx, [rbp - 16]
    imul eax, edx
    mov rdx, [rbp - 24]
    mov [rdx + AR_SZ], eax
    mov rax, [rel array_head]
    mov [rdx + AR_NEXT], rax
    mov [rel array_head], rdx
    mov eax, [rel array_count]
    dec eax
    or eax, TY_ARRAY
    mov rsp, rbp
    pop rbp
    ret
