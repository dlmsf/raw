section .data
    ; Error messages
    error_args db 'Usage: ./minify input.js [output.js]', 0x0A, 0
    error_open_input db 'Error: Cannot open input file', 0x0A, 0
    error_open_output db 'Error: Cannot open output file', 0x0A, 0
    error_read db 'Error: Cannot read input file', 0x0A, 0
    error_write db 'Error: Cannot write output file', 0x0A, 0
    
    ; Default output filename
    default_output db 'output.js', 0
    
    ; Buffers - explicitly sized for safety
    input_buffer times 65536 db 0
    output_buffer times 65536 db 0
    
section .text
    global _start

_start:
    ; Validate command line arguments
    pop rcx                     ; argc
    cmp rcx, 2
    jl .error_args              ; Need at least input file
    cmp rcx, 3
    jg .error_args              ; Max 3 args
    
    ; Process input filename
    pop rdi                     ; Skip program name
    pop rdi                     ; First arg (input file)
    
    ; Open input file - read only mode
    mov rax, 2                  ; sys_open
    mov rsi, 0                  ; O_RDONLY
    mov rdx, 0                  ; No special permissions needed
    syscall
    cmp rax, 0
    jl .error_open_input
    mov r8, rax                 ; Save input file descriptor
    
    ; Read input file with explicit size limit
    mov rdi, rax                ; fd
    mov rax, 0                  ; sys_read
    mov rsi, input_buffer
    mov rdx, 65536              ; Max buffer size
    syscall
    cmp rax, 0
    jl .error_read
    mov r9, rax                 ; Save actual input length
    
    ; Close input file immediately after reading
    mov rax, 3                  ; sys_close
    mov rdi, r8
    syscall
    
    ; Check if output filename was provided
    pop rcx                     ; Check for third argument
    test rcx, rcx
    jz .use_default_output
    
    mov rdi, rcx                ; Use provided output filename
    jmp .open_output
    
.use_default_output:
    lea rdi, [default_output]
    
.open_output:
    ; Open/Create output file with safe permissions
    mov rax, 2                  ; sys_open
    mov rsi, 0x241              ; O_CREAT|O_WRONLY|O_TRUNC
    mov rdx, 0o644              ; Standard file permissions (rw-r--r--)
    syscall
    cmp rax, 0
    jl .error_open_output
    mov r10, rax                ; Save output file descriptor
    
    ; ========== MINIFIER LOGIC ==========
    mov rsi, input_buffer       ; Source pointer
    mov rdi, output_buffer      ; Destination pointer
    mov rcx, r9                 ; Input length
    
    ; State tracking
    xor r11, r11                ; String state: 0=none, 1=', 2=", 3=`
    xor r12, r12                ; Comment state: 0=none, 1=//, 2=/* */
    xor r13, r13                ; Escape next char flag
    xor r14, r14                ; Last non-whitespace char
    xor r15, r15                ; In object/array literal flag (0=no, 1=yes)
    xor r8, r8                  ; Regex state: 0=not in regex, 1=inside regex
    
.minify_loop:
    test rcx, rcx
    jz .minify_done
    
    mov al, [rsi]
    
    ; Handle regex state first (before strings/comments)
    test r8, r8
    jnz .in_regex
    
    ; Handle comments - but NOT when inside a string
    test r11, r11
    jnz .in_string
    test r12, r12
    jnz .in_comment
    
    ; Handle strings (single, double, AND template)
    test r11, r11
    jnz .in_string
    
    ; Not in string, comment, or regex
    cmp al, "'"
    je .start_string_single
    cmp al, '"'
    je .start_string_double
    cmp al, '`'
    je .start_string_template
    cmp al, '/'
    je .handle_slash
    
    ; Update object/array literal tracking
    cmp al, '{'
    je .possible_object_start
    cmp al, '}'
    je .handle_close_brace
    cmp al, '['
    je .possible_array_start
    cmp al, ']'
    je .handle_close_bracket
    
    ; Handle whitespace
    call .is_whitespace
    jc .handle_whitespace
    
    ; Check if we need to add semicolon before certain characters
    cmp al, 'l'
    je .check_if_let_needs_semicolon
    cmp al, 'c'
    je .check_if_const_needs_semicolon
    cmp al, 'v'
    je .check_if_var_needs_semicolon
    cmp al, 'f'
    je .check_if_function_needs_semicolon
    
    ; Handle regular character
    mov [rdi], al
    inc rdi
    
    ; Update last character
    mov r14, rax
    jmp .next_char

; ===================== SLASH HANDLER =====================
.handle_slash:
    ; Need to look at next character to decide
    cmp rcx, 1
    je .slash_copy              ; End of input, just copy slash
    
    mov bl, [rsi + 1]
    ; Check for line comment //
    cmp bl, '/'
    je .start_line_comment
    ; Check for block comment /*
    cmp bl, '*'
    je .start_block_comment
    
    ; Not a comment -> check for regex start
    cmp r14b, '('
    je .start_regex
    cmp r14b, '['
    je .start_regex
    cmp r14b, ','
    je .start_regex
    cmp r14b, '='
    je .start_regex
    cmp r14b, ':'
    je .start_regex
    cmp r14b, '!'
    je .start_regex
    cmp r14b, '&'
    je .start_regex
    cmp r14b, '|'
    je .start_regex
    cmp r14b, '?'
    je .start_regex
    cmp r14b, '~'
    je .start_regex
    cmp r14b, '{'
    je .start_regex
    cmp r14b, ';'
    je .start_regex
    
.slash_copy:
    ; Treat slash as division operator - just copy it
    mov [rdi], al
    inc rdi
    mov r14, rax
    jmp .next_char

.start_regex:
    ; Enter regex state, copy the opening '/'
    mov r8, 1                   ; Regex state active
    xor r13, r13                ; Reset escape flag for regex
    mov [rdi], al
    inc rdi
    mov r14, rax                ; Last char is '/'
    jmp .next_char

; ===================== REGEX BODY HANDLER =====================
.in_regex:
    ; Copy current character
    mov [rdi], al
    inc rdi
    mov r14, rax
    
    ; Check for escape sequence
    cmp r13, 1
    je .reset_regex_escape
    
    cmp al, '\'
    je .set_regex_escape
    
    ; Check for closing '/'
    cmp al, '/'
    jne .next_char
    
    ; End of regex literal
    xor r8, r8                  ; Exit regex state
    xor r13, r13                ; Clear escape flag
    jmp .next_char

.set_regex_escape:
    mov r13, 1
    jmp .next_char

.reset_regex_escape:
    mov r13, 0
    jmp .next_char
; ============================================================

.handle_close_brace:
    ; Handle closing brace
    mov [rdi], al
    inc rdi
    mov r14, rax
    
    ; Check if we're in an object literal
    cmp r15, 1
    jne .not_in_object_literal
    ; Exiting object literal
    mov r15, 0
    
.not_in_object_literal:
    ; After closing brace, we might need semicolon
    ; Check next non-whitespace character
    push rsi
    push rcx
    push rax
    
    ; Save current position
    mov rbx, rsi
    inc rbx
    dec rcx
    
.check_next_after_brace:
    cmp rcx, 0
    je .no_semicolon_after_brace
    mov al, [rbx]
    
    ; Skip whitespace
    cmp al, ' '
    je .continue_check_brace
    cmp al, 0x09
    je .continue_check_brace
    cmp al, 0x0A
    je .continue_check_brace
    cmp al, 0x0D
    je .continue_check_brace
    
    ; Found next non-whitespace char
    ; Check if it's a character that needs semicolon before it
    cmp al, 'l'
    je .check_let_after_brace
    cmp al, 'c'
    je .check_const_after_brace
    cmp al, 'v'
    je .check_var_after_brace
    cmp al, 'f'
    je .check_function_after_brace
    
    ; Not a variable/function declaration, no semicolon needed
    jmp .no_semicolon_after_brace

.check_let_after_brace:
    ; Check if it's 'let'
    cmp rcx, 3
    jb .no_semicolon_after_brace
    mov dl, [rbx + 1]
    cmp dl, 'e'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 2]
    cmp dl, 't'
    jne .no_semicolon_after_brace
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 4
    je .needs_semicolon_after_brace
    mov dl, [rbx + 3]
    cmp dl, ' '
    je .needs_semicolon_after_brace
    cmp dl, 0x09
    je .needs_semicolon_after_brace
    cmp dl, 0x0A
    je .needs_semicolon_after_brace
    cmp dl, 0x0D
    je .needs_semicolon_after_brace
    cmp dl, ';'
    je .needs_semicolon_after_brace
    jmp .no_semicolon_after_brace

.check_const_after_brace:
    ; Check if it's 'const'
    cmp rcx, 5
    jb .no_semicolon_after_brace
    mov dl, [rbx + 1]
    cmp dl, 'o'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 2]
    cmp dl, 'n'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 3]
    cmp dl, 's'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 4]
    cmp dl, 't'
    jne .no_semicolon_after_brace
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 6
    je .needs_semicolon_after_brace
    mov dl, [rbx + 5]
    cmp dl, ' '
    je .needs_semicolon_after_brace
    cmp dl, 0x09
    je .needs_semicolon_after_brace
    cmp dl, 0x0A
    je .needs_semicolon_after_brace
    cmp dl, 0x0D
    je .needs_semicolon_after_brace
    cmp dl, ';'
    je .needs_semicolon_after_brace
    jmp .no_semicolon_after_brace

.check_var_after_brace:
    ; Check if it's 'var'
    cmp rcx, 3
    jb .no_semicolon_after_brace
    mov dl, [rbx + 1]
    cmp dl, 'a'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 2]
    cmp dl, 'r'
    jne .no_semicolon_after_brace
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 4
    je .needs_semicolon_after_brace
    mov dl, [rbx + 3]
    cmp dl, ' '
    je .needs_semicolon_after_brace
    cmp dl, 0x09
    je .needs_semicolon_after_brace
    cmp dl, 0x0A
    je .needs_semicolon_after_brace
    cmp dl, 0x0D
    je .needs_semicolon_after_brace
    cmp dl, ';'
    je .needs_semicolon_after_brace
    jmp .no_semicolon_after_brace

.check_function_after_brace:
    ; Check if it's 'function'
    cmp rcx, 8
    jb .no_semicolon_after_brace
    mov dl, [rbx + 1]
    cmp dl, 'u'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 2]
    cmp dl, 'n'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 3]
    cmp dl, 'c'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 4]
    cmp dl, 't'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 5]
    cmp dl, 'i'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 6]
    cmp dl, 'o'
    jne .no_semicolon_after_brace
    mov dl, [rbx + 7]
    cmp dl, 'n'
    jne .no_semicolon_after_brace
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 9
    je .needs_semicolon_after_brace
    mov dl, [rbx + 8]
    cmp dl, ' '
    je .needs_semicolon_after_brace
    cmp dl, 0x09
    je .needs_semicolon_after_brace
    cmp dl, 0x0A
    je .needs_semicolon_after_brace
    cmp dl, 0x0D
    je .needs_semicolon_after_brace
    cmp dl, ';'
    je .needs_semicolon_after_brace
    jmp .no_semicolon_after_brace

.continue_check_brace:
    inc rbx
    dec rcx
    jmp .check_next_after_brace

.needs_semicolon_after_brace:
    ; Add semicolon after the brace
    mov byte [rdi], ';'
    inc rdi
    
.no_semicolon_after_brace:
    pop rax
    pop rcx
    pop rsi
    jmp .next_char

.handle_close_bracket:
    ; Handle closing bracket
    mov [rdi], al
    inc rdi
    mov r14, rax
    
    ; Check if we're in an array literal
    cmp r15, 1
    jne .not_in_array_literal
    ; Exiting array literal
    mov r15, 0
    
.not_in_array_literal:
    ; After closing bracket, we might need semicolon
    ; Check next non-whitespace character
    push rsi
    push rcx
    push rax
    
    ; Save current position
    mov rbx, rsi
    inc rbx
    dec rcx
    
.check_next_after_bracket:
    cmp rcx, 0
    je .no_semicolon_after_bracket
    mov al, [rbx]
    
    ; Skip whitespace
    cmp al, ' '
    je .continue_check_bracket
    cmp al, 0x09
    je .continue_check_bracket
    cmp al, 0x0A
    je .continue_check_bracket
    cmp al, 0x0D
    je .continue_check_bracket
    
    ; Found next non-whitespace char
    ; Check if it's a character that needs semicolon before it
    cmp al, 'l'
    je .check_let_after_bracket
    cmp al, 'c'
    je .check_const_after_bracket
    cmp al, 'v'
    je .check_var_after_bracket
    cmp al, 'f'
    je .check_function_after_bracket
    
    ; Not a variable/function declaration, no semicolon needed
    jmp .no_semicolon_after_bracket

.check_let_after_bracket:
    ; Check if it's 'let'
    cmp rcx, 3
    jb .no_semicolon_after_bracket
    mov dl, [rbx + 1]
    cmp dl, 'e'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 2]
    cmp dl, 't'
    jne .no_semicolon_after_bracket
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 4
    je .needs_semicolon_after_bracket
    mov dl, [rbx + 3]
    cmp dl, ' '
    je .needs_semicolon_after_bracket
    cmp dl, 0x09
    je .needs_semicolon_after_bracket
    cmp dl, 0x0A
    je .needs_semicolon_after_bracket
    cmp dl, 0x0D
    je .needs_semicolon_after_bracket
    cmp dl, ';'
    je .needs_semicolon_after_bracket
    jmp .no_semicolon_after_bracket

.check_const_after_bracket:
    ; Check if it's 'const'
    cmp rcx, 5
    jb .no_semicolon_after_bracket
    mov dl, [rbx + 1]
    cmp dl, 'o'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 2]
    cmp dl, 'n'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 3]
    cmp dl, 's'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 4]
    cmp dl, 't'
    jne .no_semicolon_after_bracket
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 6
    je .needs_semicolon_after_bracket
    mov dl, [rbx + 5]
    cmp dl, ' '
    je .needs_semicolon_after_bracket
    cmp dl, 0x09
    je .needs_semicolon_after_bracket
    cmp dl, 0x0A
    je .needs_semicolon_after_bracket
    cmp dl, 0x0D
    je .needs_semicolon_after_bracket
    cmp dl, ';'
    je .needs_semicolon_after_bracket
    jmp .no_semicolon_after_bracket

.check_var_after_bracket:
    ; Check if it's 'var'
    cmp rcx, 3
    jb .no_semicolon_after_bracket
    mov dl, [rbx + 1]
    cmp dl, 'a'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 2]
    cmp dl, 'r'
    jne .no_semicolon_after_bracket
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 4
    je .needs_semicolon_after_bracket
    mov dl, [rbx + 3]
    cmp dl, ' '
    je .needs_semicolon_after_bracket
    cmp dl, 0x09
    je .needs_semicolon_after_bracket
    cmp dl, 0x0A
    je .needs_semicolon_after_bracket
    cmp dl, 0x0D
    je .needs_semicolon_after_bracket
    cmp dl, ';'
    je .needs_semicolon_after_bracket
    jmp .no_semicolon_after_bracket

.check_function_after_bracket:
    ; Check if it's 'function'
    cmp rcx, 8
    jb .no_semicolon_after_bracket
    mov dl, [rbx + 1]
    cmp dl, 'u'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 2]
    cmp dl, 'n'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 3]
    cmp dl, 'c'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 4]
    cmp dl, 't'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 5]
    cmp dl, 'i'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 6]
    cmp dl, 'o'
    jne .no_semicolon_after_bracket
    mov dl, [rbx + 7]
    cmp dl, 'n'
    jne .no_semicolon_after_bracket
    
    ; Check if followed by whitespace or semicolon
    cmp rcx, 9
    je .needs_semicolon_after_bracket
    mov dl, [rbx + 8]
    cmp dl, ' '
    je .needs_semicolon_after_bracket
    cmp dl, 0x09
    je .needs_semicolon_after_bracket
    cmp dl, 0x0A
    je .needs_semicolon_after_bracket
    cmp dl, 0x0D
    je .needs_semicolon_after_bracket
    cmp dl, ';'
    je .needs_semicolon_after_bracket
    jmp .no_semicolon_after_bracket

.continue_check_bracket:
    inc rbx
    dec rcx
    jmp .check_next_after_bracket

.needs_semicolon_after_bracket:
    ; Add semicolon after the bracket
    mov byte [rdi], ';'
    inc rdi
    
.no_semicolon_after_bracket:
    pop rax
    pop rcx
    pop rsi
    jmp .next_char

.check_if_let_needs_semicolon:
    ; Check if we need semicolon before 'let'
    cmp rcx, 3
    jb .copy_char
    
    ; Verify it's actually 'let'
    mov bl, [rsi + 1]
    cmp bl, 'e'
    jne .copy_char
    mov bl, [rsi + 2]
    cmp bl, 't'
    jne .copy_char
    
    ; Check if next char is whitespace or semicolon
    cmp rcx, 4
    je .check_prev_for_semicolon
    mov bl, [rsi + 3]
    cmp bl, ' '
    je .check_prev_for_semicolon
    cmp bl, 0x09
    je .check_prev_for_semicolon
    cmp bl, 0x0A
    je .check_prev_for_semicolon
    cmp bl, 0x0D
    je .check_prev_for_semicolon
    cmp bl, ';'
    je .check_prev_for_semicolon
    jmp .copy_char

.check_if_const_needs_semicolon:
    ; Check if we need semicolon before 'const'
    cmp rcx, 5
    jb .copy_char
    
    ; Verify it's actually 'const'
    mov bl, [rsi + 1]
    cmp bl, 'o'
    jne .copy_char
    mov bl, [rsi + 2]
    cmp bl, 'n'
    jne .copy_char
    mov bl, [rsi + 3]
    cmp bl, 's'
    jne .copy_char
    mov bl, [rsi + 4]
    cmp bl, 't'
    jne .copy_char
    
    ; Check if next char is whitespace or semicolon
    cmp rcx, 6
    je .check_prev_for_semicolon
    mov bl, [rsi + 5]
    cmp bl, ' '
    je .check_prev_for_semicolon
    cmp bl, 0x09
    je .check_prev_for_semicolon
    cmp bl, 0x0A
    je .check_prev_for_semicolon
    cmp bl, 0x0D
    je .check_prev_for_semicolon
    cmp bl, ';'
    je .check_prev_for_semicolon
    jmp .copy_char

.check_if_var_needs_semicolon:
    ; Check if we need semicolon before 'var'
    cmp rcx, 3
    jb .copy_char
    
    ; Verify it's actually 'var'
    mov bl, [rsi + 1]
    cmp bl, 'a'
    jne .copy_char
    mov bl, [rsi + 2]
    cmp bl, 'r'
    jne .copy_char
    
    ; Check if next char is whitespace or semicolon
    cmp rcx, 4
    je .check_prev_for_semicolon
    mov bl, [rsi + 3]
    cmp bl, ' '
    je .check_prev_for_semicolon
    cmp bl, 0x09
    je .check_prev_for_semicolon
    cmp bl, 0x0A
    je .check_prev_for_semicolon
    cmp bl, 0x0D
    je .check_prev_for_semicolon
    cmp bl, ';'
    je .check_prev_for_semicolon
    jmp .copy_char

.check_if_function_needs_semicolon:
    ; Check if we need semicolon before 'function'
    cmp rcx, 8
    jb .copy_char
    
    ; Verify it's actually 'function'
    mov bl, [rsi + 1]
    cmp bl, 'u'
    jne .copy_char
    mov bl, [rsi + 2]
    cmp bl, 'n'
    jne .copy_char
    mov bl, [rsi + 3]
    cmp bl, 'c'
    jne .copy_char
    mov bl, [rsi + 4]
    cmp bl, 't'
    jne .copy_char
    mov bl, [rsi + 5]
    cmp bl, 'i'
    jne .copy_char
    mov bl, [rsi + 6]
    cmp bl, 'o'
    jne .copy_char
    mov bl, [rsi + 7]
    cmp bl, 'n'
    jne .copy_char
    
    ; Check if next char is whitespace or semicolon
    cmp rcx, 9
    je .check_prev_for_semicolon
    mov bl, [rsi + 8]
    cmp bl, ' '
    je .check_prev_for_semicolon
    cmp bl, 0x09
    je .check_prev_for_semicolon
    cmp bl, 0x0A
    je .check_prev_for_semicolon
    cmp bl, 0x0D
    je .check_prev_for_semicolon
    cmp bl, ';'
    je .check_prev_for_semicolon
    jmp .copy_char

.check_prev_for_semicolon:
    ; Check if we need semicolon before this keyword
    cmp rdi, output_buffer
    je .no_semicolon_before_keyword
    
    ; Look at last character in output
    mov bl, [rdi - 1]
    
    ; Check if last char needs semicolon before keyword
    cmp bl, '}'
    je .add_semicolon_before_keyword
    cmp bl, ')'
    je .add_semicolon_before_keyword
    cmp bl, ']'
    je .add_semicolon_before_keyword
    cmp bl, '"'
    je .add_semicolon_before_keyword
    cmp bl, "'"
    je .add_semicolon_before_keyword
    cmp bl, '`'
    je .add_semicolon_before_keyword
    
    ; Check if it's an identifier character
    push rax
    mov al, bl
    call .is_identifier_char_al
    pop rax
    jc .add_semicolon_before_keyword
    
.no_semicolon_before_keyword:
    jmp .copy_char

.add_semicolon_before_keyword:
    ; Add semicolon before keyword
    mov byte [rdi], ';'
    inc rdi
    jmp .copy_char

.handle_whitespace:
    ; Check what type of whitespace
    cmp al, 0x0A                ; Newline
    je .handle_newline
    cmp al, 0x0D                ; Carriage return
    je .handle_newline
    
    ; For spaces/tabs
    cmp al, ' '
    jne .skip_char
    
    ; Keep space between identifiers
    cmp rsi, input_buffer
    je .skip_char
    
    cmp rcx, 1
    je .skip_char
    
    mov bl, [rsi - 1]
    mov dl, [rsi + 1]
    
    call .is_identifier_char
    jnc .skip_char
    
    push rbx
    mov bl, dl
    call .is_identifier_char
    pop rbx
    jnc .skip_char
    
    mov byte [rdi], ' '
    inc rdi
    
.skip_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.handle_newline:
    ; Check if we need semicolon at newline
    test r14, r14
    jz .skip_char                ; No last char
    
    ; Don't add semicolons inside object/array literals
    cmp r15, 0
    jne .skip_char               ; Inside object/array
    
    ; Check last character to see if we need semicolon
    mov bl, r14b
    
    ; If last char was } ) ] " ' ` or identifier, we might need semicolon
    cmp bl, '}'
    je .maybe_add_semicolon
    cmp bl, ')'
    je .maybe_add_semicolon
    cmp bl, ']'
    je .maybe_add_semicolon
    cmp bl, '"'
    je .maybe_add_semicolon
    cmp bl, "'"
    je .maybe_add_semicolon
    cmp bl, '`'
    je .maybe_add_semicolon
    
    ; Check if last char was identifier char
    call .is_identifier_char
    jc .maybe_add_semicolon
    
    jmp .skip_char

.maybe_add_semicolon:
    ; Don't add if already has semicolon
    cmp rdi, output_buffer
    je .skip_char
    
    mov dl, [rdi - 1]
    cmp dl, ';'
    je .skip_char
    cmp dl, '{'
    je .skip_char
    
    ; Check if next non-whitespace char starts a control statement
    push rsi
    push rcx
    push rax
    
    ; Skip current newline
    mov rbx, rsi
    inc rbx
    dec rcx
    
.peek_next_non_ws:
    cmp rcx, 0
    je .no_control_statement
    mov al, [rbx]
    
    ; Skip whitespace
    cmp al, ' '
    je .continue_peek
    cmp al, 0x09
    je .continue_peek
    cmp al, 0x0A
    je .continue_peek
    cmp al, 0x0D
    je .continue_peek
    
    ; Skip comments in the lookahead
    cmp al, '/'
    jne .check_control           ; Not a slash, continue with control check
    ; Check if this is a comment start
    cmp rcx, 1
    jbe .no_control_statement   ; Not enough chars for a comment
    mov dl, [rbx + 1]
    cmp dl, '/'
    je .skip_line_comment_peek
    cmp dl, '*'
    je .skip_block_comment_peek
    jmp .no_control_statement   ; Regular division, treat as no statement start

.check_control:
    ; Check if next token starts a control statement (original logic)
    cmp al, 'a'
    jb .no_control_statement
    cmp al, 'z'
    ja .no_control_statement
    
    jmp .should_add_semicolon
    
.continue_peek:
    inc rbx
    dec rcx
    jmp .peek_next_non_ws

; ---- Comment skipping routines (only used in peek) ----

.skip_line_comment_peek:
    ; Skip until newline
    inc rbx          ; move past the second '/'
    dec rcx
.skip_line_loop:
    cmp rcx, 0
    je .no_control_statement
    mov al, [rbx]
    cmp al, 0x0A
    je .after_line_comment_peek
    inc rbx
    dec rcx
    jmp .skip_line_loop
.after_line_comment_peek:
    ; Skip the newline itself and continue peeking
    inc rbx
    dec rcx
    jmp .peek_next_non_ws

.skip_block_comment_peek:
    ; Skip until '*/'
    add rbx, 2      ; move past the '/*'
    sub rcx, 2
