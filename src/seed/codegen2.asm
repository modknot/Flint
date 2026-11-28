; ===========================================================================
; Semantic checks (stage 0 subset) + function code generation + entry + backfill + PE output
; ===========================================================================

; ------------------------------ name comparison ----------------------------
name_eq:
    cmp rsi, rcx
    jne .no
    xor eax, eax
.loop:
    cmp rax, rsi
    jae .yes
    mov r8b, [rdi + rax]
    cmp r8b, [rdx + rax]
    jne .no
    inc rax
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; diag_name(rdi=tok, rsi=msg, rdx=len)
diag_name:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rsi
    mov [rbp - 16], rdx
    mov [rbp - 24], rdi
    call tok_text
    mov [rel diag_name_ptr], rax
    mov rdi, [rbp - 24]
    call tok_len
    mov [rel diag_name_len], rax
    mov rdi, [rbp - 24]
    mov rsi, [rbp - 8]
    mov rdx, [rbp - 16]
    call diag_tok
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ function collection ------------------------
collect_functions:
    push rbp
    mov rbp, rsp
    sub rsp, 0xA0
    mov rax, [rdi + ND_A]
    mov [rbp - 8], rax

.node_loop:
    mov rax, [rbp - 8]
    test rax, rax
    jz .done
    mov [rbp - 16], rax
    mov rax, [rax + ND_A]
    mov [rbp - 24], rax                  ; name Token

    ; reserved name print
    mov rdi, [rbp - 24]
    lea rsi, [rel s_print]
    call tok_is
    test al, al
    jz .arity
    mov rdi, [rbp - 24]
    lea rsi, [rel m_print_reserved]
    mov edx, m_print_reserved_len
    call diag_tok
    jmp .next

.arity:
    mov rax, [rbp - 16]
    mov rdx, [rax + ND_B]
    xor ecx, ecx
.count:
    test rdx, rdx
    jz .counted
    inc ecx
    mov rdx, [rdx + ND_NEXT]
    jmp .count
.counted:
    mov [rbp - 32], ecx
    cmp ecx, 4
    jbe .dup_params
    mov rdi, [rbp - 24]
    lea rsi, [rel m_too_many_args]
    mov edx, m_too_many_args_len
    call diag_tok
    jmp .next

.dup_params:
    mov rax, [rbp - 16]
    mov rax, [rax + ND_B]
    mov [rbp - 40], rax
.outer:
    mov rax, [rbp - 40]
    test rax, rax
    jz .dup_done
    mov rax, [rax + ND_A]
    mov [rbp - 48], rax                  ; p1 token
    mov rax, [rbp - 40]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 56], rax
.inner:
    mov rax, [rbp - 56]
    test rax, rax
    jz .outer_next
    mov rax, [rax + ND_A]
    mov [rbp - 64], rax                  ; p2 token

    mov rdi, [rbp - 48]
    call tok_text
    mov [rbp - 72], rax
    mov rdi, [rbp - 48]
    call tok_len
    mov [rbp - 80], rax
    mov rdi, [rbp - 64]
    call tok_text
    mov rdx, rax
    mov rdi, [rbp - 64]
    call tok_len
    mov rcx, rax
    mov rdi, [rbp - 72]
    mov rsi, [rbp - 80]
    call name_eq
    test al, al
    jz .inner_next
    mov rdi, [rbp - 64]
    lea rsi, [rel m_dup_param]
    mov edx, m_dup_param_len
    call diag_tok
    jmp .dup_done
.inner_next:
    mov rax, [rbp - 56]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 56], rax
    jmp .inner
.outer_next:
    mov rax, [rbp - 40]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 40], rax
    jmp .outer
.dup_done:

    ; duplicate check + registration
    mov rdi, [rbp - 24]
    call tok_text
    mov [rbp - 72], rax
    mov rdi, [rbp - 24]
    call tok_len
    mov [rbp - 80], rax
    mov rdi, [rbp - 72]
    mov rsi, [rbp - 80]
    call fn_find
    test rax, rax
    jz .add
    mov rdi, [rbp - 24]
    lea rsi, [rel m_dup_fn]
    mov edx, m_dup_fn_len
    call diag_tok
    jmp .next
.add:
    mov rdi, [rbp - 72]
    mov rsi, [rbp - 80]
    mov rdx, [rbp - 16]
    mov ecx, [rbp - 32]
    call fn_add

.next:
    mov rax, [rbp - 16]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 8], rax
    jmp .node_loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ types and lvalues --------------------------
; type_size(edi=type code) -> eax=byte size (base type size)
type_size:
    mov eax, edi
    test eax, TY_ARRAY
    jnz .array
    test eax, TY_STRUCT
    jnz .struct
    test eax, TY_PTR | TY_FN
    jnz .eight
    and eax, 0x0F
    cmp eax, TY_BYTE
    je .one
    cmp eax, TY_U8
    je .one
    cmp eax, TY_U32
    je .four
    cmp eax, TY_I32
    je .four
.eight:
    mov eax, 8
    ret
.one:
    mov eax, 1
    ret
.four:
    mov eax, 4
    ret
.struct:
    and eax, 0x3F
    mov rdx, [rel struct_head]
.s_loop:
    test rdx, rdx
    jz .eight
    cmp [rdx + ST_ID], eax
    je .s_hit
    mov rdx, [rdx + ST_NEXT]
    jmp .s_loop
.s_hit:
    mov eax, [rdx + ST_SZ]
    ret
.array:
    and eax, 0x3F
    mov rdx, [rel array_head]
.a_loop:
    test rdx, rdx
    jz .eight
    cmp [rdx + AR_ID], eax
    je .a_hit
    mov rdx, [rdx + AR_NEXT]
    jmp .a_loop
.a_hit:
    mov eax, [rdx + AR_SZ]
    ret

; elem_type(edi=container type) -> eax=element type (arrays return their element; pointers return their base type)
elem_type:
    mov eax, edi
    test eax, TY_ARRAY
    jnz .array
    test eax, TY_PTR
    jnz .ptr
    xor eax, eax
    ret
.array:
    and eax, 0x3F
    mov rdx, [rel array_head]
.a_loop:
    test rdx, rdx
    jz .none
    cmp [rdx + AR_ID], eax
    je .hit
    mov rdx, [rdx + AR_NEXT]
    jmp .a_loop
.hit:
    mov eax, [rdx + AR_ELEM]
    ret
.ptr:
    mov eax, edi
    and eax, ~TY_PTR
    ret
.none:
    xor eax, eax
    ret
node_type:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi
    test rdi, rdi
    jz .zero
    mov eax, [rdi + ND_KIND]
    cmp eax, NK_IDENT
    je .ident
    cmp eax, NK_INDEX
    je .index
    cmp eax, NK_CAST
    je .cast
    cmp eax, NK_DEREF
    je .deref
    cmp eax, NK_FIELD
    je .field
.zero:
    xor eax, eax
    jmp .done
.ident:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 16], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 24], rax
    mov rdi, [rbp - 16]
    call tok_len
    mov rsi, rax
    mov rdi, [rbp - 24]
    call local_type
    jmp .done
.index:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov edi, eax
    call elem_type
    jmp .done
.field:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    test eax, TY_PTR
    jz .field_type_ready
    mov edi, eax
    call elem_type
.field_type_ready:
    cmp eax, TY_STRUCT
    jb .zero
    test eax, TY_STRUCT
    jz .zero
    mov edi, eax
    mov rax, [rbp - 8]
    mov rsi, [rax + ND_B]
    call sf_find_tok
    test rax, rax
    jz .zero
    mov eax, [rax + SF_TYPE]
    jmp .done
.cast:
    mov rax, [rbp - 8]
    mov eax, [rax + ND_VAL]
    jmp .done
.deref:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov edi, eax
    call elem_type
    jmp .done
.done:
    mov rsp, rbp
    pop rbp
    ret

