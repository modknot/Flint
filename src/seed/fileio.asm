; ===========================================================================
; File I/O (kernel32 only; paths are UTF-16, taken directly from the command line)
; ===========================================================================

; file_read(rdi=lpcwstr path) -> rax=buf, rdx=len (fatal on failure)
file_read:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi

    xor ecx, ecx
    mov edx, SRC_MAX
    mov r8d, MEM_COMMIT_RESERVE
    mov r9d, PAGE_READWRITE
    call [rel __imp_VirtualAlloc]
    test rax, rax
    jz .oom
    mov [rbp - 16], rax

    mov rcx, [rbp - 8]
    mov edx, GENERIC_READ
    mov r8d, 1
    xor r9d, r9d
    mov qword [rsp + 0x20], OPEN_EXISTING
    mov qword [rsp + 0x28], 0
    mov qword [rsp + 0x30], 0
    call [rel __imp_CreateFileW]
    cmp rax, -1
    je .open_fail
    mov [rbp - 24], rax

    mov rcx, rax
    mov rdx, [rbp - 16]
    mov r8d, SRC_MAX
    lea r9, [rbp - 32]
    mov qword [rsp + 0x20], 0
    call [rel __imp_ReadFile]
    test eax, eax
    jz .read_fail

    mov rax, [rbp - 32]
    mov [rbp - 48], rax
    cmp rax, SRC_MAX
    jb .done_read

    ; Read exactly up to the limit: read 1 more byte to detect overflow
    mov rcx, [rbp - 24]
    lea rdx, [rel zero_buf]
    mov r8d, 1
    lea r9, [rbp - 32]
    mov qword [rsp + 0x20], 0
    call [rel __imp_ReadFile]
    test eax, eax
    jz .read_fail
    cmp dword [rbp - 32], 0
    jne .too_large

.done_read:
    mov rcx, [rbp - 24]
    call [rel __imp_CloseHandle]
    mov rax, [rbp - 16]
    mov rdx, [rbp - 48]
    mov rsp, rbp
    pop rbp
    ret

.read_fail:
    mov rcx, [rbp - 24]
    call [rel __imp_CloseHandle]
    lea rdi, [rel m_read_fail]
    mov esi, m_read_fail_len
    mov edx, 4
    call fatal
.open_fail:
    lea rdi, [rel m_open_fail]
    mov esi, m_open_fail_len
    mov edx, 4
    call fatal_win
.oom:
    lea rdi, [rel m_oom]
    mov esi, m_oom_len
    mov edx, 3
    call fatal
.too_large:
    mov rcx, [rbp - 24]
    call [rel __imp_CloseHandle]
    lea rdi, [rel m_src_too_large]
    mov esi, m_src_too_large_len
    mov edx, 4
    call fatal

; file_write(rdi=lpcwstr path, rsi=ptr, rdx=len) -> rax=1/0
file_write:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], rdx

    mov rcx, [rbp - 8]
    mov edx, GENERIC_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp + 0x20], CREATE_ALWAYS
    mov qword [rsp + 0x28], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp + 0x30], 0
    call [rel __imp_CreateFileW]
    cmp rax, -1
    je .fail
    mov [rbp - 32], rax

    mov rcx, rax
    mov rdx, [rbp - 16]
    mov r8, [rbp - 24]
    lea r9, [rbp - 40]
    mov qword [rsp + 0x20], 0
    call [rel __imp_WriteFile]
    test eax, eax
    jz .fail_close

    mov rcx, [rbp - 32]
    call [rel __imp_CloseHandle]
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret

.fail_close:
    mov rcx, [rbp - 32]
    call [rel __imp_CloseHandle]
.fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret
