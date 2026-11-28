; ===========================================================================
; Flint seed compiler (stage 0)
; Build: nasm -f bin (two passes: measure section lengths, then write the PE header)
; No linker and no C runtime; imports kernel32 only.
; ===========================================================================
BITS 64
DEFAULT REL

%ifndef SEC_RAW
%define SEC_RAW 0x200          ; editor default only; build.ps1 must pass the measured value
%endif

%include "defines.inc"
%define SEC_IMAGE_SIZE ((SEC_RVA + SEC_RAW + 0xFFF) & ~0xFFF)

%ifndef MEASURE_PASS
; ============================ DOS header ===================================
seed_file_start:
    dw 0x5A4D
    times 0x3A db 0
    dd 0x40

; ============================ PE / COFF ====================================
    dd 0x00004550
    dw 0x8664
    dw 1
    dd 0
    dd 0
    dd 0
    dw 0x00F0
    dw 0x0023                       ; EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE | RELOCS_STRIPPED

; ========================== optional header PE32+ =========================
seed_opt:
    dw 0x020B
    db 0
    db 0
    dd SEC_RAW
    dd 0
    dd 0
    dd entry_rva
    dd SEC_RVA
    dq IMAGE_BASE
    dd 0x1000
    dd 0x200
    dw 6
    dw 0
    dw 0
    dw 0
    dw 6
    dw 0
    dd 0
    dd SEC_IMAGE_SIZE
    dd HDR_SIZE
    dd 0
    dw 3
    dw 0
    dq 0x00100000
    dq 0x00001000
    dq 0x00100000
    dq 0x00001000
    dd 0
    dd 16
    dd 0, 0
    dd imp_rva, imp_size
    times 14 dd 0, 0

; ============================ section table ===============================
    db ".text", 0, 0, 0
    dd SEC_RAW
    dd SEC_RVA
    dd SEC_RAW
    dd HDR_SIZE
    dd 0, 0
    dw 0, 0
    dd 0xE0000060

    times HDR_SIZE - ($ - $$) db 0
%endif

; ============================ section contents ============================
%include "data.asm"
%include "memory.asm"
%include "diag.asm"
%include "fileio.asm"
%include "lexer.asm"
%include "parser.asm"
%include "codegen1.asm"
%include "codegen2.asm"
%include "main.asm"

align 0x200