; gen_addr(rdi=node) -> rax=lvalue address (NK_IDENT / NK_INDEX)
gen_addr:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    mov eax, [rdi + ND_KIND]
    cmp eax, NK_IDENT
    je .ident
    cmp eax, NK_INDEX
    je .index
    cmp eax, NK_DEREF
    je .deref
    cmp eax, NK_FIELD
    je .field
    xor eax, eax
    jmp .done
.ident:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 16], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 24], rax
    mov rdi, [rbp - 16]
    call tok_len
    mov [rbp - 32], rax
    mov rdi, [rbp - 24]
    mov rsi, [rbp - 32]
    call local_find
    cmp rax, -1
    je .undef
    mov edx, eax                         ; LV_SLOT stores disp directly
    mov edi, 0x8D                       ; lea rax,[rbp+disp]
    xor esi, esi
    call emit_rm_disp
    jmp .done
.index:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov [rbp - 56], eax
    test eax, TY_PTR
    jnz .index_ptrbase
    test eax, TY_ARRAY
    jnz .index_localbase
    test eax, TY_STRUCT
    jnz .index_localbase
    jmp .index_ptrbase
.index_ptrbase:
    mov rdi, [rbp - 8]
    mov rdi, [rdi + ND_A]
    call gen_expr                       ; pointer: runtime value is the base address
    jmp .index_base_ready
.index_localbase:
    mov rdi, [rbp - 8]
    mov rdi, [rdi + ND_A]
    call gen_addr                       ; array/struct: take the storage address
.index_base_ready:
    call emit_push_rax
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov edi, eax
    call elem_type
    mov edi, eax
    call type_size
    mov [rbp - 48], eax                 ; element size
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_expr                       ; runtime: index -> rax
    mov ecx, [rbp - 48]
    cmp ecx, 8
    je .mul8
    cmp ecx, 4
    je .mul4
    cmp ecx, 1
    je .mul_done
    jmp .mul_generic
.mul8:
    mov eax, 0x48                       ; imul rax,rax,8
    call cb_b
    mov eax, 0x6B
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 8
    call cb_b
    jmp .mul_done
.mul4:
    mov eax, 0x48                       ; imul rax,rax,4
    call cb_b
    mov eax, 0x6B
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 4
    call cb_b
    jmp .mul_done
.mul_generic:
    mov eax, 0x48                       ; imul rax,rax,imm32
    call cb_b
    mov eax, 0x69
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, [rbp - 48]
    call cb_d
.mul_done:
    mov edi, 9                          ; pop base address into r9
    call emit_pop_reg
    mov eax, 0x4C                       ; add rax,r9
    call cb_b
    mov eax, 0x01
    call cb_b
    mov eax, 0xC8
    call cb_b
    jmp .done
.deref:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_expr                       ; pointer value is the address
    jmp .done
.field:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov [rbp - 72], eax                 ; base type
    test eax, TY_PTR
    jz .field_base_obj
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_expr                       ; pointer: runtime value is the struct address
    jmp .field_base_ready
.field_base_obj:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_addr
.field_base_ready:
    mov [rbp - 56], rax                 ; base address
    mov eax, [rbp - 72]
    test eax, TY_PTR
    jz .field_type_ready
    mov edi, eax
    call elem_type
.field_type_ready:
    mov edi, eax
    mov rax, [rbp - 8]
    mov rsi, [rax + ND_B]
    call sf_find_tok
    test rax, rax
    jz .field_done
    mov edx, [rax + SF_OFF]
    mov [rbp - 64], edx
    test edx, edx
    jz .field_done
    mov rax, [rbp - 56]
    mov eax, 0x48                       ; add rax,imm32
    call cb_b
    mov eax, 0x05
    call cb_b
    mov eax, [rbp - 64]
    call cb_d
.field_done:
    mov rax, [rbp - 56]
    jmp .done
.undef:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    lea rsi, [rel m_undef]
    mov edx, m_undef_len
    call diag_name
    xor eax, eax
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ expression generation ----------------------
gen_expr:
    push rbp
    mov rbp, rsp
    sub rsp, 0x90
    mov [rbp - 8], rdi
    mov rax, [rdi + ND_KIND]

    cmp eax, NK_INT
    je .int
    cmp eax, NK_IDENT
    je .ident
    cmp eax, NK_BIN
    je .bin
    cmp eax, NK_UNARY
    je .unary
    cmp eax, NK_CALL
    je .call
    cmp eax, NK_INDEX
    je .index
    cmp eax, NK_CAST
    je .cast
    cmp eax, NK_DEREF
    je .index
    cmp eax, NK_FIELD
    je .index
    jmp .internal

.int:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_VAL]
    call emit_imm64
    jmp .done

.ident:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 16], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 56], rax
    mov rdi, [rbp - 16]
    call tok_len
    mov [rbp - 64], rax
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 64]
    call local_find
    cmp rax, -1
    je .ident_not_local
    mov edx, eax                         ; LV_SLOT stores disp directly
    mov [rbp - 72], edx
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 64]
    call local_type
    mov ecx, eax
    mov edx, [rbp - 72]
    call load_local
    jmp .done
.ident_not_local:
    mov rdi, [rbp - 16]
    call fn_find_tok
    test rax, rax
    jz .ident_undef
    cmp dword [rel cg_no_fnval], 0
    je .ident_fnaddr
    mov rdi, [rbp - 16]
    lea rsi, [rel m_fn_as_value]
    mov edx, m_fn_as_value_len
    call diag_name
    jmp .ident_zero
.ident_fnaddr:
    mov rax, [rbp - 16]
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 64]
    mov edx, [rax + TK_LINE]
    mov ecx, [rax + TK_COL]
    mov r8d, [rax + TK_START]
    call emit_fnaddr_fixup              ; function name as value: address patch
    jmp .done
.ident_undef:
    mov rdi, [rbp - 16]
    lea rsi, [rel m_undef]
    mov edx, m_undef_len
    call diag_name
.ident_zero:
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .done

.bin:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_C]
    call gen_expr
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC1
    call cb_b
    call emit_pop_rax
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov eax, [rax + TK_KIND]
    cmp eax, TK_PLUS
    je .op_add
    cmp eax, TK_MINUS
    je .op_sub
    cmp eax, TK_PLUS_ASSIGN              ; desugared +=
    je .op_add
    cmp eax, TK_MINUS_ASSIGN
    je .op_sub
    cmp eax, TK_STAR
    je .op_mul
    cmp eax, TK_SLASH
    je .op_div
    cmp eax, TK_PERCENT
    je .op_mod
    cmp eax, TK_LT
    je .op_lt
    cmp eax, TK_GT
    je .op_gt
    cmp eax, TK_LE
    je .op_le
    cmp eax, TK_GE
    je .op_ge
    cmp eax, TK_EQ
    je .op_eq
    cmp eax, TK_NE
    je .op_ne
    jmp .internal
.op_add:
    mov eax, 0x48
    call cb_b
    mov eax, 0x01
    call cb_b
    mov eax, 0xC8
    call cb_b
    jmp .done
.op_sub:
    mov eax, 0x48
    call cb_b
    mov eax, 0x29
    call cb_b
    mov eax, 0xC8
    call cb_b
    jmp .done
.op_mul:
    mov eax, 0x48
    call cb_b
    mov eax, 0x0F
    call cb_b
    mov eax, 0xAF
    call cb_b
    mov eax, 0xC1
    call cb_b
    jmp .done
.op_div:
    mov eax, 0x48
    call cb_b
    mov eax, 0x99
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0xF7
    call cb_b
    mov eax, 0xF9
    call cb_b
    jmp .done
.op_mod:
    mov eax, 0x48
    call cb_b
    mov eax, 0x99
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0xF7
    call cb_b
    mov eax, 0xF9
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xD0
    call cb_b
    jmp .done

; comparison: cmp rax,rcx -> setcc al -> movzx eax,al (result 0/1)
.op_lt:
    mov r9d, 0x9C
    jmp .cmp_emit
.op_gt:
    mov r9d, 0x9F
    jmp .cmp_emit
.op_le:
    mov r9d, 0x9E
    jmp .cmp_emit
