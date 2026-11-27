; ===========================================================================
; 入口 / 命令行 / 模式分发
; ===========================================================================

; wstreq(rdi=utf16 str, rsi=ascii cstr) -> al=1/0
wstreq:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
.loop:
    movzx ecx, byte [rsi]
    movzx edx, word [rdi]
    test ecx, ecx
    jz .str_end
    cmp edx, ecx
    jne .no
    add rdi, 2
    inc rsi
    jmp .loop
.str_end:
    test edx, edx
    jnz .no
    mov eax, 1
    mov rsp, rbp
    pop rbp
    ret
.no:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; w2u8(rdi=utf16, rsi=outbuf, edx=cap) -> rax=字节长度（0 表示失败）
w2u8:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60
    mov [rbp - 8], rdi
    mov [rbp - 16], rsi
    mov [rbp - 24], rdx
    mov ecx, CP_UTF8
    xor edx, edx
    mov r8, [rbp - 8]
    mov r9, -1
    mov rax, [rbp - 16]
    mov [rsp + 0x20], rax
    mov eax, [rbp - 24]
    mov [rsp + 0x28], rax
    mov qword [rsp + 0x30], 0
    mov qword [rsp + 0x38], 0
    call [rel __imp_WideCharToMultiByte]
    test eax, eax
    jz .fail
    dec eax
    mov rsp, rbp
    pop rbp
    ret
.fail:
    xor eax, eax
    mov rsp, rbp
    pop rbp
    ret

; cmd_tokenize: 把 cmd_w 切成 UTF-16 参数，写入 arg_buf，args[] 指向各段
cmd_tokenize:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    lea rsi, [rel cmd_w]
    lea rdi, [rel arg_buf]
    mov dword [rel argc], 0
    xor r8d, r8d                       ; in_token
    xor r9d, r9d                       ; in_quote
.loop:
    movzx eax, word [rsi]
    test eax, eax
    jz .end
    cmp eax, '"'
    je .quote
    cmp eax, ' '
    je .space
    cmp eax, 9
    je .space
    test r9d, r9d
    jnz .store
    test r8d, r8d
    jnz .store
    ; 新 Token 起点
    mov ecx, [rel argc]
    cmp ecx, 8
    jae .store
    lea rdx, [rel args]
    mov [rdx + rcx * 8], rdi
    inc dword [rel argc]
    mov r8d, 1
.store:
    mov [rdi], ax
    add rdi, 2
    add rsi, 2
    jmp .loop
.quote:
    ; 引号本身不入 token；若当前不在 token 中，则引号处开启新 token
    test r8d, r8d
    jnz .q_toggle
    mov ecx, [rel argc]
    cmp ecx, 8
    jae .q_toggle
    lea rdx, [rel args]
    mov [rdx + rcx * 8], rdi
    inc dword [rel argc]
    mov r8d, 1
.q_toggle:
    xor r9d, 1
    add rsi, 2
    jmp .loop
.space:
    test r9d, r9d
    jnz .store
    test r8d, r8d
    jz .skip
    mov word [rdi], 0
    add rdi, 2
    xor r8d, r8d
.skip:
    add rsi, 2
    jmp .loop
.end:
    test r8d, r8d
    jz .done
    mov word [rdi], 0
.done:
    mov rsp, rbp
    pop rbp
    ret

; dump_tokens()
dump_tokens:
    push rbp
    mov rbp, rsp
    sub rsp, 0x50
    mov qword [rbp - 8], 0
.loop:
    mov rax, [rbp - 8]
    cmp rax, [rel tk_count]
    jae .done
    imul rcx, rax, TK_SIZE
    add rcx, [rel tk_ptr]
    mov [rbp - 16], rcx
    mov rdi, rax
    call out_u32
    mov edi, ' '
    call out_ch
    mov rcx, [rbp - 16]
    mov edi, [rcx + TK_LINE]
    call out_u32
    mov edi, ':'
    call out_ch
    mov rcx, [rbp - 16]
    mov edi, [rcx + TK_COL]
    call out_u32
    mov edi, ' '
    call out_ch
    mov rcx, [rbp - 16]
    mov eax, [rcx + TK_KIND]
    lea rdx, [rel tk_names]
    movsxd rax, dword [rdx + rax * 4]
    lea rdi, [rdx + rax]
    call out_cstr
    mov edi, ' '
    call out_ch
    mov rcx, [rbp - 16]
    mov eax, [rcx + TK_KIND]
    cmp eax, TK_EOF
    je .nl
    mov edi, '"'
    call out_ch
    mov rcx, [rbp - 16]
    mov rdi, [rel src_ptr]
    mov eax, [rcx + TK_START]
    add rdi, rax
    mov esi, [rcx + TK_END]
    sub esi, [rcx + TK_START]
    call out_write
    mov edi, '"'
    call out_ch
