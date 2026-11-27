; ===========================================================================
; 代码生成 + 内部 PE32+ 写出（阶段 0）
; 约定：FlintCall(临时) = 参数 rcx,rdx,r8,r9；返回 rax；调用者负责 16 字节栈对齐
; 生成代码内的表达式采用栈机：左值 push，右值 -> rcx，再弹回 rax。
; ===========================================================================

; ------------------------------ 节缓冲 ------------------------------------
cb_begin:
    mov edi, SEC_BYTES
    call arena_alloc
    mov [rel sec_buf], rax
    mov qword [rel sec_len], 0
    mov dword [rel cg_depth], 0
    ret

; cb_b(al)
cb_b:
    mov rdi, [rel sec_buf]
    mov rcx, [rel sec_len]
    mov [rdi + rcx], al
    inc rcx
    mov [rel sec_len], rcx
    ret

; cb_w(ax)
cb_w:
    mov rdi, [rel sec_buf]
    mov rcx, [rel sec_len]
    mov [rdi + rcx], ax
    add rcx, 2
    mov [rel sec_len], rcx
    ret

; cb_d(eax)
cb_d:
    mov rdi, [rel sec_buf]
    mov rcx, [rel sec_len]
    mov [rdi + rcx], eax
    add rcx, 4
    mov [rel sec_len], rcx
    ret

; cb_q(rax)
cb_q:
    mov rdi, [rel sec_buf]
    mov rcx, [rel sec_len]
    mov [rdi + rcx], rax
    add rcx, 8
    mov [rel sec_len], rcx
    ret

; cb_mem(rdi=ptr, rsi=len)
cb_mem:
    mov rdx, [rel sec_buf]
    mov rcx, [rel sec_len]
    add rdx, rcx
    mov r8, rdi
    mov r9, rsi
.loop:
    test r9, r9
    jz .done
    mov al, [r8]
    mov [rdx], al
    inc r8
    inc rdx
    dec r9
    jmp .loop
.done:
    add [rel sec_len], rsi
    ret

; cb_pad(rdi=bytes)
cb_pad:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
.loop:
    cmp qword [rbp - 8], 0
    jz .done
    xor eax, eax
    call cb_b
    dec qword [rbp - 8]
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; patch32(rdi=off, esi=value)
patch32:
    mov rax, [rel sec_buf]
    mov [rax + rdi], esi
    ret

; emit_rm_disp(edi=opcode, esi=reg, edx=disp) —— REX.W + modrm，base 固定 rbp
emit_rm_disp:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov [rbp - 16], esi
    mov [rbp - 24], edx
    mov eax, esi
    shr eax, 3
    and eax, 1
    shl eax, 2
    or eax, 0x48
    call cb_b
    mov eax, [rbp - 8]
    call cb_b
    mov eax, [rbp - 24]
    cmp eax, -128
    jl .d32
    cmp eax, 127
    jg .d32
    mov eax, [rbp - 16]
    and eax, 7
    shl eax, 3
    or eax, 0x45
    call cb_b
    mov eax, [rbp - 24]
    call cb_b
    jmp .done
.d32:
    mov eax, [rbp - 16]
    and eax, 7
    shl eax, 3
    or eax, 0x85
    call cb_b
    mov eax, [rbp - 24]
    call cb_d
.done:
    mov rsp, rbp
    pop rbp
    ret

; emit_rip(edi=opcode, esi=reg, edx=target_off, ecx=rexw)
emit_rip:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], edi
    mov [rbp - 16], esi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov eax, 6
    cmp dword [rbp - 32], 0
    je .len
    mov eax, 7
.len:
    mov rdx, [rel sec_len]
    add rdx, rax
    mov rax, [rbp - 24]
    sub rax, rdx
    mov [rbp - 40], rax
    cmp dword [rbp - 32], 0
    je .no_rex
    mov eax, [rbp - 16]
    shr eax, 3
    and eax, 1
    shl eax, 2
    or eax, 0x48
    call cb_b
.no_rex:
    mov eax, [rbp - 8]
    call cb_b
    mov eax, [rbp - 16]
    and eax, 7
    shl eax, 3
    or eax, 0x05
    call cb_b
    mov eax, [rbp - 40]
    call cb_d
    mov rsp, rbp
    pop rbp
    ret