.op_ge:
    mov r9d, 0x9D
    jmp .cmp_emit
.op_eq:
    mov r9d, 0x94
    jmp .cmp_emit
.op_ne:
    mov r9d, 0x95
.cmp_emit:
    mov [rbp - 72], r9d
    mov eax, 0x48
    call cb_b
    mov eax, 0x39
    call cb_b
    mov eax, 0xC8
    call cb_b
    mov eax, 0x0F
    call cb_b
    mov eax, [rbp - 72]
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 0x0F
    call cb_b
    mov eax, 0xB6
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .done

.unary:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_expr
    mov eax, 0x48
    call cb_b
    mov eax, 0xF7
    call cb_b
    mov eax, 0xD8
    call cb_b
    jmp .done

.index:
    mov rax, [rbp - 8]
    mov rdi, rax
    call gen_addr
    mov rax, [rbp - 8]
    mov rdi, rax
    call node_type
    mov edi, eax
    call type_size
    cmp eax, 1
    je .idx_load1
    cmp eax, 4
    je .idx_load4
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    xor eax, eax
    call cb_b
    jmp .done
.idx_load4:
    mov eax, 0x8B
    call cb_b
    xor eax, eax
    call cb_b
    jmp .done
.idx_load1:
    mov eax, 0x0F
    call cb_b
    mov eax, 0xB6
    call cb_b
    xor eax, eax
    call cb_b
    jmp .done

.cast:
    mov rax, [rbp - 8]
    mov edi, [rax + ND_VAL]
    mov [rbp - 80], edi
    mov rdi, [rax + ND_A]
    call gen_expr
    mov edi, [rbp - 80]
    test edi, TY_PTR
    jnz .done                           ; pointer conversion does not change width
    and edi, 0x0F
    cmp edi, TY_BYTE
    jne .cast_u32
    mov eax, 0x25                      ; and eax,0xFF
    call cb_b
    mov eax, 0xFF
    call cb_b
    xor eax, eax
    call cb_b
    call cb_b
    call cb_b
    jmp .done
.cast_u32:
    cmp edi, TY_U32
    jne .done
    mov eax, 0x89                      ; mov eax,eax (clear upper 32 bits)
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .done

.call:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 16], rax
    mov rdi, rax
    lea rsi, [rel s_print]
    call tok_is
    test al, al
    jnz .print_call

    mov rdi, [rbp - 16]
    lea rsi, [rel s_alloc]
    call tok_is
    test al, al
    jnz .alloc_call

    mov rdi, [rbp - 16]
    lea rsi, [rel s_free]
    call tok_is
    test al, al
    jnz .free_call

    mov rdi, [rbp - 16]
    lea rsi, [rel s_writefile]
    call tok_is
    test al, al
    jnz .writefile_call

    mov rdi, [rbp - 16]
    lea rsi, [rel s_readfile]
    call tok_is
    test al, al
    jnz .readfile_call

    ; If callee is a local of function-pointer type, use an indirect call
    mov rax, [rbp - 16]
    mov [rbp - 96], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 24], rax
    mov rdi, [rbp - 96]
    call tok_len
    mov [rbp - 32], rax
    mov rdi, [rbp - 24]
    mov rsi, [rbp - 32]
    call local_find
    cmp rax, -1
    je .normal_call
    mov [rbp - 88], rax                 ; slot number
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    mov [rbp - 32], rax
    jmp .fnptr_eval

.fnptr_eval:
    mov rax, [rbp - 32]
    test rax, rax
    jz .fnptr_pops
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax
    jmp .fnptr_eval
.fnptr_pops:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    xor ecx, ecx
.fnptr_count:
    test rax, rax
    jz .fnptr_counted
    inc ecx
    mov rax, [rax + ND_NEXT]
    jmp .fnptr_count
.fnptr_counted:
    mov [rbp - 40], ecx
.fnptr_pop_loop:
    cmp dword [rbp - 40], 0
    je .fnptr_call
    dec dword [rbp - 40]
    mov eax, [rbp - 40]
    lea rdx, [rel param_regs]
    movzx edi, byte [rdx + rax]
    call emit_pop_reg
    jmp .fnptr_pop_loop
.fnptr_call:
    mov rsi, [rbp - 96]
    mov edi, NK_IDENT
    call node_tok
    mov rdx, [rbp - 96]
    mov [rax + ND_A], rdx
    mov rdi, rax
    call gen_expr                       ; rax = function pointer value
    mov eax, 0xFF                       ; call rax
    call cb_b
    mov eax, 0xD0
    call cb_b
    jmp .done

.normal_call:

    mov rdi, [rbp - 16]
    call fn_find_tok
    test rax, rax
    jz .undef_fn
    mov [rbp - 16], rax                  ; function record

    mov rax, [rbp - 8]
    mov rdx, [rax + ND_B]
    xor ecx, ecx
.count_args:
    test rdx, rdx
    jz .args_counted
    inc ecx
    mov rdx, [rdx + ND_NEXT]
    jmp .count_args
.args_counted:
    mov [rbp - 24], ecx
    mov rax, [rbp - 16]
    cmp ecx, [rax + FN_ARITY]
    je .arity_ok
    mov rdi, [rbp - 16]                  ; a record cannot be used as a Token
    mov rdi, [rbp - 8]
    mov rdi, [rdi + ND_A]
    lea rsi, [rel m_arity]
    mov edx, m_arity_len
    call diag_tok
.arity_ok:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    mov [rbp - 32], rax
.arg_loop:
    mov rax, [rbp - 32]
    test rax, rax
    jz .args_done
    mov rax, [rax + ND_A]
    mov [rbp - 56], rax
    cmp dword [rax + ND_KIND], NK_IDENT
    jne .arg_plain
    mov rdi, [rbp - 56]
    mov rdi, [rdi + ND_A]
    call fn_find_tok
    test rax, rax
    jz .arg_plain
    mov rax, [rbp - 56]
    mov rax, [rax + ND_A]
    mov [rbp - 80], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 64], rax
    mov rdi, [rbp - 80]
    call tok_len
    mov [rbp - 72], rax
    mov rax, [rbp - 80]
    mov rdi, [rbp - 64]
    mov rsi, [rbp - 72]
    mov edx, [rax + TK_LINE]
    mov ecx, [rax + TK_COL]
    mov r8d, [rax + TK_START]
    call emit_fnaddr_fixup
    jmp .arg_pushed
.arg_plain:
    mov rdi, [rbp - 56]
    call gen_expr
.arg_pushed:
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax
    jmp .arg_loop
.args_done:
    mov eax, [rbp - 24]
    mov [rbp - 40], eax
.pop_loop:
    cmp dword [rbp - 40], 0
    je .pops_done
    dec dword [rbp - 40]
    mov eax, [rbp - 40]
    lea rdx, [rel param_regs]
    movzx edi, byte [rdx + rax]
    call emit_pop_reg
    jmp .pop_loop
.pops_done:
    mov eax, [rel cg_depth]
    and eax, 1
    mov [rbp - 48], eax
    test eax, eax
    jz .no_pad
    mov edi, 8
    call emit_sub_rsp
    inc dword [rel cg_depth]
.no_pad:
    ; get the callee name Token information
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 88], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 56], rax
    mov rdi, [rbp - 88]
    call tok_len
    mov [rbp - 64], rax
    mov rax, [rbp - 88]
    mov ecx, [rax + TK_LINE]
    mov [rbp - 72], rcx
    mov ecx, [rax + TK_COL]
    mov [rbp - 80], rcx
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 64]
    mov edx, [rbp - 72]
    mov ecx, [rbp - 80]
    mov rax, [rbp - 88]
    mov r8d, [rax + TK_START]
    call emit_call_fixup
    cmp dword [rbp - 48], 0
    je .done
    mov edi, 8
    call emit_add_rsp
    dec dword [rel cg_depth]
    jmp .done

