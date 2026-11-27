; ===========================================================================
; 诊断输出（stdout，UTF-8；控制台代码页由 main 设为 65001）
; 所有人类可读文本均为 UTF-8，行号列号 1 基，Snippet 按 4 列 Tab 展开。
; ===========================================================================

; ------------------------------ 基础输出 ----------------------------------
; out_write(rdi=ptr, rsi=len)
out_write:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    test rsi, rsi
    jz .done
    mov rcx, [rel h_stdout]
    mov rdx, rdi
    mov r8, rsi
    lea r9, [rel io_written]
    mov qword [rsp + 0x20], 0
    call [rel __imp_WriteFile]
.done:
    mov rsp, rbp
    pop rbp
    ret

; out_ch(rdi=char)
out_ch:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rsp], dil
    lea rdi, [rsp]
    mov esi, 1
    call out_write
    mov rsp, rbp
    pop rbp
    ret

; out_cstr(rdi=zstr)
out_cstr:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov rsi, rdi
    xor ecx, ecx
.loop:
    cmp byte [rsi + rcx], 0
    je .done
    inc rcx
    jmp .loop
.done:
    mov rdi, rsi
    mov rsi, rcx
    call out_write
    mov rsp, rbp
    pop rbp
    ret

; out_spaces(rdi=count)
out_spaces:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
.loop:
    mov rdi, [rbp - 8]
    test rdi, rdi
    jz .done
    mov rsi, rdi
    cmp rsi, 80
    jbe .chunk_ok
    mov esi, 80
.chunk_ok:
    mov [rbp - 16], rsi
    lea rdi, [rel spaces80]
    call out_write
    mov rsi, [rbp - 16]
    sub [rbp - 8], rsi
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; out_u32(rdi=value)
out_u32:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov rax, rdi
    lea rsi, [rel numbuf + 32]
    mov r10, 10
.loop:
    xor edx, edx
    div r10
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .loop
    lea rdx, [rel numbuf + 32]
    sub rdx, rsi
    mov rdi, rsi
    mov rsi, rdx
    call out_write
    mov rsp, rbp
    pop rbp
    ret

; out_i64(rdi=value)
out_i64:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    test rdi, rdi
    jns .pos
    mov [rsp + 0x28], rdi
    mov edi, '-'
    call out_ch
    mov rdi, [rsp + 0x28]
    neg rdi
.pos:
    call out_u32
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 行定位 ------------------------------------
find_line_start:
    ; rdi=offset -> rax=行首字节偏移
    mov rax, rdi
    mov r8, [rel src_ptr]
.loop:
    test rax, rax
    jz .done
    cmp byte [r8 + rax - 1], 10
    je .done
    dec rax
    jmp .loop
.done:
    ret

find_line_end:
    ; rdi=offset -> rax=行尾字节偏移（不含）
    mov rax, rdi
    mov r8, [rel src_ptr]
    mov r9, [rel src_len]
.loop:
    cmp rax, r9
    jae .done
    mov dl, [r8 + rax]
    cmp dl, 10
    je .done
    cmp dl, 13
    je .done
    inc rax
    jmp .loop
.done:
    ret

caret_width:
    ; rdi=line_start, rsi=err_offset -> rax=显示宽度（Tab 4 列，UTF-8 续字节 0 宽）
    xor eax, eax
    mov r8, [rel src_ptr]
.loop:
    cmp rdi, rsi
    jae .done
    movzx edx, byte [r8 + rdi]
    cmp edx, 9
    jne .not_tab
    mov ecx, eax
    shr ecx, 2
    inc ecx
    shl ecx, 2
    mov eax, ecx
    jmp .next
.not_tab:
    cmp edx, 0x80
    jb .w1
    mov ecx, edx
    and ecx, 0xC0
    cmp ecx, 0x80
    je .next
.w1:
    inc eax
.next:
    inc rdi
    jmp .loop
.done:
    ret

print_snippet:
    ; rdi=line_start, rsi=line_end, edx=caret_width, ecx=line_no
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], edx
    mov [rbp - 32], ecx

    ; 行号右对齐宽度 4
    mov eax, ecx
    xor r8d, r8d
    cmp eax, 10
    jae .p2
    mov r8d, 3
    jmp .pad_done
.p2:
    cmp eax, 100
    jae .p1
    mov r8d, 2
    jmp .pad_done
.p1:
    cmp eax, 1000
    jae .p0
    mov r8d, 1
.p0:
.pad_done:
    mov rdi, r8
    call out_spaces
    mov edi, [rbp - 32]
    call out_u32
    lea rdi, [rel s_bar]
    call out_cstr

    ; 打印源码行（Tab 展开，UTF-8 续字节原样输出，超 160 列截断）
    mov r9, [rel src_ptr]
    mov rdi, [rbp - 8]
    mov rsi, [rbp - 16]
    xor r10d, r10d