.skip_block_loop:
    cmp rcx, 0
    je .no_control_statement
    mov al, [rbx]
    cmp al, '*'
    jne .advance_block_peek
    cmp rcx, 1
    je .advance_block_peek
    mov dl, [rbx + 1]
    cmp dl, '/'
    je .after_block_comment_peek
.advance_block_peek:
    inc rbx
    dec rcx
    jmp .skip_block_loop
.after_block_comment_peek:
    ; Skip the '*/' and continue peeking
    add rbx, 2
    sub rcx, 2
    jmp .peek_next_non_ws
; ----------------------------------------------------------

.should_add_semicolon:
    pop rax
    pop rcx
    pop rsi
    
    ; Insert semicolon
    mov byte [rdi], ';'
    inc rdi
    jmp .skip_char

.no_control_statement:
    pop rax
    pop rcx
    pop rsi
    jmp .skip_char

.possible_object_start:
    ; Check if this is an object literal or a block
    cmp rsi, input_buffer
    je .is_block                ; At start of file, must be block
    
    mov bl, [rsi - 1]
    
    ; If preceded by =, :, ,, (, [, {, =>, or identifier, it's an object literal
    cmp bl, '='
    je .is_object_literal
    cmp bl, ':'
    je .is_object_literal
    cmp bl, ','
    je .is_object_literal
    cmp bl, '('
    je .is_object_literal
    cmp bl, '['
    je .is_object_literal
    cmp bl, '{'
    je .is_block               ; Nested block, not object literal
    
    ; Check for arrow function
    cmp rsi, input_buffer + 1
    jb .check_id_char
    mov bh, [rsi - 2]
    cmp bh, '='
    jne .check_id_char
    cmp bl, '>'
    je .is_object_literal
    
.check_id_char:
    ; If preceded by identifier char, it could be either
    push rbx
    call .is_identifier_char
    pop rbx
    jc .is_block               ; identifier{ is usually a block (like if{)
    
.is_block:
    ; Regular block - don't set object literal flag
    jmp .copy_char

.is_object_literal:
    ; Start of object literal
    mov r15, 1
    jmp .copy_char

.possible_array_start:
    ; Start of array literal
    mov r15, 1
    jmp .copy_char

.start_string_single:
    mov r11, 1
    jmp .copy_char

.start_string_double:
    mov r11, 2
    jmp .copy_char

.start_string_template:
    mov r11, 3
    jmp .copy_char

.copy_char:
    mov [rdi], al
    inc rdi
    mov r14, rax                ; Save last char
    jmp .next_char

.next_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.in_string:
    ; In string mode, copy character WITHOUT minifying
    mov [rdi], al
    inc rdi
    mov r14, rax                ; Save last char
    
    ; Handle escape sequences
    cmp r13, 1
    je .reset_escape
    
    cmp al, '\'
    je .set_escape
    
    ; Check for end of string based on type
    cmp r11, 1
    je .check_single_quote
    cmp r11, 2
    je .check_double_quote
    cmp r11, 3
    je .check_backtick
    
    jmp .next_char

.check_single_quote:
    cmp al, "'"
    jne .next_char
    xor r11, r11
    jmp .next_char

.check_double_quote:
    cmp al, '"'
    jne .next_char
    xor r11, r11
    jmp .next_char

.check_backtick:
    cmp al, '`'
    jne .next_char
    xor r11, r11
    jmp .next_char

.set_escape:
    mov r13, 1
    jmp .next_char

.reset_escape:
    mov r13, 0
    jmp .next_char

.start_line_comment:
    xor r14, r14                ; Reset last char for comment
    mov r12, 1
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.start_block_comment:
    xor r14, r14                ; Reset last char for comment
    mov r12, 2
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.in_comment:
    cmp r12, 1
    je .line_comment
    cmp r12, 2
    je .block_comment
    jmp .next_char

.line_comment:
    cmp al, 0x0A
    jne .skip_comment_char
    xor r12, r12
.skip_comment_char:
    inc rsi
    dec rcx
    jmp .minify_loop

.block_comment:
    cmp al, '*'
    jne .skip_comment_char
    cmp rcx, 1
    je .skip_comment_char
    mov bl, [rsi + 1]
    cmp bl, '/'
    jne .skip_comment_char
    xor r12, r12
    add rsi, 2
    sub rcx, 2
    jmp .minify_loop

.minify_done:
    ; Calculate output length
    mov r11, rdi
    lea rdi, [output_buffer]
    sub r11, rdi
    
    ; Write output file
    mov rax, 1
    mov rdi, r10
    mov rsi, output_buffer
    mov rdx, r11
    syscall
    cmp rax, 0
    jl .error_write
    
    ; Close output file
    mov rax, 3
    mov rdi, r10
    syscall
    
    ; Clean exit
    mov rax, 60
    xor rdi, rdi
    syscall

; ========== HELPER FUNCTIONS ==========

.is_whitespace:
    cmp al, ' '
    je .is_ws_yes
    cmp al, 0x09
    je .is_ws_yes
    cmp al, 0x0A
    je .is_ws_yes
    cmp al, 0x0D
    je .is_ws_yes
    clc
    ret
.is_ws_yes:
    stc
    ret

.is_identifier_char:
    cmp bl, '0'
    jb .check_letters_id
    cmp bl, '9'
    jbe .is_id_yes
.check_letters_id:
    cmp bl, 'A'
    jb .check_lower_id
    cmp bl, 'Z'
    jbe .is_id_yes
.check_lower_id:
    cmp bl, 'a'
    jb .check_special_id
    cmp bl, 'z'
    jbe .is_id_yes
.check_special_id:
    cmp bl, '_'
    je .is_id_yes
    cmp bl, '$'
    je .is_id_yes
    clc
    ret
.is_id_yes:
    stc
    ret

.is_identifier_char_al:
    ; Check if character in AL is identifier char
    cmp al, '0'
    jb .check_letters_al
    cmp al, '9'
    jbe .is_id_yes_al
.check_letters_al:
    cmp al, 'A'
    jb .check_lower_al
    cmp al, 'Z'
    jbe .is_id_yes_al
.check_lower_al:
    cmp al, 'a'
    jb .check_special_al
    cmp al, 'z'
    jbe .is_id_yes_al
.check_special_al:
    cmp al, '_'
    je .is_id_yes_al
    cmp al, '$'
    je .is_id_yes_al
    clc
    ret
.is_id_yes_al:
    stc
    ret

; ========== ERROR HANDLERS ==========
.error_args:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_args]
    mov rdx, 37
    syscall
    jmp .exit_with_error

.error_open_input:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_open_input]
    mov rdx, 32
    syscall
    jmp .exit_with_error

.error_open_output:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_open_output]
    mov rdx, 33
    syscall
    jmp .exit_with_error

.error_read:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_read]
    mov rdx, 30
    syscall
    jmp .exit_with_error

.error_write:
    mov rax, 1
    mov rdi, 2
    lea rsi, [error_write]
    mov rdx, 31
    syscall
    jmp .exit_with_error

.exit_with_error:
    mov rax, 60
    mov rdi, 1
    syscall