; emit_imm64(rdi=imm) —— movabs rax, imm64
emit_imm64:
    push rdi
    mov eax, 0x48
    call cb_b
    mov eax, 0xB8
    call cb_b
    pop rax
    call cb_q
    ret

; emit_sub_rsp(edi=imm)
emit_sub_rsp:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov eax, 0x48
    call cb_b
    mov eax, [rbp - 8]
    cmp eax, 127
    ja .big
    mov eax, 0x83
    call cb_b
    mov eax, 0xEC
    call cb_b
    mov eax, [rbp - 8]
    call cb_b
    jmp .done
.big:
    mov eax, 0x81
    call cb_b
    mov eax, 0xEC
    call cb_b
    mov eax, [rbp - 8]
    call cb_d
.done:
    mov rsp, rbp
    pop rbp
    ret

; emit_add_rsp(edi=imm)
emit_add_rsp:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov eax, 0x48
    call cb_b
    mov eax, [rbp - 8]
    cmp eax, 127
    ja .big
    mov eax, 0x83
    call cb_b
    mov eax, 0xC4
    call cb_b
    mov eax, [rbp - 8]
    call cb_b
    jmp .done
.big:
    mov eax, 0x81
    call cb_b
    mov eax, 0xC4
    call cb_b
    mov eax, [rbp - 8]
    call cb_d
.done:
    mov rsp, rbp
    pop rbp
    ret

; call_off(edi=target_off)
call_off:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov rax, [rel sec_len]
    add rax, 5
    mov rdx, [rbp - 8]
    sub rdx, rax
    mov [rbp - 16], edx
    mov eax, 0xE8
    call cb_b
    mov eax, [rbp - 16]
    call cb_d
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 回填表 ------------------------------------
; fx_add(rdi=disp_off, rsi=name, edx=len, ecx=line, r8d=col, r9d=srcoff)
fx_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov [rbp - 40], r8
    mov [rbp - 48], r9
    mov edi, FX_SIZE
    call arena_alloc
    mov ecx, [rbp - 8]
    mov [rax + FX_OFF], ecx
    mov rdx, [rbp - 16]
    mov [rax + FX_NAME], rdx
    mov ecx, [rbp - 24]
    mov [rax + FX_LEN], ecx
    mov ecx, [rbp - 32]
    mov [rax + FX_LINE], ecx
    mov ecx, [rbp - 40]
    mov [rax + FX_COL], ecx
    mov ecx, [rbp - 48]
    mov [rax + FX_SRCOFF], ecx
    mov rdx, [rel fix_head]
    mov [rax + FX_NEXT], rdx
    mov [rel fix_head], rax
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 函数表 ------------------------------------
fn_find:
    ; rdi=name ptr, rsi=len -> rax=record/0
    mov rdx, [rel fn_head]
.loop:
    test rdx, rdx
    jz .no
    mov eax, [rdx + FN_LEN]
    cmp eax, esi
    jne .next
    mov r8, [rdx + FN_NAME]
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
    mov rdx, [rdx + FN_NEXT]
    jmp .loop
.no:
    xor eax, eax
    ret

; fn_find_tok(rdi=token*) -> rax
fn_find_tok:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
    call tok_text
    mov rdi, rax
    mov rax, [rbp - 8]
    mov esi, [rax + TK_END]
    sub esi, [rax + TK_START]
    call fn_find
    mov rsp, rbp
    pop rbp
    ret

; fn_add(rdi=name, rsi=len, rdx=node, ecx=arity) -> rax
fn_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], rdx
    mov [rbp - 32], ecx
    mov edi, FN_SIZE
    call arena_alloc
    mov rdx, [rbp - 8]
    mov [rax + FN_NAME], rdx
    mov ecx, [rbp - 16]
    mov [rax + FN_LEN], ecx
    mov ecx, [rbp - 32]
    mov [rax + FN_ARITY], ecx
    mov dword [rax + FN_OFF], 0
    mov rdx, [rbp - 24]
    mov [rax + FN_NODE], rdx
    mov dword [rax + FN_FLAGS], 0
    mov rdx, [rel fn_head]
    mov [rax + FN_NEXT], rdx
    mov [rel fn_head], rax
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 局部变量 ----------------------------------
local_find:
    ; rdi=ptr, rsi=len -> rax=slot / -1
    mov rdx, [rel local_head]