.alloc_call:
    ; alloc(size, align) -> VirtualAlloc(0, size, MEM_COMMIT|MEM_RESERVE, PAGE_READWRITE)
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    test rax, rax
    jz .alloc_noarg
    mov rdi, [rax + ND_A]
    call gen_expr
    jmp .alloc_sized
.alloc_noarg:
    mov edi, 0x1000
    call emit_imm64
.alloc_sized:
    mov eax, 0x48                       ; mov rdx,rax
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC2
    call cb_b
    mov eax, 0x31                       ; xor ecx,ecx
    call cb_b
    mov eax, 0xC9
    call cb_b
    mov eax, 0x41                       ; mov r8d,0x3000
    call cb_b
    mov eax, 0xB8
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x30
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x41                       ; mov r9d,4
    call cb_b
    mov eax, 0xB9
    call cb_b
    mov eax, 0x04
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x00
    call cb_b
    mov edi, 0xFF                       ; call [iat+24]
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 24
    xor ecx, ecx
    call emit_rip
    jmp .done

.free_call:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    test rax, rax
    jz .free_zero
    mov rdi, [rax + ND_A]
    call gen_expr                       ; rax = ptr
    mov eax, 0x48                       ; mov rcx,rax
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC1
    call cb_b
    mov eax, 0x31                       ; xor edx,edx
    call cb_b
    mov eax, 0xD2
    call cb_b
    mov eax, 0x41                       ; mov r8d,0x8000 (MEM_RELEASE)
    call cb_b
    mov eax, 0xB8
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x80
    call cb_b
    mov eax, 0x00
    call cb_b
    mov eax, 0x00
    call cb_b
    mov edi, 0xFF                       ; call [iat+32]
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 32
    xor ecx, ecx
    call emit_rip
.free_zero:
    jmp .done

; writefile(path:^u8, pathlen:i64, data:^u8, len:i64) -> i64
; Paths are passed to CreateFileA as single-byte ANSI/UTF-8; returns 1 on success.
.writefile_call:
    mov rax, [rbp - 8]
    mov rdx, [rax + ND_B]
    xor ecx, ecx
.wf_cnt:
    test rdx, rdx
    jz .wf_cnt_done
    inc ecx
    mov rdx, [rdx + ND_NEXT]
    jmp .wf_cnt
.wf_cnt_done:
    cmp ecx, 4
    je .wf_ok
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    lea rsi, [rel m_arity]
    mov edx, m_arity_len
    call diag_tok
    xor eax, eax
    jmp .done
.wf_ok:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    mov [rbp - 32], rax

    ; Push four arguments in order: path, pathlen, data, len
    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax

    ; shadow space + three stack arguments
    mov edi, 0x40
    call emit_sub_rsp
    ; mov rcx,[rsp+0x58]  path
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x58
    call cb_b
    ; mov edx,0x40000000  GENERIC_WRITE
    mov eax, 0xBA
    call cb_b
    mov eax, 0x40000000
    call cb_d
    ; xor r8d,r8d
    mov eax, 0x45
    call cb_b
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    ; xor r9d,r9d
    mov eax, 0x45
    call cb_b
    mov eax, 0x31
    call cb_b
    mov eax, 0xC9
    call cb_b
    ; [rsp+0x20]=CREATE_ALWAYS(2)
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x20
    call cb_b
    mov eax, 2
    call cb_d
    ; [rsp+0x28]=FILE_ATTRIBUTE_NORMAL(0x80)
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x28
    call cb_b
    mov eax, 0x80
    call cb_d
    ; [rsp+0x30]=0
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x30
    call cb_b
    xor eax, eax
    call cb_d
    ; call [iat+40] CreateFileA
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 40
    xor ecx, ecx
    call emit_rip

    mov edi, 0x40
    call emit_add_rsp

    ; r8=len, rdx=data, r10=handle
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x04
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x54
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x08
    call cb_b
    mov eax, 0x49
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC2
    call cb_b

    mov edi, 0x20
    call emit_add_rsp
    sub dword [rel cg_depth], 4

    ; push r10
    mov eax, 0x41
    call cb_b
    mov eax, 0x52
    call cb_b
    mov edi, 0x38
    call emit_sub_rsp
    ; lpOverlapped = 0
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x20
    call cb_b
    xor eax, eax
    call cb_d
    ; lea r9,[rsp+0x28] written
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8D
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x28
    call cb_b
    ; rcx=handle
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x38
    call cb_b
    ; call [iat+8] WriteFile
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 8
    xor ecx, ecx
    call emit_rip

    mov edi, 0x38
    call emit_add_rsp
    mov eax, 0x50                       ; push rax (generated code, save WriteFile return value)
    call cb_b
    ; rcx = [rsp+8] handle
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x08
    call cb_b
    mov edi, 0x20
    call emit_sub_rsp
    ; call [iat+48] CloseHandle
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 48
    xor ecx, ecx
    call emit_rip
    mov edi, 0x20
    call emit_add_rsp
    mov eax, 0x58                       ; pop rax (recover WriteFile return value)
    call cb_b
    mov edi, 8
    call emit_add_rsp
    jmp .done

; readfile(path:^u8, pathlen:i64, buf:^u8, maxlen:i64) -> i64
; Returns the actual number of bytes read; returns 0 on failure.
.readfile_call:
    mov rax, [rbp - 8]
    mov rdx, [rax + ND_B]
    xor ecx, ecx
.rf_cnt:
    test rdx, rdx
    jz .rf_cnt_done
    inc ecx
    mov rdx, [rdx + ND_NEXT]
    jmp .rf_cnt
.rf_cnt_done:
    cmp ecx, 4
    je .rf_ok
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    lea rsi, [rel m_arity]
    mov edx, m_arity_len
    call diag_tok
    xor eax, eax
    jmp .done
.rf_ok:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax

    mov rax, [rbp - 32]
    mov rdi, [rax + ND_A]
    call gen_expr
    call emit_push_rax

    mov edi, 0x40
    call emit_sub_rsp
    ; rcx=path
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x58
    call cb_b
    ; edx=GENERIC_READ
    mov eax, 0xBA
    call cb_b
    mov eax, 0x80000000
    call cb_d
    ; r8d=FILE_SHARE_READ
    mov eax, 0x41
    call cb_b
    mov eax, 0xB8
    call cb_b
    mov eax, 1
    call cb_d
    ; r9d=0
    mov eax, 0x45
    call cb_b
    mov eax, 0x31
    call cb_b
    mov eax, 0xC9
    call cb_b
    ; [rsp+0x20]=OPEN_EXISTING(3)
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x20
    call cb_b
    mov eax, 3
    call cb_d
    ; [rsp+0x28]=0x80
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x28
    call cb_b
    mov eax, 0x80
    call cb_d
    ; [rsp+0x30]=0
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x30
    call cb_b
    xor eax, eax
    call cb_d
    ; call CreateFileA
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 40
    xor ecx, ecx
    call emit_rip

    mov edi, 0x40
    call emit_add_rsp
    ; r8=maxlen, rdx=buf, r10=handle
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x04
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x54
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x08
    call cb_b
    mov eax, 0x49
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC2
    call cb_b

    mov edi, 0x20
    call emit_add_rsp
    sub dword [rel cg_depth], 4
    mov eax, 0x41
    call cb_b
    mov eax, 0x52
    call cb_b
    mov edi, 0x38
    call emit_sub_rsp
    ; lpOverlapped=0
    mov eax, 0xC7
    call cb_b
    mov eax, 0x44
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x20
    call cb_b
    xor eax, eax
    call cb_d
    ; lea r9,[rsp+0x28] bytes-read
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8D
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x28
    call cb_b
    ; rcx=handle
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x4C
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x38
    call cb_b
    ; call ReadFile
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 56
    xor ecx, ecx
    call emit_rip
    ; r10=bytes read
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x54
    call cb_b
    mov eax, 0x24
    call cb_b
    mov eax, 0x28
    call cb_b
    mov edi, 0x38
    call emit_add_rsp
    mov eax, 0x59                       ; pop rcx（handle）
    call cb_b
    mov eax, 0x41
    call cb_b
    mov eax, 0x52
    call cb_b
    mov edi, 0x28
    call emit_sub_rsp
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 48
    xor ecx, ecx
    call emit_rip
    mov edi, 0x28
    call emit_add_rsp
    mov eax, 0x58                       ; pop rax (byte count)
    call cb_b
    jmp .done

