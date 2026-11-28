; ===========================================================================
; Flint runtime, embedded at the start of every generated program.
; The calling convention matches generated Flint code: arguments start at
; [rbp+16], the return value is in rax, and the caller cleans the stack.
; IAT slots are section offsets: file offset = section offset + 0x200,
; RVA = 0x1000 + file offset.
; ===========================================================================
BITS 64
DEFAULT REL

%define iat_VirtualAlloc   0x2F000
%define iat_VirtualFree    0x2F008
%define iat_CreateFileA    0x2F010
%define iat_ReadFile       0x2F018
%define iat_WriteFile      0x2F020
%define iat_CloseHandle    0x2F028
%define iat_GetStdHandle   0x2F030
%define iat_ExitProcess    0x2F038
%define iat_GetCommandLineA 0x2F040

; ---------------------------------------------------------------------------
; rt_alloc(size, align) -> ptr
; ---------------------------------------------------------------------------
rt_alloc:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    and rsp, -16
    call rt_args_init
    xor ecx, ecx
    mov rdx, [rbp+16]
    mov r8d, 0x3000
    mov r9d, 4
    call [rel iat_VirtualAlloc]
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_free(ptr) -> 0
; ---------------------------------------------------------------------------
rt_free:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    and rsp, -16
    mov rcx, [rbp+16]
    xor edx, edx
    mov r8d, 0x8000
    call [rel iat_VirtualFree]
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_writefile(path, plen, data, len) -> 1 on success / 0 on failure
; ---------------------------------------------------------------------------
rt_writefile:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    and rsp, -16
    mov rcx, [rbp+16]
    mov edx, 0x40000000
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+0x20], 2
    mov qword [rsp+0x28], 0x80
    mov qword [rsp+0x30], 0
    call [rel iat_CreateFileA]
    cmp rax, -1
    je .wf_fail
    mov [rbp-0x10], rax
    mov rcx, rax
    mov rdx, [rbp+32]
    mov r8, [rbp+40]
    lea r9, [rbp-8]
    mov qword [rsp+0x20], 0
    call [rel iat_WriteFile]
    mov [rbp-0x18], rax
    mov rcx, [rbp-0x10]
    call [rel iat_CloseHandle]
    cmp qword [rbp-0x18], 0
    jz .wf_fail
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret
.wf_fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_readfile(path, plen, dst, max) -> bytes read, 0 on failure
; ---------------------------------------------------------------------------
rt_readfile:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    and rsp, -16
    mov rcx, [rbp+16]
    mov edx, 0x80000000
    mov r8d, 1
    xor r9d, r9d
    mov qword [rsp+0x20], 3
    mov qword [rsp+0x28], 0x80
    mov qword [rsp+0x30], 0
    call [rel iat_CreateFileA]
    cmp rax, -1
    je .rf_fail
    mov [rbp-0x10], rax
    mov rcx, rax
    mov rdx, [rbp+32]
    mov r8, [rbp+40]
    lea r9, [rbp-8]
    mov qword [rsp+0x20], 0
    call [rel iat_ReadFile]
    mov [rbp-0x18], rax
    mov rcx, [rbp-0x10]
    call [rel iat_CloseHandle]
    cmp qword [rbp-0x18], 0
    jz .rf_fail
    mov eax, [rbp-8]
    mov rsp, rbp
    pop rbp
    ret
.rf_fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; One padding byte keeps rt_print at offset 494 in the runtime.
; ---------------------------------------------------------------------------
    db 0x90
; rt_print(value) -> 0
; ---------------------------------------------------------------------------
rt_print:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    and rsp, -16
    mov rcx, -11
    call [rel iat_GetStdHandle]
    mov [rbp-0x10], rax
    mov rax, [rbp+16]
    lea r11, [rbp-0x30]
    xor r8d, r8d
    xor r9d, r9d
    test rax, rax
    jns .pp
    neg rax
    mov r9d, 1
.pp:
    mov rcx, 10
.div:
    xor edx, edx
    div rcx
    dec r11
    add dl, 48
    mov [r11], dl
    inc r8
    test rax, rax
    jnz .div
    test r9, r9
    jz .wr
    dec r11
    mov byte [r11], 45
    inc r8
.wr:
    mov rcx, [rbp-0x10]
    mov rdx, r11
    lea r9, [rbp-8]
    mov qword [rsp+0x20], 0
    call [rel iat_WriteFile]
    mov rcx, [rbp-0x10]
    lea rdx, [rel rt_nl]
    mov r8d, 2
    lea r9, [rbp-8]
    mov qword [rsp+0x20], 0
    call [rel iat_WriteFile]
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_args_init: on the first alloc, split GetCommandLineA into argv and write
; it to the fixed data area. The compiler main program reads argc/argv from
; the generated addresses; ordinary programs do not use these slots.
; ---------------------------------------------------------------------------
rt_args_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x28
    mov rcx, 0x464C495441524756
    cmp qword [rel arg_magic], rcx
    je .done

    call [rel iat_GetCommandLineA]
    test rax, rax
    jz .done
    mov rsi, rax

    xor ecx, ecx
    mov edx, 0x3000
    mov r8d, 0x3000
    mov r9d, 4
    call [rel iat_VirtualAlloc]
    test rax, rax
    jz .done
    mov r15, rax
    lea r14, [rax + 0x1000]
    mov [rel argv_v], r14
    mov [rel arg_buf_v], r15

    mov rdi, r15
    xor ebx, ebx
    xor r12d, r12d
    xor r13d, r13d
.loop:
    movzx eax, byte [rsi]
    test al, al
    jz .end
    cmp al, 34
    je .quote
    cmp al, 32
    je .space
    cmp al, 9
    je .space
    test r12, r12
    jnz .store
    mov [r14 + rbx * 8], rdi
    inc rbx
    mov r12, 1
.store:
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .loop
.quote:
    test r12, r12
    jnz .q_toggle
    mov [r14 + rbx * 8], rdi
    inc rbx
    mov r12, 1
.q_toggle:
    xor r13, 1
    inc rsi
    jmp .loop
.space:
    test r13, r13
    jnz .store
    test r12, r12
    jz .skip
    mov byte [rdi], 0
    inc rdi
    xor r12, r12
.skip:
    inc rsi
    jmp .loop
.end:
    test r12, r12
    jz .finish
    mov byte [rdi], 0
.finish:
    mov [rel argc_v], rbx
    mov rcx, 0x464C495441524756
    mov [rel arg_magic], rcx
.done:
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

align 8
arg_magic: dq 0
argc_v:    dq 0
argv_v:    dq 0
arg_buf_v: dq 0

rt_nl: db 13, 10