.loop:
    test rdx, rdx
    jz .no
    mov eax, [rdx + LV_LEN]
    cmp eax, esi
    jne .next
    mov r8, [rdx + LV_NAME]
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
    mov eax, [rdx + LV_SLOT]
    ret
.next:
    mov rdx, [rdx + LV_NEXT]
    jmp .loop
.no:
    mov rax, -1
    ret

; local_add(rdi=ptr, rsi=len, edx=slot, ecx=type)
local_add:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx
    mov edi, LV_SIZE
    call arena_alloc
    mov rdx, [rbp - 8]
    mov [rax + LV_NAME], rdx
    mov ecx, [rbp - 16]
    mov [rax + LV_LEN], ecx
    mov ecx, [rbp - 24]
    mov [rax + LV_SLOT], ecx
    mov ecx, [rbp - 32]
    mov [rax + LV_TYPE], ecx
    mov rdx, [rel local_head]
    mov [rax + LV_NEXT], rdx
    mov [rel local_head], rax
    mov rsp, rbp
    pop rbp
    ret

; local_type(rdi=ptr, rsi=len) -> eax=类型码 / -1
local_type:
    mov rdx, [rel local_head]
.loop:
    test rdx, rdx
    jz .no
    mov eax, [rdx + LV_LEN]
    cmp eax, esi
    jne .next
    mov r8, [rdx + LV_NAME]
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
    mov eax, [rdx + LV_TYPE]
    ret
.next:
    mov rdx, [rdx + LV_NEXT]
    jmp .loop
.no:
    mov eax, -1
    ret

; ------------------------------ 名字工具 ----------------------------------
tok_text:
    mov rax, [rel src_ptr]
    mov ecx, [rdi + TK_START]
    add rax, rcx
    ret

tok_len:
    mov eax, [rdi + TK_END]
    mov ecx, [rdi + TK_START]
    sub eax, ecx
    ret

; name_eq_cstr(rdi=ptr, rsi=len, rdx=cstr) -> al
name_eq_cstr:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    xor ecx, ecx
.slen:
    cmp byte [rdx + rcx], 0
    je .slen_done
    inc rcx
    jmp .slen
.slen_done:
    cmp rcx, rsi
    jne .no
    xor eax, eax
.cmp:
    cmp rax, rcx
    jae .yes
    mov r8b, [rdi + rax]
    cmp r8b, [rdx + rax]
    jne .no
    inc rax
    jmp .cmp
.yes:
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret
.no:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; tok_is(rdi=token*, rsi=cstr) -> al
tok_is:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    call tok_text
    mov rdi, rax
    mov rax, [rbp - 8]
    mov esi, [rax + TK_END]
    sub esi, [rax + TK_START]
    mov rdx, [rbp - 16]
    call name_eq_cstr
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; 数据段：KERNEL32 导入表 + 全局槽 + 常量
; ---------------------------------------------------------------------------
emit_data:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40

    ; DLL 名
    mov rax, [rel sec_len]
    mov [rel g_dll_off], rax
    lea rdi, [rel str_kernel32]
    mov esi, 13
    call cb_mem

    ; Hint/Name
    mov rax, [rel sec_len]
    mov [rel g_hint_gs], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_getstd]
    mov esi, 13
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_wf], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_writefile]
    mov esi, 10
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_ep], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_exitproc]
    mov esi, 12
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_va], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_valloc]
    mov esi, 12
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_vf], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_vfree]
    mov esi, 11
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_cf], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_createfilea]
    mov esi, 11
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_ch], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_closehandle]
    mov esi, 11
    call cb_mem

    mov rax, [rel sec_len]
    mov [rel g_hint_rf], rax
    xor eax, eax
    call cb_w
    lea rdi, [rel str_readfile]
    mov esi, 8
    call cb_mem

    ; IAT
    mov rax, [rel sec_len]
    add rax, 7
    and rax, ~7
    mov [rel g_iat_off], rax
    call cg_pad_to_8

    mov rax, [rel g_hint_gs]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_wf]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_ep]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_va]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_vf]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_cf]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_ch]
    add rax, SEC_RVA
    call cb_q
    mov rax, [rel g_hint_rf]
    add rax, SEC_RVA
    call cb_q
    xor eax, eax
    call cb_q

    ; 导入描述符（1 个 + 终止符）
    mov rax, [rel sec_len]
    mov [rel g_desc_off], rax
    xor eax, eax
    call cb_d
    call cb_d
    call cb_d
    mov rax, [rel g_dll_off]
    add rax, SEC_RVA
    call cb_d
    mov rax, [rel g_iat_off]
    add rax, SEC_RVA
    call cb_d
    xor eax, eax
    call cb_d
    call cb_d
    call cb_d
    call cb_d
    call cb_d

    ; 全局槽
    mov rax, [rel sec_len]
    add rax, 7
    and rax, ~7
    call cg_pad_to_8
    mov rax, [rel sec_len]
    mov [rel g_hstdout_off], rax
    xor eax, eax
    call cb_q

    mov rax, [rel sec_len]
    mov [rel g_nl_off], rax
    mov eax, 10
    call cb_b

    ; 代码段 16 字节对齐
    mov rax, [rel sec_len]
    add rax, 15
    and rax, ~15
    mov [rel sec_len], rax

    mov rsp, rbp
    pop rbp
    ret