.print_call:
    mov rax, [rbp - 8]
    mov rdx, [rax + ND_B]
    xor ecx, ecx
.cnt:
    test rdx, rdx
    jz .cnt_done
    inc ecx
    mov rdx, [rdx + ND_NEXT]
    jmp .cnt
.cnt_done:
    cmp ecx, 1
    je .print_ok
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    lea rsi, [rel m_arity]
    mov edx, m_arity_len
    call diag_tok
.print_ok:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    test rax, rax
    jz .print_zero
    mov rdi, [rax + ND_A]
    call gen_expr
    jmp .print_arg_done
.print_zero:
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
.print_arg_done:
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC1
    call cb_b
    mov eax, [rel cg_depth]
    and eax, 1
    mov [rbp - 48], eax
    test eax, eax
    jz .print_nopad
    mov edi, 8
    call emit_sub_rsp
    inc dword [rel cg_depth]
.print_nopad:
    mov rdi, [rel g_help_off]
    call call_off
    cmp dword [rbp - 48], 0
    je .print_ret0
    mov edi, 8
    call emit_add_rsp
    dec dword [rel cg_depth]
.print_ret0:
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .done

.undef_fn:
    mov rdi, [rbp - 16]
    lea rsi, [rel m_undef_fn]
    mov edx, m_undef_fn_len
    call diag_name
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .done

.internal:
    mov rdi, [rbp - 8]
    mov esi, [rdi + ND_LINE]
    mov edx, [rdi + ND_COL]
    lea rcx, [rel m_internal]
    mov r8d, m_internal_len
    xor edi, edi
    call diag_at
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
.done:
    mov rsp, rbp
    pop rbp
    ret

emit_push_rax:
    mov eax, 0x50
    call cb_b
    inc dword [rel cg_depth]
    ret

; The following four use rbp+disp32 operands, with edx=disp
emit_st_rax_disp:
    push rdx
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0x85
    call cb_b
    pop rdx
    mov eax, edx
    call cb_d
    ret

emit_ld_rax_disp:
    push rdx
    mov eax, 0x48
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x85
    call cb_b
    pop rdx
    mov eax, edx
    call cb_d
    ret

emit_ld_r9_disp:
    push rdx
    mov eax, 0x4C
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x8D
    call cb_b
    pop rdx
    mov eax, edx
    call cb_d
    ret

emit_st_r8_disp:
    push rdx
    mov eax, 0x4C
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0x85
    call cb_b
    pop rdx
    mov eax, edx
    call cb_d
    ret

emit_pop_rax:
    mov eax, 0x58
    call cb_b
    dec dword [rel cg_depth]
    ret

emit_pop_reg:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    cmp dword [rbp - 8], 8
    jb .low
    mov eax, 0x41
    call cb_b
    mov eax, [rbp - 8]
    sub eax, 8
    add eax, 0x58
    call cb_b
    jmp .done
.low:
    mov eax, [rbp - 8]
    add eax, 0x58
    call cb_b
.done:
    dec dword [rel cg_depth]
    mov rsp, rbp
    pop rbp
    ret

; emit_push_reg(edi=reg)
emit_push_reg:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    cmp dword [rbp - 8], 8
    jb .low
    mov eax, 0x41
    call cb_b
    mov eax, [rbp - 8]
    sub eax, 8
    add eax, 0x50
    call cb_b
    jmp .done
.low:
    mov eax, [rbp - 8]
    add eax, 0x50
    call cb_b
.done:
    inc dword [rel cg_depth]
    mov rsp, rbp
    pop rbp
    ret

; emit_call_fixup(rdi=name, rsi=len, edx=line, ecx=col, r8d=srcoff)
emit_call_fixup:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov [rbp - 40], r8
    mov rax, [rel sec_len]
    inc rax
    mov [rbp - 48], rax
    mov eax, 0xE8
    call cb_b
    xor eax, eax
    call cb_d
    mov rdi, [rbp - 48]
    mov rsi, [rbp - 8]
    mov edx, [rbp - 16]
    mov ecx, [rbp - 24]
    mov r8d, [rbp - 32]
    mov r9d, [rbp - 40]
    call fx_add
    mov rsp, rbp
    pop rbp
    ret

; emit_fnaddr_fixup(rdi=name, rsi=len, edx=line, ecx=col, r8d=srcoff)
; emit lea rax,[rip+disp]; disp is backfilled by the function-address patch
emit_fnaddr_fixup:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov [rbp - 40], r8
    mov rax, [rel sec_len]
    add rax, 3
    mov [rbp - 48], rax                 ; disp field offset
    mov eax, 0x48
    call cb_b
    mov eax, 0x8D
    call cb_b
    mov eax, 0x05
    call cb_b
    xor eax, eax
    call cb_d
    mov rdi, [rbp - 48]
    mov rsi, [rbp - 8]
    mov edx, [rbp - 16]
    mov ecx, [rbp - 24]
    mov r8d, [rbp - 32]
    mov r9d, [rbp - 40]
    call fx_add
    mov rsp, rbp
    pop rbp
    ret

; store_local(edx=rbp disp, ecx=type): write rax to [rbp+disp]
store_local:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edx
    mov [rbp - 16], ecx
    mov edi, ecx
    call type_size
    cmp eax, 1
    je .one
    cmp eax, 4
    je .four
    mov eax, 0x48                       ; mov [rbp+disp],rax
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0x85
    call cb_b
    jmp .disp
.one:
    mov eax, 0x88                       ; mov [rbp+disp],al
    call cb_b
    mov eax, 0x85
    call cb_b
    jmp .disp
.four:
    mov eax, 0x89                       ; mov [rbp+disp],eax
    call cb_b
    mov eax, 0x85
    call cb_b
.disp:
    mov eax, [rbp - 8]
    call cb_d
    mov rsp, rbp
    pop rbp
    ret

; load_local(edx=disp, ecx=type) -> rax
load_local:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edx
    mov [rbp - 16], ecx
    mov edi, ecx
    call type_size
    cmp eax, 1
    je .one
    cmp eax, 4
    je .four
    mov eax, 0x48                       ; mov rax,[rbp+disp]
    call cb_b
    mov eax, 0x8B
    call cb_b
    mov eax, 0x85
    call cb_b
    jmp .disp
.one:
    mov eax, 0x0F                       ; movzx eax, byte [rbp+disp]
    call cb_b
    mov eax, 0xB6
    call cb_b
    mov eax, 0x85
    call cb_b
    jmp .disp
.four:
    mov eax, 0x8B                       ; mov eax,[rbp+disp]
    call cb_b
    mov eax, 0x85
    call cb_b
.disp:
    mov eax, [rbp - 8]
    call cb_d
    mov rsp, rbp
    pop rbp
    ret

; gen_struct_fields(edi=struct type, edx=base disp, rsi=field initializer chain)
gen_struct_fields:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], edi
    mov [rbp - 16], edx
    mov [rbp - 24], rsi
.loop:
    mov rax, [rbp - 24]
    test rax, rax
    jz .done
    mov [rbp - 32], rax
    mov edi, [rbp - 8]
    mov rsi, [rax + ND_A]
    call sf_find_tok
    test rax, rax
    jz .next
    mov edx, [rax + SF_OFF]
    add edx, [rbp - 16]
    mov [rbp - 40], edx                 ; field address disp
    mov ecx, [rax + SF_TYPE]
    mov [rbp - 44], ecx
    mov rax, [rbp - 32]
    mov rdi, [rax + ND_B]
    call gen_expr
    mov edx, [rbp - 40]
    mov ecx, [rbp - 44]
    call store_local