.nl:
    mov edi, 10
    call out_ch
    inc qword [rbp - 8]
    jmp .loop
.done:
    mov rsp, rbp
    pop rbp
    ret

; ------------------------------ 编译流程 ----------------------------------
do_compile:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60

    ; 输入路径 -> UTF-8（诊断用）
    mov rdi, [rel args + 8]
    lea rsi, [rel path8]
    mov edx, 2048
    call w2u8
    lea rdx, [rel path8]
    mov [rel path8_ptr], rdx
    mov [rel path8_len], rax

    ; 读取源码
    mov rdi, [rel args + 8]
    call file_read
    mov [rel src_ptr], rax
    mov [rel src_len], rdx

    ; 词法
    mov rdi, rax
    mov rsi, rdx
    call lex_run
    mov [rbp - 8], rax                  ; tokens
    mov rdx, [rel tk_count]
    mov [rbp - 16], rdx                 ; count

    cmp dword [rel err_count], 0
    jne .fail

    ; 语法
    mov rdi, [rbp - 8]
    mov rsi, [rbp - 16]
    call parse_run
    mov [rbp - 24], rax

    cmp dword [rel err_count], 0
    jne .fail

    ; 语义 + 代码生成
    mov rdi, [rbp - 24]
    call cg_run
    cmp dword [rel err_count], 0
    jne .fail

    ; 写出 PE
    mov rdi, [rel args + 16]
    call pe_write
    test eax, eax
    jz .write_fail

    lea rdi, [rel s_ok]
    call out_cstr
    mov edi, [rel tk_count]
    call out_u32
    mov edi, 10
    call out_ch
    xor edi, edi
    call exit_now

.write_fail:
    lea rdi, [rel m_out_open_fail]
    mov esi, m_out_open_fail_len
    mov edx, 5
    call fatal_win

.fail:
    mov edi, 1
    call exit_now

; ------------------------------ 入口 --------------------------------------
start_here:
    push rbp
    mov rbp, rsp
    sub rsp, 0x60

    mov ecx, STD_OUTPUT_HANDLE
    call [rel __imp_GetStdHandle]
    mov [rel h_stdout], rax
    call [rel __imp_GetConsoleOutputCP]
    mov [rel old_cp], eax
    mov ecx, CP_UTF8
    call [rel __imp_SetConsoleOutputCP]
    call [rel __imp_GetCommandLineW]
    mov rsi, rax
    lea rdi, [rel cmd_w]
    xor ecx, ecx
.copy_cl:
    mov ax, [rsi]
    mov [rdi], ax
    test ax, ax
    jz .copied
    add rsi, 2
    add rdi, 2
    inc ecx
    cmp ecx, 4095
    jb .copy_cl
    mov word [rdi], 0
.copied:
    call cmd_tokenize

    cmp dword [rel argc], 2
    jl .usage
    mov rdi, [rel args + 8]
    lea rsi, [rel s_opt_version]
    call wstreq
    test al, al
    jnz .version
    mov rdi, [rel args + 8]
    lea rsi, [rel s_opt_tokens]
    call wstreq
    test al, al
    jnz .tokens
    cmp dword [rel argc], 3
    jl .usage
    call do_compile
    jmp .exit

.version:
    lea rdi, [rel m_banner]
    call out_cstr
    mov edi, 10
    call out_ch
    xor edi, edi
    call exit_now

.tokens:
    cmp dword [rel argc], 3
    jl .usage
    mov rdi, [rel args + 16]
    lea rsi, [rel path8]
    mov edx, 2048
    call w2u8
    lea rdx, [rel path8]
    mov [rel path8_ptr], rdx
    mov [rel path8_len], rax
    mov rdi, [rel args + 16]
    call file_read
    mov [rel src_ptr], rax
    mov [rel src_len], rdx
    mov rdi, rax
    mov rsi, rdx
    call lex_run
    call dump_tokens
    cmp dword [rel err_count], 0
    jne .exit1
    xor edi, edi
    call exit_now
.exit1:
    mov edi, 1
    call exit_now

.usage:
    lea rdi, [rel m_usage]
    call out_cstr
    mov edi, 10
    call out_ch
    mov edi, 2
    call exit_now
.exit:
    xor edi, edi
    call exit_now

; ------------------------------ 数据 --------------------------------------
s_opt_version:  db "--version", 0
s_opt_tokens:   db "--tokens", 0
s_ok:           db "flint: 编译成功，tokens=", 0

entry_rva equ start_here - sec_start + SEC_RVA