.loop:
    cmp rdi, rsi
    jae .line_done
    cmp r10d, 160
    jae .trunc
    movzx eax, byte [r9 + rdi]
    mov [rbp - 40], eax
    cmp eax, 9
    jne .not_tab
    mov ecx, r10d
    shr ecx, 2
    inc ecx
    shl ecx, 2
    sub ecx, r10d
    mov [rbp - 44], ecx
    push rdi
    push rsi
    push r9
    push r10
    mov edi, ecx
    call out_spaces
    pop r10
    pop r9
    pop rsi
    pop rdi
    mov ecx, [rbp - 44]
    add r10d, ecx
    jmp .next
.not_tab:
    push rdi
    push rsi
    push r9
    push r10
    mov edi, [rbp - 40]
    call out_ch
    pop r10
    pop r9
    pop rsi
    pop rdi
    mov eax, [rbp - 40]
    cmp eax, 0x80
    jb .w1
    mov ecx, eax
    and ecx, 0xC0
    cmp ecx, 0x80
    je .next
.w1:
    inc r10d
.next:
    inc rdi
    jmp .loop
.trunc:
    lea rdi, [rel s_ellipsis]
    call out_cstr
.line_done:
    mov edi, 10
    call out_ch

    ; caret 行
    mov edi, 7
    call out_spaces
    mov edi, '|'
    call out_ch
    mov edi, ' '
    call out_ch
    mov edi, [rbp - 24]
    cmp edi, 160
    jbe .caret_ok
    mov edi, 160
.caret_ok:
    call out_spaces
    mov edi, '^'
    call out_ch
    mov edi, 10
    call out_ch

    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 诊断主入口 --------------------------------
; diag_at(rdi=byte_offset, rsi=line, rdx=col, rcx=msg, r8=msglen)
; 若 diag_name_ptr 非 0，则在消息后追加 'name'
diag_at:
    push rbp
    mov rbp, rsp
    sub rsp, 0x80
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], rdx
    mov [rbp - 32], rcx
    mov [rbp - 40], r8

    inc dword [rel err_count]
    cmp dword [rel err_count], DIAG_MAX
    jbe .ok
    lea rdi, [rel m_toomany_err]
    mov esi, m_toomany_err_len
    mov edx, 1
    call fatal
.ok:
    mov rdi, [rel path8_ptr]
    mov rsi, [rel path8_len]
    call out_write
    mov edi, ':'
    call out_ch
    mov rdi, [rbp - 16]
    call out_u32
    mov edi, ':'
    call out_ch
    mov rdi, [rbp - 24]
    call out_u32
    lea rdi, [rel s_err_prefix]
    call out_cstr
    mov rdi, [rbp - 32]
    mov rsi, [rbp - 40]
    call out_write

    cmp qword [rel diag_name_ptr], 0
    je .no_name
    mov edi, ' '
    call out_ch
    mov edi, 0x27
    call out_ch
    mov rdi, [rel diag_name_ptr]
    mov rsi, [rel diag_name_len]
    call out_write
    mov edi, 0x27
    call out_ch
.no_name:
    mov edi, 10
    call out_ch

    ; 源码片段
    mov rdi, [rbp - 8]
    call find_line_start
    mov [rbp - 48], rax
    mov rdi, [rbp - 8]
    call find_line_end
    mov [rbp - 56], rax
    mov rdi, [rbp - 48]
    mov rsi, [rbp - 8]
    call caret_width
    mov [rbp - 64], rax
    mov rdi, [rbp - 48]
    mov rsi, [rbp - 56]
    mov edx, [rbp - 64]
    mov ecx, [rbp - 16]
    call print_snippet

    mov qword [rel diag_name_ptr], 0
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 终止 --------------------------------------
; fatal(rdi=msg, rsi=len, rdx=exit_code)
fatal:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdx
    mov [rbp - 16], rdi
    mov [rbp - 24], rsi
    lea rdi, [rel s_flint_prefix]
    call out_cstr
    mov rdi, [rbp - 16]
    mov rsi, [rbp - 24]
    call out_write
    mov edi, 10
    call out_ch
    mov rdi, [rbp - 8]
    call exit_now

; fatal_win(rdi=msg, rsi=len, rdx=exit_code)：附带 GetLastError
fatal_win:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40
    mov [rbp - 8], rdx
    mov [rbp - 16], rdi
    mov [rbp - 24], rsi
    call [rel __imp_GetLastError]
    mov [rbp - 32], eax
    lea rdi, [rel s_flint_prefix]
    call out_cstr
    mov rdi, [rbp - 16]
    mov rsi, [rbp - 24]
    call out_write
    lea rdi, [rel s_win32_prefix]
    call out_cstr
    mov rdi, [rbp - 32]
    call out_u32
    mov edi, ')'
    call out_ch
    mov edi, 10
    call out_ch
    mov rdi, [rbp - 8]
    call exit_now

; exit_now(rdi=code)：恢复控制台代码页并退出
exit_now:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    mov [rbp - 8], rdi
    mov eax, [rel old_cp]
    test eax, eax
    jz .skip
    mov ecx, eax
    call [rel __imp_SetConsoleOutputCP]
.skip:
    mov ecx, [rbp - 8]
    call [rel __imp_ExitProcess]
    mov rsp, rbp
    pop rbp
    ret