.next:
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 24], rax
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; gen_init_to(edi=declared type, edx=disp, rdi=initializer expression)
gen_init_to:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], edi
    mov [rbp - 16], edx
    mov [rbp - 24], rsi
    mov rax, rsi
    mov eax, [rax + ND_KIND]
    cmp eax, NK_STRUCTLIT
    je .struct
    cmp eax, NK_ARRAYLIT
    je .array
    ; scalar
    mov rdi, [rbp - 24]
    call gen_expr
    mov edx, [rbp - 16]
    mov ecx, [rbp - 8]
    call store_local
    jmp .done
.struct:
    mov eax, [rbp - 8]
    test eax, TY_STRUCT
    jz .scalar
    mov rax, [rbp - 24]
    mov edi, [rax + ND_VAL]
    mov edx, [rbp - 16]
    mov rsi, [rax + ND_B]
    call gen_struct_fields
    jmp .done
.array:
    mov eax, [rbp - 8]
    test eax, TY_ARRAY
    jz .scalar
    mov edi, eax
    call elem_type
    mov [rbp - 32], eax                 ; element type
    mov edi, eax
    call type_size
    mov [rbp - 36], eax                 ; element size
    mov rax, [rbp - 24]
    mov rax, [rax + ND_B]
    mov [rbp - 48], rax
    mov dword [rbp - 64], 0
.el_loop:
    mov rax, [rbp - 48]
    test rax, rax
    jz .done
    mov [rbp - 72], rax
    mov eax, [rbp - 64]
    mov ecx, [rbp - 36]
    imul eax, ecx
    add eax, [rbp - 16]
    mov [rbp - 80], eax                 ; element disp
    mov rax, [rbp - 72]
    mov rsi, rax
    mov edi, [rbp - 32]
    mov edx, [rbp - 80]
    call gen_init_to
    inc dword [rbp - 64]
    mov rax, [rbp - 72]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 48], rax
    jmp .el_loop
.scalar:
    mov rdi, [rbp - 24]
    call gen_expr
    mov edx, [rbp - 16]
    mov ecx, [rbp - 8]
    call store_local
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ statement generation -----------------------
; gen_stmt(rdi=node)
gen_stmt:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    mov eax, [rdi + ND_KIND]
    cmp eax, NK_LET
    je .let
    cmp eax, NK_RETURN
    je .ret
    cmp eax, NK_EXPRSTMT
    je .expr
    cmp eax, NK_BLOCK
    je .block
    cmp eax, NK_WHILE
    je .while
    cmp eax, NK_IF
    je .if
    cmp eax, NK_ASSIGN
    je .assign
    jmp .done

.let:
    ; Compute this variable's byte size and allocate frame space
    mov rax, [rbp - 8]
    mov rax, [rax + ND_C]
    mov [rbp - 48], eax                  ; declared type
    mov edi, eax
    call type_size
    test eax, eax
    jnz .let_sz_ok
    mov eax, 8
.let_sz_ok:
    mov [rbp - 52], eax
    mov ecx, [rel next_off]
    add ecx, eax
    mov [rel next_off], ecx
    neg ecx
    mov [rbp - 16], ecx                  ; this variable's disp
    mov dword [rel cg_no_fnval], 1
    mov rax, [rbp - 8]
    mov rsi, [rax + ND_B]
    mov edi, [rax + ND_C]
    mov edx, [rbp - 16]
    call gen_init_to
    mov dword [rel cg_no_fnval], 0
    ; duplicate-name check
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
    mov [rbp - 24], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 32], rax
    mov rdi, [rbp - 24]
    call tok_len
    mov [rbp - 40], rax
    mov rdi, [rbp - 32]
    mov rsi, [rbp - 40]
    call local_find
    cmp rax, -1
    je .add_local
    mov rdi, [rbp - 24]
    lea rsi, [rel m_dup_local]
    mov edx, m_dup_local_len
    call diag_name
.add_local:
    mov rdi, [rbp - 32]
    mov rsi, [rbp - 40]
    mov edx, [rbp - 16]
    mov rax, [rbp - 8]
    mov rax, [rax + ND_C]
    mov ecx, eax                         ; declared type code
    call local_add
    jmp .done

.ret:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    test rdi, rdi
    jz .ret_zero
    call gen_expr
    jmp .ret_epi
.ret_zero:
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
.ret_epi:
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xEC
    call cb_b
    mov eax, 0x5D
    call cb_b
    mov eax, 0xC3
    call cb_b
    jmp .done

.expr:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_expr
    jmp .done

.block:
    mov rax, [rbp - 8]
    mov rax, [rax + ND_A]
.block_loop:
    test rax, rax
    jz .done
    mov [rbp - 16], rax
    mov rdi, rax
    call gen_stmt
    mov rax, [rbp - 16]
    mov rax, [rax + ND_NEXT]
    jmp .block_loop

.assign:
    ; Assignment: store lvalue address in cg_scr1, old value in cg_scr2, rhs in rax
    mov rax, [rbp - 8]
    mov rax, [rax + ND_C]
    mov eax, [rax + TK_KIND]
    mov [rbp - 56], eax
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_addr
    mov edx, [rel cg_scr1]
    call emit_st_rax_disp
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call node_type
    mov edi, eax
    call type_size
    mov [rbp - 48], eax
    mov eax, [rbp - 56]
    cmp eax, TK_ASSIGN
    je .assign_rhs
    ; If the rhs is already a desugared binary expression, treat it as a normal assignment
    mov rax, [rbp - 8]
    mov rax, [rax + ND_B]
    cmp dword [rax + ND_KIND], NK_BIN
    jne .assign_compound
    mov dword [rbp - 56], TK_ASSIGN
    jmp .assign_rhs
.assign_compound:
    ; compound: load old value into rax and store it in cg_scr2
    mov edx, [rel cg_scr1]
    call emit_ld_rax_disp
    cmp dword [rbp - 48], 8
    je .old8
    cmp dword [rbp - 48], 4
    je .old4
    mov eax, 0x0F                       ; movzx eax, byte [rax]
    call cb_b
    mov eax, 0xB6
    call cb_b
    xor eax, eax
    call cb_b
    jmp .old_done
.old8:
    mov eax, 0x48                       ; mov rax,[rax]
    call cb_b
    mov eax, 0x8B
    call cb_b
    xor eax, eax
    call cb_b
    jmp .old_done
.old4:
    mov eax, 0x8B                       ; mov eax,[rax]
    call cb_b
    xor eax, eax
    call cb_b
.old_done:
    mov edx, [rel cg_scr2]
    call emit_st_rax_disp
.assign_rhs:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_expr
    mov eax, [rbp - 56]
    cmp eax, TK_ASSIGN
    je .assign_simple
    mov eax, 0x49                       ; mov r8,rax (rhs)
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov edx, [rel cg_scr2]
    call emit_ld_rax_disp               ; old value
    mov eax, 0x4C                       ; add rax,r8
    call cb_b
    mov eax, 0x01
    call cb_b
    mov eax, 0xC0
    call cb_b
    jmp .assign_value_ready
.assign_simple:
.assign_value_ready:
    mov eax, 0x49                       ; mov r8,rax
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov edx, [rel cg_scr1]
    call emit_ld_r9_disp                ; address -> r9
    cmp dword [rbp - 48], 8
    je .st8
    cmp dword [rbp - 48], 4
    je .st4
    mov eax, 0x45                       ; mov [r9], r8b
    call cb_b
    mov eax, 0x88
    call cb_b
    mov eax, 0x01
    call cb_b
    jmp .done
.st8:
    mov eax, 0x4D                       ; mov [r9], r8
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0x01
    call cb_b
    jmp .done
.st4:
    mov eax, 0x45                       ; mov [r9], r8d
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0x01
    call cb_b
    jmp .done
.while:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    mov rax, [rel sec_len]
    mov [rbp - 24], rax                 ; loop top
    call gen_expr
    ; test rax,rax
    mov eax, 0x48
    call cb_b
    mov eax, 0x85
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 0x84                      ; jz
    call emit_jcc_off
    mov [rbp - 32], rax
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_stmt
    ; jmp top
    mov eax, 0xE9
    call cb_b
    mov rax, [rel sec_len]
    mov [rbp - 40], rax
    xor eax, eax
    call cb_d
    mov rdi, [rbp - 32]
    mov rsi, [rel sec_len]
    call patch_rel32
    mov rdi, [rbp - 40]
    mov rsi, [rbp - 24]
    call patch_rel32
    jmp .done

