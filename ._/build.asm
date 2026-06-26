; build.asm – corrected template generator

section .data
    filename db "./build_output.asm", 0
    template db "section .data", 10
             db "    ; Constants (like JavaScript const)", 10
             db "    ; Example: MAX_SIZE equ 100", 10, 10
             
             db "    ; Global variables (like JavaScript let/var)", 10
             db "    ; Example: counter dq 0", 10
             db "    ; Example: message db 'Hello', 0", 10, 10
             
             db "    ; Function pointers", 10
             db "    ; Example: callback dq 0", 10, 10
             
             db "    ; ANSI Color Codes", 10
             db "    COLOR_RESET   db 27, '[0m', 0", 10
             db "    COLOR_BRIGHT  db 27, '[1m', 0", 10
             db "    COLOR_DARK    db 27, '[2m', 0", 10
             db "    COLOR_GREEN   db 27, '[32m', 0", 10
             db "    COLOR_GRAY    db 27, '[90m', 0   ; Dark gray", 10
             db "    COLOR_BLUE    db 27, '[34m', 0", 10, 10
             
             db "    ; Type constants for print function", 10
             db "    TYPE_STRING    equ 1", 10
             db "    TYPE_NUMBER    equ 2", 10
             db "    TYPE_CHAR      equ 3", 10
             db "    TYPE_BOOLEAN   equ 4", 10
             db "    TYPE_NULL      equ 5", 10
             db "    TYPE_UNDEFINED equ 6", 10
             db "    TYPE_FLOAT     equ 7", 10, 10
             
             db "    ; Boolean strings", 10
             db "    true_str db 'true', 0", 10
             db "    false_str db 'false', 0", 10
             db "    null_str db 'null', 0", 10
             db "    undefined_str db 'undefined', 0", 10
             db "    hex_prefix db '0x', 0", 10
             db "    float_scale dq 1000000000000000.0", 10, 10
             
             db "    ; Common utility strings", 10
             db "    space db ' ', 0", 10
             db "    newline db 10, 0", 10, 10
             
             db "section .bss", 10
             db "    print_buffer resb 32", 10
             db "    number_buffer resb 32", 10
             db "    temp_number resq 1", 10, 10
             
             db "section .text", 10
             db "    global _start", 10, 10
             
             db "print_raw_string:", 10
             db "    ; Input: rsi = pointer to null-terminated string", 10
             db "    push rdi", 10
             db "    push rcx", 10
             db "    push rdx", 10
             db "    mov rdi, rsi", 10
             db "    xor rcx, rcx", 10
             db "    not rcx", 10
             db "    xor al, al", 10
             db "    repne scasb", 10
             db "    not rcx", 10
             db "    dec rcx", 10
             db "    mov rax, 1", 10
             db "    mov rdi, 1", 10
             db "    mov rdx, rcx", 10
             db "    syscall", 10
             db "    pop rdx", 10
             db "    pop rcx", 10
             db "    pop rdi", 10
             db "    ret", 10, 10
             
             db "print_raw_number:", 10
             db "    ; Input: [temp_number] = number to print", 10
             db "    push rbx", 10
             db "    push rcx", 10
             db "    push rdx", 10
             db "    push rsi", 10
             db "    push rdi", 10
             db "    mov rax, [temp_number]", 10
             db "    mov rbx, number_buffer", 10
             db "    add rbx, 30", 10
             db "    mov byte [rbx], 0", 10
             db "    mov rsi, rbx", 10
             db "    dec rsi", 10
             db "    mov rcx, 10", 10
             db "    cmp rax, 0", 10
             db "    jge .convert", 10
             db "    neg rax", 10
             db "    push rax", 10
             db "    mov byte [rsi], '-'", 10
             db "    pop rax", 10
             db "    jmp .convert", 10
             db ".convert:", 10
             db "    xor rdx, rdx", 10
             db "    div rcx", 10
             db "    add dl, '0'", 10
             db "    dec rsi", 10
             db "    mov [rsi+1], dl", 10
             db "    cmp rax, 0", 10
             db "    jne .convert", 10
             db "    inc rsi", 10
             db ".print:", 10
             db "    mov rdi, rsi", 10
             db "    mov rsi, rdi", 10
             db "    call print_raw_string", 10
             db "    pop rdi", 10
             db "    pop rsi", 10
             db "    pop rdx", 10
             db "    pop rcx", 10
             db "    pop rbx", 10
             db "    ret", 10, 10
             
             db "float_to_str:", 10
             db "    ; Convert double in xmm0 to string.", 10
             db "    ; Input:  xmm0 = value (double), rdi = output buffer (min 32 bytes)", 10
             db "    ; Output: buffer filled with null-terminated string", 10
             db "    push rax", 10
             db "    push rbx", 10
             db "    push rcx", 10
             db "    push rdx", 10
             db "    push rsi", 10
             db "    push r8", 10
             db "    push r9", 10
             db "    push r10", 10
             db "    ", 10
             db "    ; Clear buffer", 10
             db "    mov rcx, 32", 10
             db "    xor al, al", 10
             db "    rep stosb", 10
             db "    sub rdi, 32         ; reset pointer to start", 10
             db "    ", 10
             db "    ; Check for negative", 10
             db "    pxor xmm1, xmm1", 10
             db "    comisd xmm0, xmm1", 10
             db "    jae .positive", 10
             db "    mov byte [rdi], '-'", 10
             db "    inc rdi", 10
             db "    movsd xmm2, xmm1", 10
             db "    subsd xmm2, xmm0", 10
             db "    movsd xmm0, xmm2", 10
             db ".positive:", 10
             db "    ", 10
             db "    ; Extract integer part", 10
             db "    cvttsd2si r10, xmm0    ; r10 = integer part", 10
             db "    cvtsi2sd xmm1, r10", 10
             db "    subsd xmm0, xmm1       ; xmm0 = fractional part (0.0 to 0.999...)", 10
             db "    ", 10
             db "    ; Convert integer part to string (store in reverse)", 10
             db "    mov rbx, rdi           ; Save start of number", 10
             db "    mov rax, r10", 10
             db "    mov r8, 10", 10
             db "    test rax, rax", 10
             db "    jnz .int_loop", 10
             db "    mov byte [rdi], '0'", 10
             db "    inc rdi", 10
             db "    jmp .reverse_int", 10
             db ".int_loop:", 10
             db "    test rax, rax", 10
             db "    jz .reverse_int", 10
             db "    xor rdx, rdx", 10
             db "    div r8", 10
             db "    add dl, '0'", 10
             db "    mov [rdi], dl", 10
             db "    inc rdi", 10
             db "    jmp .int_loop", 10
             db ".reverse_int:", 10
             db "    ; Reverse the integer string in-place", 10
             db "    mov rsi, rdi", 10
             db "    dec rsi                ; rsi = last char", 10
             db ".reverse_loop:", 10
             db "    cmp rbx, rsi", 10
             db "    jae .fraction", 10
             db "    mov al, [rbx]", 10
             db "    mov ah, [rsi]", 10
             db "    mov [rbx], ah", 10
             db "    mov [rsi], al", 10
             db "    inc rbx", 10
             db "    dec rsi", 10
             db "    jmp .reverse_loop", 10
             db ".fraction:", 10
             db "    ; Check if fractional part is non-zero", 10
             db "    pxor xmm2, xmm2", 10
             db "    comisd xmm0, xmm2", 10
             db "    je .no_fraction", 10
             db "    ", 10
             db "    mov byte [rdi], '.'", 10
             db "    inc rdi", 10
             db "    ", 10
             db "    ; Multiply fractional part by 1,000,000,000,000,000 to get 15 digits", 10
             db "    movsd xmm1, [float_scale]", 10
             db "    mulsd xmm0, xmm1       ; xmm0 = fraction * 10^15", 10
             db "    cvttsd2si r9, xmm0      ; r9 = 0 to 999999999999999", 10
             db "    ", 10
             db "    ; Convert r9 to 15-digit string with leading zeros", 10
             db "    mov rax, r9", 10
             db "    mov r8, 15               ; Digit counter", 10
             db "    mov r9, 100000000000000          ; Divisor", 10
             db ".frac_loop:", 10
             db "    cmp r8, 0", 10
             db "    je .done_with_fraction", 10
             db "    ", 10
             db "    xor rdx, rdx", 10
             db "    div r9                  ; rax = quotient, rdx = remainder", 10
             db "    add al, '0'", 10
             db "    mov [rdi], al", 10
             db "    inc rdi", 10
             db "    ", 10
             db "    ; Prepare for next iteration", 10
             db "    mov rax, rdx            ; Remainder becomes new dividend", 10
             db "    push rax", 10
             db "    xor rdx, rdx", 10
             db "    mov rax, r9", 10
             db "    mov rcx, 10", 10
             db "    div rcx                 ; rax = r9/10", 10
             db "    mov r9, rax             ; New divisor", 10
             db "    pop rax                 ; Restore dividend", 10
             db "    ", 10
             db "    dec r8", 10
             db "    jmp .frac_loop", 10
             db ".no_fraction:", 10
             db "    ; No fractional part -> just terminate and exit", 10
             db "    mov byte [rdi], 0", 10
             db "    jmp .exit_float_to_str", 10
             db ".done_with_fraction:", 10
             db "    ; Remove trailing zeros after decimal point (only when fraction exists)", 10
             db "    dec rdi", 10
             db ".remove_zeros:", 10
             db "    cmp byte [rdi], '0'", 10
             db "    jne .check_decimal", 10
             db "    dec rdi", 10
             db "    jmp .remove_zeros", 10
             db ".check_decimal:", 10
             db "    cmp byte [rdi], '.'", 10
             db "    jne .terminate", 10
             db "    dec rdi                ; Remove lone decimal point", 10
             db ".terminate:", 10
             db "    inc rdi", 10
             db "    mov byte [rdi], 0", 10
             db ".exit_float_to_str:", 10
             db "    ", 10
             db "    pop r10", 10
             db "    pop r9", 10
             db "    pop r8", 10
             db "    pop rsi", 10
             db "    pop rdx", 10
             db "    pop rcx", 10
             db "    pop rbx", 10
             db "    pop rax", 10
             db "    ret", 10, 10
             
             db "print:", 10
             db "    ; Input: rax = value/pointer, rdx = type", 10
             db "    cmp rdx, TYPE_STRING", 10
             db "    je .print_string", 10
             db "    cmp rdx, TYPE_NUMBER", 10
             db "    je .print_number", 10
             db "    cmp rdx, TYPE_FLOAT", 10
             db "    je .print_float", 10
             db "    cmp rdx, TYPE_CHAR", 10
             db "    je .print_char", 10
             db "    cmp rdx, TYPE_BOOLEAN", 10
             db "    je .print_boolean", 10
             db "    cmp rdx, TYPE_NULL", 10
             db "    je .print_null", 10
             db "    cmp rdx, TYPE_UNDEFINED", 10
             db "    je .print_undefined", 10
             db "    jmp .print_hex", 10
             db "    ", 10
             db ".print_string:", 10
             db "    push rsi", 10
             db "    mov rsi, rax", 10
             db "    call print_raw_string", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_number:", 10
             db "    push rsi", 10
             db "    push rax", 10
             db "    mov [temp_number], rax", 10
             db "    mov rsi, COLOR_BRIGHT", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_GREEN", 10
             db "    call print_raw_string", 10
             db "    call print_raw_number", 10
             db "    mov rsi, COLOR_RESET", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_float:", 10
             db "    push rsi", 10
             db "    push rax", 10
             db "    mov rsi, COLOR_BRIGHT", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_GREEN", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    push rax", 10
             db "    mov rsi, rax           ; rax points to the string", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_RESET", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_char:", 10
             db "    push rsi", 10
             db "    mov [print_buffer], al", 10
             db "    mov byte [print_buffer + 1], 0", 10
             db "    mov rsi, print_buffer", 10
             db "    call print_raw_string", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_boolean:", 10
             db "    push rsi", 10
             db "    push rax", 10
             db "    mov rsi, COLOR_BRIGHT", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_GREEN", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    cmp rax, 0", 10
             db "    je .print_false", 10
             db "    mov rsi, true_str", 10
             db "    call print_raw_string", 10
             db "    jmp .bool_done", 10
             db ".print_false:", 10
             db "    mov rsi, false_str", 10
             db "    call print_raw_string", 10
             db ".bool_done:", 10
             db "    mov rsi, COLOR_RESET", 10
             db "    call print_raw_string", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_null:", 10
             db "    push rsi", 10
             db "    mov rsi, COLOR_DARK", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_GRAY", 10
             db "    call print_raw_string", 10
             db "    mov rsi, null_str", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_RESET", 10
             db "    call print_raw_string", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_undefined:", 10
             db "    push rsi", 10
             db "    mov rsi, COLOR_DARK", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_GRAY", 10
             db "    call print_raw_string", 10
             db "    mov rsi, undefined_str", 10
             db "    call print_raw_string", 10
             db "    mov rsi, COLOR_RESET", 10
             db "    call print_raw_string", 10
             db "    pop rsi", 10
             db "    ret", 10
             db "    ", 10
             db ".print_hex:", 10
             db "    push rsi", 10
             db "    push rax", 10
             db "    mov rsi, hex_prefix", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    push rax", 10
             db "    mov rbx, number_buffer", 10
             db "    add rbx, 31", 10
             db "    mov byte [rbx], 0", 10
             db "    mov rsi, rbx", 10
             db "    mov rcx, 16", 10
             db ".hex_loop:", 10
             db "    dec rsi", 10
             db "    xor rdx, rdx", 10
             db "    div rcx", 10
             db "    cmp dl, 10", 10
             db "    jl .hex_digit", 10
             db "    add dl, 'a' - 10", 10
             db "    jmp .store_hex", 10
             db ".hex_digit:", 10
             db "    add dl, '0'", 10
             db ".store_hex:", 10
             db "    mov [rsi], dl", 10
             db "    cmp rax, 0", 10
             db "    jne .hex_loop", 10
             db "    call print_raw_string", 10
             db "    pop rax", 10
             db "    pop rsi", 10
             db "    ret", 10, 10
             
             db "_start:", 10
             db "    ; Your code here", 10
             db "    ; Example usage:", 10
             db "    ;   mov rax, 42", 10
             db "    ;   mov rdx, TYPE_NUMBER", 10
             db "    ;   call print", 10
             db "    ;   mov rax, newline", 10
             db "    ;   mov rdx, TYPE_STRING", 10
             db "    ;   call print", 10, 10
             db "    mov rax, 60", 10
             db "    xor rdi, rdi", 10
             db "    syscall", 10
    template_len equ $ - template

section .bss
    fd resq 1

section .text
    global _start

_start:
    ; Create the template file
    mov rax, 2                  ; sys_open
    mov rdi, filename           ; filename
    mov rsi, 0o101              ; O_WRONLY | O_CREAT
    or rsi, 0o100               ; O_TRUNC
    mov rdx, 0o644              ; permissions
    syscall
    
    cmp rax, 0
    jl exit_error
    
    mov [fd], rax

    ; Write the template content
    mov rax, 1                  ; sys_write
    mov rdi, [fd]               ; file descriptor
    mov rsi, template           ; buffer
    mov rdx, template_len       ; length
    syscall

    ; Close the file
    mov rax, 3                  ; sys_close
    mov rdi, [fd]
    syscall

    ; Exit successfully
    mov rax, 60
    xor rdi, rdi
    syscall

exit_error:
    mov rax, 60
    mov rdi, 1
    syscall