; 把 sec_len 抬到 8 字节对齐（写零）
cg_pad_to_8:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov rax, [rel sec_buf]
    mov rcx, [rel sec_len]
.pad:
    test rcx, 7
    jz .done
    mov byte [rax + rcx], 0
    inc rcx
    jmp .pad
.done:
    mov [rel sec_len], rcx
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; 输出程序的 print 桩（十进制 + 换行），仅用易失寄存器
; ---------------------------------------------------------------------------
emit_helper:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov rax, [rel sec_len]
    mov [rel g_help_off], rax

    mov eax, 0x55
    call cb_b
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xE5
    call cb_b
    mov edi, 0x70
    call emit_sub_rsp
    ; mov qword [rsp+0x20], 0
    mov eax, 0x48
    call cb_b
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
    ; mov rax, rcx
    mov eax, 0x48
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xC8
    call cb_b
    ; lea r11,[rbp-1]
    mov edi, 0x8D
    mov esi, 11
    mov edx, -1
    call emit_rm_disp
    ; xor r10d,r10d
    mov eax, 0x45
    call cb_b
    mov eax, 0x31
    call cb_b
    mov eax, 0xD2
    call cb_b
    ; xor r8d,r8d
    mov eax, 0x45
    call cb_b
    mov eax, 0x31
    call cb_b
    mov eax, 0xC0
    call cb_b
    ; test rax,rax
    mov eax, 0x48
    call cb_b
    mov eax, 0x85
    call cb_b
    mov eax, 0xC0
    call cb_b
    ; jns .pos
    mov al, 0x89
    call emit_jcc_off
    mov [rbp - 8], rax
    ; neg rax
    mov eax, 0x48
    call cb_b
    mov eax, 0xF7
    call cb_b
    mov eax, 0xD8
    call cb_b
    ; mov r8d,1
    mov eax, 0x41
    call cb_b
    mov eax, 0xB8
    call cb_b
    mov eax, 1
    call cb_d
.pos:
    mov rax, [rbp - 8]
    mov rdi, rax
    mov rax, [rel sec_len]
    mov rsi, rax
    call patch_rel32
    ; mov ecx,10
    mov eax, 0xB9
    call cb_b
    mov eax, 10
    call cb_d
.loop:
    mov rax, [rel sec_len]
    mov [rbp - 16], rax
    ; xor edx,edx
    mov eax, 0x31
    call cb_b
    mov eax, 0xD2
    call cb_b
    ; div rcx
    mov eax, 0x48
    call cb_b
    mov eax, 0xF7
    call cb_b
    mov eax, 0xF1
    call cb_b
    ; add dl,0x30
    mov eax, 0x80
    call cb_b
    mov eax, 0xC2
    call cb_b
    mov eax, 0x30
    call cb_b
    ; mov [r11],dl
    mov eax, 0x41
    call cb_b
    mov eax, 0x88
    call cb_b
    mov eax, 0x13
    call cb_b
    ; dec r11
    mov eax, 0x49
    call cb_b
    mov eax, 0xFF
    call cb_b
    mov eax, 0xCB
    call cb_b
    ; add r10d,1
    mov eax, 0x41
    call cb_b
    mov eax, 0x83
    call cb_b
    mov eax, 0xC2
    call cb_b
    mov eax, 1
    call cb_b
    ; test rax,rax
    mov eax, 0x48
    call cb_b
    mov eax, 0x85
    call cb_b
    mov eax, 0xC0
    call cb_b
    ; jnz .loop
    mov al, 0x85
    call emit_jcc_off
    mov [rbp - 24], rax
    ; test r8d,r8d
    mov eax, 0x45
    call cb_b
    mov eax, 0x85
    call cb_b
    mov eax, 0xC0
    call cb_b
    ; jz .sdone
    mov al, 0x84
    call emit_jcc_off
    mov [rbp - 32], rax
    ; mov byte [r11],'-'
    mov eax, 0x41
    call cb_b
    mov eax, 0xC6
    call cb_b
    mov eax, 0x03
    call cb_b
    mov eax, 0x2D
    call cb_b
    ; dec r11
    mov eax, 0x49
    call cb_b
    mov eax, 0xFF
    call cb_b
    mov eax, 0xCB
    call cb_b
    ; add r10d,1
    mov eax, 0x41
    call cb_b
    mov eax, 0x83
    call cb_b
    mov eax, 0xC2
    call cb_b
    mov eax, 1
    call cb_b
