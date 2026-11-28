; ===========================================================================
; Memory: bump arena (stage 0 never reclaims; stage 2 replaces it with a block
; table and optional free)
; arena_alloc(rdi=size) -> rax=ptr (16-byte aligned)
; ===========================================================================
arena_alloc:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    add rdi, 15
    and rdi, ~15
    mov rax, [rel ar_cur]
    mov rdx, rax
    add rdx, rdi
    cmp rdx, [rel ar_end]
    jbe .have

    ; Current block is too small: allocate a new block (size = max(request, 1 MiB))
    mov rsi, rdi
    cmp rsi, 0x100000
    jae .size_ok
    mov esi, 0x100000
.size_ok:
    xor ecx, ecx
    mov rdx, rsi
    mov r8d, MEM_COMMIT_RESERVE
    mov r9d, PAGE_READWRITE
    call [rel __imp_VirtualAlloc]
    test rax, rax
    jz .oom
    mov [rel ar_cur], rax
    mov rdx, rax
    add rdx, rsi
    mov [rel ar_end], rdx
    mov rax, [rel ar_cur]
    mov rdx, rax
    add rdx, rdi
.have:
    mov [rel ar_cur], rdx
    mov rsp, rbp
    pop rbp
    ret
.oom:
    lea rdi, [rel m_oom]
    mov esi, m_oom_len
    mov edx, 3
    call fatal