.if:
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_A]
    call gen_expr
    mov eax, 0x48
    call cb_b
    mov eax, 0x85
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 0x84
    call emit_jcc_off
    mov [rbp - 32], rax
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_B]
    call gen_stmt
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_C]
    test rdi, rdi
    jz .if_no_else
    ; jmp end
    mov eax, 0xE9
    call cb_b
    mov rax, [rel sec_len]
    mov [rbp - 40], rax
    xor eax, eax
    call cb_d
    mov rdi, [rbp - 32]
    mov rsi, [rel sec_len]
    call patch_rel32
    mov rax, [rbp - 8]
    mov rdi, [rax + ND_C]
    call gen_stmt
    mov rdi, [rbp - 40]
    mov rsi, [rel sec_len]
    call patch_rel32
    jmp .done
.if_no_else:
    mov rdi, [rbp - 32]
    mov rsi, [rel sec_len]
    call patch_rel32
.done:
    mov rsp, rbp
    pop rbp
    ret

; count_let_bytes(rdi=first statement in chain) -> eax=total bytes of all nested lets
count_let_bytes:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov dword [rbp - 32], 0
.loop:
    test rdi, rdi
    jz .done
    mov [rbp - 24], rdi
    mov eax, [rdi + ND_KIND]
    cmp eax, NK_LET
    jne .check_block
    mov rdx, [rdi + ND_C]
    mov edi, edx
    call type_size
    test eax, eax
    jnz .let_sz
    mov eax, 8
.let_sz:
    add [rbp - 32], eax
    jmp .next
.check_block:
    cmp eax, NK_BLOCK
    je .block
    cmp eax, NK_IF
    je .if
    cmp eax, NK_WHILE
    je .while
    jmp .next
.block:
    mov rax, [rbp - 24]
    mov rdi, [rax + ND_A]
    call count_let_bytes
    add [rbp - 32], eax
    jmp .next
.if:
    mov rax, [rbp - 24]
    mov rdi, [rax + ND_B]
    call count_let_bytes
    add [rbp - 32], eax
    mov rax, [rbp - 24]
    mov rdi, [rax + ND_C]
    test rdi, rdi
    jz .next
    cmp dword [rdi + ND_KIND], NK_IF
    je .else_if_count
    call count_let_bytes
    add [rbp - 32], eax
    jmp .next
.else_if_count:
    call count_let_bytes
    add [rbp - 32], eax
    jmp .next
.while:
    mov rax, [rbp - 24]
    mov rdi, [rax + ND_B]
    call count_let_bytes
    add [rbp - 32], eax
.next:
    mov rax, [rbp - 24]
    mov rdi, [rax + ND_NEXT]
    jmp .loop
.done:
    mov eax, [rbp - 32]
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ function generation -------------------------
; gen_fn(rdi=fn record)
gen_fn:
    push rbp
    mov rbp, rsp
    sub rsp, 0x80
    mov [rbp - 8], rdi

    mov qword [rel local_head], 0
    mov dword [rel next_off], 0
    mov rax, [rbp - 8]
    mov eax, [rax + FN_ARITY]
    mov [rbp - 28], eax                  ; parameter count

    ; record code offset
    mov rax, [rel sec_len]
    mov rdx, [rbp - 8]
    mov [rdx + FN_OFF], eax

    ; Count bytes occupied by lets across all nested statements
    mov rax, [rbp - 8]
    mov rax, [rax + FN_NODE]
    mov rax, [rax + ND_C]
    mov rdi, [rax + ND_A]
    call count_let_bytes
    mov [rbp - 16], eax                  ; total let bytes

    mov eax, [rbp - 28]
    shl eax, 3
    add eax, [rbp - 16]
    mov [rbp - 32], eax                  ; total variable-area bytes
    add eax, 64                          ; shadow space + temporary slots + margin
    add eax, 15
    and eax, ~15
    cmp eax, 0x30
    jae .frame_ok
    mov eax, 0x30
.frame_ok:
    mov [rbp - 24], eax                  ; frame
    ; assignment temporary slot: immediately after locals
    mov eax, [rbp - 32]
    add eax, 8
    neg eax
    mov [rel cg_scr1], eax
    mov eax, [rbp - 32]
    add eax, 16
    neg eax
    mov [rel cg_scr2], eax

    ; prologue
    mov eax, 0x55
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xE5
    call cb_b
    mov edi, [rbp - 24]
    call emit_sub_rsp

    ; parameter stack slots
    mov rax, [rbp - 8]
    mov rax, [rax + FN_NODE]
    mov rax, [rax + ND_B]
    mov [rbp - 32], rax
    mov dword [rbp - 40], 0
.param_loop:
    mov rax, [rbp - 32]
    test rax, rax
    jz .params_done
    mov rax, [rax + ND_A]
    mov [rbp - 48], rax
    mov rdi, rax
    call tok_text
    mov [rbp - 56], rax
    mov rdi, [rbp - 48]
    call tok_len
    mov [rbp - 64], rax
    mov rdi, [rbp - 56]
    mov rsi, [rbp - 64]
    mov eax, [rel next_off]
    add eax, 8
    mov [rel next_off], eax
    neg eax
    mov [rbp - 44], eax                  ; parameter disp
    mov edx, eax
    mov rax, [rbp - 32]
    mov rax, [rax + ND_C]
    mov ecx, eax                         ; parameter declared type
    call local_add
    ; save registers
    mov eax, [rbp - 40]
    lea rdx, [rel param_regs]
    movzx esi, byte [rdx + rax]
    mov edx, [rbp - 44]
    mov edi, 0x89
    call emit_rm_disp
    inc dword [rbp - 40]
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax
    jmp .param_loop
.params_done:

    ; function body
    mov rax, [rbp - 8]
    mov rax, [rax + FN_NODE]
    mov rax, [rax + ND_C]
    mov rax, [rax + ND_A]
    mov [rbp - 32], rax
.body_loop:
    mov rax, [rbp - 32]
    test rax, rax
    jz .body_done
    mov rdi, rax
    call gen_stmt
    mov rax, [rbp - 32]
    mov rax, [rax + ND_NEXT]
    mov [rbp - 32], rax
    jmp .body_loop
.body_done:
    ; fall through: return 0
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xEC
    call cb_b
    mov eax, 0x5D
    call cb_b
    mov eax, 0xC3
    call cb_b

    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ entry --------------------------------------
emit_entry:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov rax, [rel sec_len]
    mov [rel g_entry_off], rax

    mov edi, 0x28
    call emit_sub_rsp
    ; mov ecx,-11
    mov eax, 0xB9
    call cb_b
    mov eax, 0xFFFFFFF5
    call cb_d
    ; call GetStdHandle
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    xor ecx, ecx
    call emit_rip
    ; mov [g_hstdout],rax
    mov edi, 0x89
    xor esi, esi
    mov edx, [rel g_hstdout_off]
    mov ecx, 1
    call emit_rip

    ; call main
    lea rdi, [rel s_main]
    mov esi, 4
    call fn_find
    test rax, rax
    jz .no_main
    mov edi, [rax + FN_OFF]
    call call_off
    jmp .after_call
.no_main:
    mov eax, 0xCC
    call cb_b
.after_call:
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC1
    call cb_b
    ; call ExitProcess
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 16
    xor ecx, ecx
    call emit_rip
    mov eax, 0xCC
    call cb_b

    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ backfill -----------------------------------
resolve_fixups:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov rax, [rel fix_head]
    mov [rbp - 8], rax