.sdone:
    mov rax, [rbp - 24]
    mov rdi, rax
    mov rax, [rbp - 16]
    mov rsi, rax
    call patch_rel32
    mov rax, [rbp - 32]
    mov rdi, rax
    mov rax, [rel sec_len]
    mov rsi, rax
    call patch_rel32

    ; lea rdx,[r11+1]
    mov edi, 0x8D
    mov esi, 2
    mov edx, 1
    call emit_rm_disp_r11
    ; mov r8d,r10d
    mov eax, 0x45
    call cb_b
    mov eax, 0x89
    call cb_b
    mov eax, 0xD0
    call cb_b
    ; mov rcx,[g_hstdout]
    mov edi, 0x8B
    mov esi, 1
    mov edx, [rel g_hstdout_off]
    mov ecx, 1
    call emit_rip
    ; lea r9,[rbp-0x38]
    mov edi, 0x8D
    mov esi, 9
    mov edx, -0x38
    call emit_rm_disp
    ; call [iat_WriteFile]
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 8
    xor ecx, ecx
    call emit_rip
    ; lea rdx,[g_nl]
    mov edi, 0x8D
    mov esi, 2
    mov edx, [rel g_nl_off]
    mov ecx, 1
    call emit_rip
    ; mov r8d,1
    mov eax, 0x41
    call cb_b
    mov eax, 0xB8
    call cb_b
    mov eax, 1
    call cb_d
    ; mov rcx,[g_hstdout]
    mov edi, 0x8B
    mov esi, 1
    mov edx, [rel g_hstdout_off]
    mov ecx, 1
    call emit_rip
    ; lea r9,[rbp-0x38]
    mov edi, 0x8D
    mov esi, 9
    mov edx, -0x38
    call emit_rm_disp
    ; call [iat_WriteFile]
    mov edi, 0xFF
    mov esi, 2
    mov edx, [rel g_iat_off]
    add edx, 8
    xor ecx, ecx
    call emit_rip
    ; mov rsp,rbp
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

; emit_jcc_off(eax=condition low byte e.g. 0x89) -> rax=disp32 offset
emit_jcc_off:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], eax
    mov eax, 0x0F
    call cb_b
    mov eax, [rbp - 8]
    call cb_b
    mov rax, [rel sec_len]
    mov [rbp - 16], rax
    xor eax, eax
    call cb_d
    mov rax, [rbp - 16]
    mov rsp, rbp
    pop rbp
    ret

; patch_rel32(rdi=disp_off, rsi=target)
patch_rel32:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov rax, rdi
    add rax, 4
    mov rdx, rsi
    sub rdx, rax
    mov [rbp - 8], edx
    mov rax, [rel sec_buf]
    mov [rax + rdi], edx
    mov rsp, rbp
    pop rbp
    ret

; emit_rm_disp_r11: lea reg,[r11+disp]
emit_rm_disp_r11:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], edi
    mov [rbp - 16], esi
    mov [rbp - 24], edx
    ; REX = 0x48 | R<<2 | B(1)
    mov eax, esi
    shr eax, 3
    and eax, 1
    shl eax, 2
    or eax, 0x49
    call cb_b
    mov eax, [rbp - 8]
    call cb_b
    mov eax, [rbp - 16]
    and eax, 7
    shl eax, 3
    or eax, 0x43
    call cb_b
    mov eax, [rbp - 24]
    call cb_b
    mov rsp, rbp
    pop rbp
    ret



