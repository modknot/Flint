; ===========================================================================
; Flint 运行库：由编译器嵌入到每个生成程序的开头。
; 调用约定与 Flint 生成代码一致：参数从 [rbp+16] 起，返回值 rax，调用方清栈。
; IAT 槽位以节内偏移表示：文件偏移 = 节内偏移 + 0x200，RVA = 0x1000 + 文件偏移。
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

; ---------------------------------------------------------------------------
; rt_alloc(size, align) -> ptr
; ---------------------------------------------------------------------------
rt_alloc:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
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
    mov rcx, [rbp+16]
    xor edx, edx
    mov r8d, 0x8000
    call [rel iat_VirtualFree]
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_writefile(path, plen, data, len) -> 1 成功 / 0 失败
; ---------------------------------------------------------------------------
rt_writefile:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
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
; rt_readfile(path, plen, dst, max) -> 读到的字节数，失败 0
; ---------------------------------------------------------------------------
rt_readfile:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
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
    mov rax, [rbp-8]
    mov rsp, rbp
    pop rbp
    ret
.rf_fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; ---------------------------------------------------------------------------
; rt_print(value) -> 0
; ---------------------------------------------------------------------------
rt_print:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
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

rt_nl: db 13, 10