.loop:
    mov rax, [rbp - 8]
    test rax, rax
    jz .done
    mov rdx, [rax + FX_NAME]
    mov esi, [rax + FX_LEN]
    mov rdi, rdx
    mov [rbp - 16], rax
    call fn_find
    test rax, rax
    jz .missing
    mov edx, [rax + FN_OFF]
    mov rax, [rbp - 16]
    mov ecx, [rax + FX_OFF]
    add ecx, 4
    sub edx, ecx
    mov rdi, [rbp - 16]
    mov edi, [rdi + FX_OFF]
    mov esi, edx
    call patch32
    jmp .next
.missing:
    mov rax, [rbp - 16]
    mov rdi, [rax + FX_SRCOFF]
    mov esi, [rax + FX_LINE]
    mov edx, [rax + FX_COL]
    lea rcx, [rel m_undef_fn]
    mov r8d, m_undef_fn_len
    xor r9d, r9d
    mov r9, [rax + FX_NAME]
    mov [rel diag_name_ptr], r9
    mov r9d, [rax + FX_LEN]
    mov [rel diag_name_len], r9
    call diag_at
.next:
    mov rax, [rbp - 16]
    mov rax, [rax + FX_NEXT]
    mov [rbp - 8], rax
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ PE output ----------------------------------
put16:
    lea rax, [rel hdr_buf]
    mov [rax + rdi], si
    ret

put32:
    lea rax, [rel hdr_buf]
    mov [rax + rdi], esi
    ret

put64:
    lea rax, [rel hdr_buf]
    mov [rax + rdi], rsi
    ret

pe_build_header:
    ; rdi = raw size
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov [rbp - 8], rdi

    lea rdi, [rel hdr_buf]
    xor eax, eax
    mov ecx, HDR_SIZE / 4
    rep stosd

    ; DOS
    xor edi, edi
    mov esi, 0x5A4D
    call put16
    mov edi, 0x3C
    mov esi, 0x40
    call put32

    ; PE sig / COFF
    mov edi, 0x40
    mov esi, 0x00004550
    call put32
    mov edi, 0x44
    mov esi, 0x8664
    call put16
    mov edi, 0x46
    mov esi, 1
    call put16
    mov edi, 0x54
    mov esi, 0x00F0
    call put16
    mov edi, 0x56
    mov esi, 0x0023
    call put16

    ; optional header
    mov edi, 0x58
    mov esi, 0x020B
    call put16
    mov edi, 0x5C
    mov esi, [rbp - 8]
    call put32
    mov edi, 0x60
    xor esi, esi
    call put32
    mov edi, 0x64
    xor esi, esi
    call put32
    mov edi, 0x68
    mov eax, [rel g_entry_off]
    add eax, SEC_RVA
    mov esi, eax
    call put32
    mov edi, 0x6C
    mov esi, SEC_RVA
    call put32
    mov edi, 0x70
    mov rsi, IMAGE_BASE
    call put64
    mov edi, 0x78
    mov esi, 0x1000
    call put32
    mov edi, 0x7C
    mov esi, 0x200
    call put32
    mov edi, 0x80
    mov esi, 6
    call put16
    mov edi, 0x82
    xor esi, esi
    call put16
    mov edi, 0x84
    xor esi, esi
    call put16
    mov edi, 0x86
    xor esi, esi
    call put16
    mov edi, 0x88
    mov esi, 6
    call put16
    mov edi, 0x8A
    xor esi, esi
    call put16
    mov edi, 0x8C
    xor esi, esi
    call put32
    mov eax, [rbp - 8]
    add eax, SEC_RVA + 0xFFF
    and eax, ~0xFFF
    mov edi, 0x90
    mov esi, eax
    call put32
    mov edi, 0x94
    mov esi, HDR_SIZE
    call put32
    mov edi, 0x98
    xor esi, esi
    call put32
    mov edi, 0x9C
    mov esi, 3
    call put16
    mov edi, 0x9E
    xor esi, esi
    call put16
    mov edi, 0xA0
    mov rsi, 0x100000
    call put64
    mov edi, 0xA8
    mov rsi, 0x1000
    call put64
    mov edi, 0xB0
    mov rsi, 0x100000
    call put64
    mov edi, 0xB8
    mov rsi, 0x1000
    call put64
    mov edi, 0xC0
    xor esi, esi
    call put32
    mov edi, 0xC4
    mov esi, 16
    call put32
    mov edi, 0xD0
    mov eax, [rel g_desc_off]
    add eax, SEC_RVA
    mov esi, eax
    call put32
    mov edi, 0xD4
    mov esi, 40
    call put32

    ; section table
    lea rax, [rel hdr_buf]
    mov rcx, 0x000000747865742E      ; ".text\0\0\0"
    mov [rax + 0x148], rcx
    mov edi, 0x150
    mov esi, [rbp - 8]
    call put32
    mov edi, 0x154
    mov esi, SEC_RVA
    call put32
    mov edi, 0x158
    mov esi, [rbp - 8]
    call put32
    mov edi, 0x15C
    mov esi, 0x200
    call put32
    mov edi, 0x16C
    mov esi, 0xE0000060
    call put32

    mov rsp, rbp
    pop rbp
    ret

pe_write:
    ; rdi = lpcwstr out path -> eax 1/0
    push rbp
    mov rbp, rsp
    sub rsp, 0x80
    mov [rbp - 8], rdi

    mov rax, [rel sec_len]
    add rax, 0x1FF
    and rax, ~0x1FF
    mov [rbp - 16], rax                  ; raw
    mov rdi, rax
    call pe_build_header

    mov rax, [rbp - 16]
    add rax, HDR_SIZE
    mov [rbp - 24], rax                  ; total

    xor ecx, ecx
    mov rdx, rax
    add rdx, 0x200
    mov r8d, MEM_COMMIT_RESERVE
    mov r9d, PAGE_READWRITE
    call [rel __imp_VirtualAlloc]
    test rax, rax
    jz .fail
    mov [rbp - 32], rax

    ; header
    lea rsi, [rel hdr_buf]
    mov rdi, rax
    mov ecx, HDR_SIZE
    rep movsb
    ; section contents
    mov rdi, [rbp - 32]
    add rdi, HDR_SIZE
    mov rsi, [rel sec_buf]
    mov rcx, [rel sec_len]
    rep movsb
    ; zero padding
    mov rcx, [rbp - 16]
    sub rcx, [rel sec_len]
    xor eax, eax
    rep stosb

    mov rdi, [rbp - 8]
    mov rsi, [rbp - 32]
    mov rdx, [rbp - 24]
    call file_write
    mov rsp, rbp
    pop rbp
    ret
.fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ main entry --------------------------------
cg_run:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    call cb_begin

    mov rdi, [rbp - 8]
    call collect_functions

    ; main is required
    lea rdi, [rel s_main]
    mov esi, 4
    call fn_find
    test rax, rax
    jnz .has_main
    xor edi, edi
    mov esi, 1
    mov edx, 1
    lea rcx, [rel m_main_missing]
    mov r8d, m_main_missing_len
    call diag_at
.has_main:

    call emit_data
    call emit_helper

    mov rax, [rel fn_head]
    mov [rbp - 16], rax
.fn_loop:
    mov rax, [rbp - 16]
    test rax, rax
    jz .fns_done
    mov rdi, rax
    call gen_fn
    mov rax, [rbp - 16]
    mov rax, [rax + FN_NEXT]
    mov [rbp - 16], rax
    jmp .fn_loop
.fns_done:
    call emit_entry
    call resolve_fixups

    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ constants ----------------------------------
str_kernel32:   db "KERNEL32.dll", 0
str_getstd:     db "GetStdHandle", 0
str_writefile:  db "WriteFile", 0
str_exitproc:   db "ExitProcess", 0
str_valloc:     db "VirtualAlloc", 0
str_vfree:      db "VirtualFree", 0
str_createfilea: db "CreateFileA", 0
str_closehandle: db "CloseHandle", 0
str_readfile:    db "ReadFile", 0
s_print:        db "print", 0
s_writefile:    db "writefile", 0
s_readfile:     db "readfile", 0
s_main:         db "main", 0
param_regs:     db 1, 2, 8, 9







