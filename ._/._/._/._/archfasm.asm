format ELF64 executable

; ------------------------------------------------------------
; SYSTEM CALL CONSTANTS
; ------------------------------------------------------------
SYS_READ   = 0
SYS_WRITE  = 1
SYS_OPEN   = 2
SYS_CLOSE  = 3
SYS_LSEEK  = 8
SYS_EXIT   = 60

O_RDONLY   = 0
O_WRONLY   = 1
O_CREAT    = 64
O_TRUNC    = 512

; ------------------------------------------------------------
; MACROS FOR BETTER READABILITY
; ------------------------------------------------------------
macro syscall1 number, a {
    mov rax, number
    mov rdi, a
    syscall
}

macro syscall2 number, a, b {
    mov rax, number
    mov rdi, a
    mov rsi, b
    syscall
}

macro syscall3 number, a, b, c {
    mov rax, number
    mov rdi, a
    mov rsi, b
    mov rdx, c
    syscall
}

macro zero_memory ptr, size {
    push rdi
    push rcx
    mov rdi, ptr
    mov rcx, size
    xor al, al
    rep stosb
    pop rcx
    pop rdi
}

; ------------------------------------------------------------
; START OF PROGRAM
; ------------------------------------------------------------
entry _start

segment readable executable

_start:
    pop rcx                     ; Get argc
    cmp rcx, 2
    jl .error_no_file
    
    pop rdi                     ; Skip argv[0] (program name)
    pop rdi                     ; Get argv[1] (input filename)
    
    ; Open input file
    syscall3 SYS_OPEN, rdi, O_RDONLY, 0
    cmp rax, 0
    jl .error_open
    mov [file_handle], rax
    
    ; Get file size using lseek
    syscall3 SYS_LSEEK, [file_handle], 0, 2  ; SEEK_END
    cmp rax, 0
    jl .error_read
    mov [file_size], rax
    
    ; Seek back to start
    syscall3 SYS_LSEEK, [file_handle], 0, 0  ; SEEK_SET
    cmp rax, 0
    jl .error_read
    
    ; Check if file is too large
    cmp qword [file_size], 65536
    jg .error_read
    
    ; Read file
    syscall3 SYS_READ, [file_handle], file_buffer, [file_size]
    cmp rax, 0
    jl .error_read
    
    ; Close input file
    syscall1 SYS_CLOSE, [file_handle]
    
    ; Create output file (overwrite if exists)
    mov rsi, O_CREAT or O_WRONLY or O_TRUNC
    mov rdx, 0644o                ; rw-r--r-- permissions in octal
    syscall3 SYS_OPEN, output_filename, rsi, rdx
    cmp rax, 0
    jl .error_create
    mov [output_handle], rax
    
    ; Process file
    call process_file
    
    ; Ensure all data is written to file
    call write_to_file
    
    ; Close output file
    syscall1 SYS_CLOSE, [output_handle]
    
    jmp .exit_success

.error_no_file:
    mov rsi, err_no_file
    call print_string
    mov rdi, 1
    jmp .exit_now

.error_open:
    mov rsi, err_open
    call print_string
    mov rdi, 2
    jmp .exit_now

.error_read:
    mov rsi, err_read
    call print_string
    mov rdi, 3
    jmp .exit_now

.error_create:
    mov rsi, err_create
    call print_string
    mov rdi, 4
    jmp .exit_now

.error_write:
    mov rsi, err_write
    call print_string
    mov rdi, 5

.exit_success:
    mov rdi, 0

.exit_now:
    syscall1 SYS_EXIT, rdi

; ------------------------------------------------------------
; GET NEXT COLOR
; ------------------------------------------------------------
get_next_color:
    push rbx
    mov ebx, [color_index]
    cmp ebx, 4
    jl .index_ok
    xor ebx, ebx
    mov [color_index], ebx
.index_ok:
    mov rax, [color_array + rbx*8]
    mov [current_color], rax
    inc ebx
    cmp ebx, 4
    jl .no_wrap
    xor ebx, ebx
.no_wrap:
    mov [color_index], ebx
    pop rbx
    ret

; ------------------------------------------------------------
; GET CHAIN COLOR
; ------------------------------------------------------------
get_chain_color:
    push rax
    mov rax, [current_color]
    mov [chain_color], rax
    pop rax
    ret

; ------------------------------------------------------------
; WRITE TO FILE - Write clean buffer to output file
; ------------------------------------------------------------
write_to_file:
    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    
    ; Check if there's anything to write
    mov rcx, [clean_pos]
    test rcx, rcx
    jz .write_done
    
    ; Write to file
    syscall3 SYS_WRITE, [output_handle], clean_buffer, rcx
    cmp rax, 0
    jl .write_error
    
    ; Reset buffer
    mov qword [clean_pos], 0
    zero_memory clean_buffer, 2048
    
.write_done:
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

.write_error:
    ; Clean up and exit on write error
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax
    mov rdi, 5
    jmp _start.exit_now

; ------------------------------------------------------------
; APPEND TO CLEAN BUFFER - Add string without color codes
; ------------------------------------------------------------
append_to_clean_buffer:
    push rsi
    push rdi
    push rcx
    push rax
    
    mov rsi, rdi          ; Source string
    mov rdi, clean_buffer
    add rdi, [clean_pos]
    
.copy_loop:
    mov al, [rsi]
    test al, al
    jz .copy_done
    
    ; Store character
    mov [rdi], al
    inc rsi
    inc rdi
    inc qword [clean_pos]
    
    ; Check buffer size
    mov rax, [clean_pos]
    cmp rax, 2047
    jl .copy_loop
    
    ; Buffer full, write to file
    call write_to_file
    
    ; Reset for next copy
    mov rdi, clean_buffer
    add rdi, [clean_pos]
    jmp .copy_loop

.copy_done:
    pop rax
    pop rcx
    pop rdi
    pop rsi
    ret

; ------------------------------------------------------------
; PRINT STRING WITH FILE OUTPUT - Terminal with colors, file without
; ------------------------------------------------------------
print_string:
    push rax
    push rdi
    push rsi
    push rdx
    push rcx
    
    ; Save the string pointer
    mov rdi, rsi
    
    ; Write to file (clean output) - only if not a color code
    ; Check if this is a color escape sequence
    cmp byte [rdi], 1Bh
    je .skip_file_write  ; Skip writing color codes to file
    
    ; Write to file (clean output)
    mov rsi, rdi
    call append_to_clean_buffer
    
.skip_file_write:
    ; Write to terminal (with colors)
    mov rsi, rdi
    call string_length
    mov rdx, rax
    mov rsi, rdi
    
    test rdx, rdx
    jz .print_done
    
    syscall3 SYS_WRITE, 1, rsi, rdx

.print_done:
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; ------------------------------------------------------------
; PROCESS FILE - Main loop
; ------------------------------------------------------------
process_file:
    push r12
    push r13
    
    mov r12, file_buffer
    mov r13, file_buffer
    add r13, [file_size]
    
    ; Initialize state
    mov dword [paren_depth], 0
    mov dword [brace_depth], 0
    mov dword [bracket_depth], 0
    mov dword [chain_depth], 0
    mov dword [chain_stack_ptr], 0
    
    ; Clear state variables
    zero_memory in_string, 1
    zero_memory in_template, 1
    zero_memory in_comment, 1
    zero_memory last_char, 1
    zero_memory skip_next_space, 1
    zero_memory in_block, 1
    zero_memory block_started, 1
    zero_memory empty_statement, 1
    zero_memory arrow_pending, 1
    zero_memory at_block_start, 1
    zero_memory in_chain_block, 1
    zero_memory expecting_block, 1
    zero_memory block_declaration, 1
    zero_memory in_block_stmt, 1
    zero_memory current_keyword, 1
    zero_memory stmt_started, 1
    
    ; Clear buffers
    zero_memory current_stmt, 1024
    zero_memory block_stmt, 1024
    zero_memory keyword_buffer, 16
    
    mov dword [color_index], 0
    mov qword [clean_pos], 0
    
    ; Get first color
    call get_next_color

.process_char:
    cmp r12, r13
    jge .process_complete
    
    ; Get current character
    mov al, [r12]
    mov [char_buffer], al
    inc r12
    
    ; Skip whitespace at beginning
    cmp byte [stmt_started], 0
    jne .not_start_whitespace
    
    cmp al, ' '
    je .skip_char
    cmp al, 9
    je .skip_char
    cmp al, 10
    je .skip_char
    cmp al, 13
    je .skip_char
    
    mov byte [stmt_started], 1

.not_start_whitespace:
    ; Handle special contexts
    cmp byte [in_string], 1
    je .process_in_string
    cmp byte [in_template], 1
    je .process_in_template
    cmp byte [in_comment], 1
    je .process_single_comment
    cmp byte [in_comment], 2
    je .process_multi_comment
    
    ; Handle special characters
    cmp al, '"'
    je .handle_dquote
    cmp al, '`'
    je .handle_backtick
    cmp al, '/'
    je .handle_slash
    cmp al, ' '
    je .handle_space_char
    cmp al, 9
    je .handle_space_char
    cmp al, 10
    je .handle_newline_char
    cmp al, 13
    je .handle_newline_char
    cmp al, ';'
    je .handle_semicolon_char
    cmp al, '{'
    je .handle_open_brace
    cmp al, '}'
    je .handle_close_brace
    cmp al, '('
    je .handle_open_paren
    cmp al, ')'
    je .handle_close_paren
    cmp al, '['
    je .handle_open_bracket
    cmp al, ']'
    je .handle_close_bracket
    cmp al, '='
    je .handle_equals_char
    cmp al, ':'
    je .handle_colon_char
    cmp al, '>'
    je .handle_greater
    
    ; Regular character
    jmp .handle_regular_char

.skip_char:
    jmp .process_char

; ------------------------------------------------------------
; CHARACTER HANDLERS
; ------------------------------------------------------------
.handle_dquote:
    call process_start_string
    jmp .process_char

.handle_backtick:
    call process_start_template
    jmp .process_char

.handle_slash:
    call check_for_comment
    jmp .process_char

.handle_space_char:
    call process_space
    jmp .process_char

.handle_newline_char:
    call process_newline
    jmp .process_char

.handle_semicolon_char:
    call process_semicolon
    jmp .process_char

.handle_open_brace:
    call process_open_brace
    jmp .process_char

.handle_close_brace:
    call process_close_brace
    jmp .process_char

.handle_open_paren:
    call process_open_paren
    jmp .process_char

.handle_close_paren:
    call process_close_paren
    jmp .process_char

.handle_open_bracket:
    call process_open_bracket
    jmp .process_char

.handle_close_bracket:
    call process_close_bracket
    jmp .process_char

.handle_equals_char:
    call process_equals
    jmp .process_char

.handle_colon_char:
    call process_colon
    jmp .process_char

.handle_greater:
    call process_greater
    jmp .process_char

.handle_regular_char:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    
    ; Check if alpha char for keyword
    mov al, [char_buffer]
    cmp al, 'a'
    jl .check_upper
    cmp al, 'z'
    jle .is_alpha
.check_upper:
    cmp al, 'A'
    jl .not_alpha
    cmp al, 'Z'
    jle .is_alpha
.not_alpha:
    ; Non-alpha ends keyword - check if we had a block keyword
    call check_and_set_block_keyword
    call clear_keyword_buffer
    jmp .add_char
.is_alpha:
    call append_to_keyword_buffer

.add_char:
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    jmp .process_char

; Context handlers
.process_in_string:
    call handle_string_char
    jmp .process_char

.process_in_template:
    call handle_template_char
    jmp .process_char

.process_single_comment:
    call handle_single_line_comment
    jmp .process_char

.process_multi_comment:
    call handle_multi_line_comment
    jmp .process_char

.process_complete:
    ; Print any remaining statement
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .done_processing
    
    call check_empty_statement
    cmp byte [empty_statement], 1
    je .skip_final_print
    
    cmp byte [in_chain_block], 1
    je .print_final_in_chain
    
    call print_current_statement
    jmp .done_processing

.print_final_in_chain:
    call print_chain_statement

.skip_final_print:
    ; Don't print empty statement

.done_processing:
    ; Close any open chains (nested)
    call close_all_chains
    
    ; Write any remaining data to file
    call write_to_file
    
    pop r13
    pop r12
    ret

; ------------------------------------------------------------
; CLOSE ALL CHAINS - Close any remaining open chains
; ------------------------------------------------------------
close_all_chains:
    push rsi
.chains_loop:
    cmp dword [chain_depth], 0
    jle .all_chains_closed
    call print_chain_end_tag
    dec dword [chain_depth]
    dec dword [chain_stack_ptr]
    jmp .chains_loop
.all_chains_closed:
    pop rsi
    ret

; ------------------------------------------------------------
; PROCESSING FUNCTIONS
; ------------------------------------------------------------
process_start_string:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call clear_keyword_buffer
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    mov byte [in_string], 1
    ret

process_start_template:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call clear_keyword_buffer
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    mov byte [in_template], 1
    ret

check_for_comment:
    cmp r12, r13
    jge .not_a_comment
    
    mov bl, [r12]
    cmp bl, '/'
    je .start_single_comment
    cmp bl, '*'
    je .start_multi_comment

.not_a_comment:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call clear_keyword_buffer
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    ret

.start_single_comment:
    inc r12
    mov byte [in_comment], 1
    ret

.start_multi_comment:
    inc r12
    mov byte [in_comment], 2
    ret

process_space:
    ; Check for keyword end
    call check_and_set_block_keyword
    call clear_keyword_buffer
    
    cmp byte [skip_next_space], 1
    je .skip_space
    
    mov bl, [last_char]
    cmp bl, '('
    je .skip_space
    cmp bl, '['
    je .skip_space
    cmp bl, '{'
    je .skip_space
    cmp bl, ';'
    je .skip_space
    cmp bl, ':'
    je .skip_space
    cmp bl, ','
    je .skip_space
    
    call append_to_stmt
    mov byte [skip_next_space], 1
    mov byte [last_char], ' '
    ret

.skip_space:
    ret

process_newline:
    ; Check for keyword end
    call check_and_set_block_keyword
    call clear_keyword_buffer
    mov byte [skip_next_space], 1
    ret

process_semicolon:
    mov byte [skip_next_space], 0
    mov byte [arrow_pending], 0
    call clear_keyword_buffer
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    
    ; Check if in chain
    cmp byte [in_chain_block], 1
    je .in_chain_semicolon
    
    ; Regular semicolon at top level
    cmp dword [brace_depth], 0
    jne .done
    cmp dword [paren_depth], 0
    jne .done
    cmp dword [bracket_depth], 0
    jne .done
    cmp byte [in_block], 0
    jne .done
    
    call check_empty_statement
    cmp byte [empty_statement], 1
    je .skip_empty
    
    call print_current_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    call get_next_color
    ret

.in_chain_semicolon:
    call check_empty_statement
    cmp byte [empty_statement], 1
    je .skip_empty
    
    call print_chain_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    ret

.skip_empty:
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    mov byte [empty_statement], 0
.done:
    ret

; ============================================================
; CRITICAL FIX: OPEN BRACE HANDLING WITH NESTED CHAIN SUPPORT
; ============================================================
process_open_brace:
    mov byte [skip_next_space], 0
    mov byte [arrow_pending], 0
    mov byte [empty_statement], 0
    
    ; Check if we're in a block statement context
    cmp byte [current_keyword], 1
    je .is_block_brace
    
    ; Check if this looks like an object literal (not a block)
    mov bl, [last_char]
    cmp bl, '='
    je .likely_object
    cmp bl, ':'
    je .likely_object
    cmp bl, ','
    je .likely_object
    cmp bl, '('
    je .likely_object
    cmp bl, '['
    je .likely_object
    cmp bl, '{'
    je .likely_object
    
    ; Check if we're in expression context
    cmp dword [paren_depth], 0
    jne .likely_object
    cmp dword [bracket_depth], 0
    jne .likely_object
    
    ; At this point, it's likely a block
    jmp .is_block_brace

.likely_object:
    ; Add brace to current statement (object literal)
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    inc dword [brace_depth]
    ret

.is_block_brace:
    ; This is a block start - save current statement as block declaration
    call copy_to_block_stmt
    
    ; Clear current statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    
    ; Increase brace depth
    inc dword [brace_depth]
    
    ; Save current brace depth for chain
    mov eax, [brace_depth]
    dec eax  ; We just incremented, so save the depth before this brace
    
    ; Push onto chain stack
    mov edx, [chain_stack_ptr]
    mov [chain_brace_stack + edx*4], eax  ; Save brace depth
    mov rax, [current_color]
    mov [chain_stack + edx*8], rax        ; Save color
    
    ; Start a chain
    call start_chain
    ret

; ============================================================
; CLOSE BRACE HANDLING WITH NESTED CHAIN SUPPORT
; ============================================================
process_close_brace:
    mov byte [skip_next_space], 0
    mov byte [arrow_pending], 0
    
    ; Decrease depth
    dec dword [brace_depth]
    
    ; Check if we're in a chain
    cmp byte [in_chain_block], 1
    jne .regular_brace
    
    ; Check if this ends the current chain
    mov edx, [chain_stack_ptr]
    dec edx  ; Get index of current chain (0-based)
    mov eax, [brace_depth]
    cmp eax, [chain_brace_stack + edx*4]
    jne .nested_in_chain
    
    ; End current chain
    call end_chain
    ret

.nested_in_chain:
    ; Nested brace in chain - add to statement
    mov al, '}'
    mov [char_buffer], al
    call append_to_stmt
    mov [last_char], al
    ret

.regular_brace:
    ; Add brace to statement
    mov al, '}'
    mov [char_buffer], al
    call append_to_stmt
    mov [last_char], al
    
    ; Check if top level
    cmp dword [brace_depth], 0
    jne .done_brace

    ; Check if we're inside an array literal
    cmp dword [bracket_depth], 0
    jg .done_brace  ; Inside array - don't print yet
    
    ; Check if we're inside parentheses
    cmp dword [paren_depth], 0
    jg .done_brace  ; Inside parens - don't print yet
    
    call check_empty_statement
    cmp byte [empty_statement], 1
    je .skip_brace_print
    
    call print_current_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    call get_next_color
    ret

.skip_brace_print:
    call clear_stmt_buffer
    mov byte [stmt_started], 0
    mov byte [empty_statement], 0
.done_brace:
    ret

; ============================================================
; OTHER CHARACTER HANDLERS
; ============================================================
process_open_paren:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    inc dword [paren_depth]
    ret

process_close_paren:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    dec dword [paren_depth]
    ret

process_open_bracket:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    inc dword [bracket_depth]
    ret

process_close_bracket:
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    dec dword [bracket_depth]
    ret

process_equals:
    call clear_keyword_buffer
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    mov byte [arrow_pending], 1
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    ret

process_colon:
    call clear_keyword_buffer
    mov byte [skip_next_space], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    ret

process_greater:
    cmp byte [arrow_pending], 1
    jne .not_arrow
    
    ; Arrow function
    mov byte [arrow_pending], 0
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    ret

.not_arrow:
    mov byte [arrow_pending], 0
    mov byte [skip_next_space], 0
    mov byte [empty_statement], 0
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    ret

; ------------------------------------------------------------
; KEYWORD DETECTION FUNCTIONS
; ------------------------------------------------------------
check_and_set_block_keyword:
    push rsi
    push rdi
    
    mov rsi, keyword_buffer
    cmp byte [rsi], 0
    je .keyword_done
    
    ; Check for block keywords
    mov rdi, .if_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    mov rdi, .else_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    mov rdi, .for_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    mov rdi, .while_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    mov rdi, .function_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    mov rdi, .do_keyword
    call compare_strings_util
    test al, al
    jnz .is_block_keyword
    
    ; Not a block keyword
    mov byte [current_keyword], 0
    jmp .keyword_done

.is_block_keyword:
    mov byte [current_keyword], 1

.keyword_done:
    pop rdi
    pop rsi
    ret

.if_keyword:      db "if", 0
.else_keyword:    db "else", 0
.for_keyword:     db "for", 0
.while_keyword:   db "while", 0
.function_keyword: db "function", 0
.do_keyword:      db "do", 0

; ------------------------------------------------------------
; CONTEXT HANDLERS
; ------------------------------------------------------------
handle_string_char:
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    cmp al, '"'
    jne .string_not_done
    cmp r12, file_buffer
    jle .string_not_done
    cmp byte [r12-2], '\'
    je .string_not_done
    mov byte [in_string], 0
.string_not_done:
    ret

handle_template_char:
    call append_to_stmt
    mov al, [char_buffer]
    mov [last_char], al
    cmp al, '`'
    jne .template_not_done
    cmp r12, file_buffer
    jle .template_not_done
    cmp byte [r12-2], '\'
    je .template_not_done
    mov byte [in_template], 0
.template_not_done:
    ret

handle_single_line_comment:
    mov al, [char_buffer]
    cmp al, 10
    jne .comment_continues
    mov byte [in_comment], 0
.comment_continues:
    ret

handle_multi_line_comment:
    mov al, [char_buffer]
    cmp al, '*'
    jne .multi_comment_continues
    cmp r12, r13
    jge .multi_comment_continues
    mov bl, [r12]
    cmp bl, '/'
    jne .multi_comment_continues
    inc r12
    mov byte [in_comment], 0
.multi_comment_continues:
    ret

; ------------------------------------------------------------
; CHAIN MANAGEMENT WITH STACK SUPPORT
; ------------------------------------------------------------
start_chain:
    push rsi
    
    ; Save chain color
    call get_chain_color
    
    ; Print chain start
    mov rsi, chain_start_tag
    call print_string
    
    ; Print block declaration if any
    mov rsi, block_stmt
    call string_length
    test rax, rax
    jz .no_decl
    
    ; Print with indentation
    mov rsi, chain_tab
    call print_string
    
    mov rsi, block_stmt
    call print_string
    
    mov rsi, newline
    call print_string

.no_decl:
    ; Set chain state
    mov byte [in_chain_block], 1
    inc dword [chain_depth]
    inc dword [chain_stack_ptr]
    
    ; Clear block buffer
    call clear_block_stmt_buffer
    mov byte [current_keyword], 0  ; Reset keyword after starting chain
    
    pop rsi
    ret

end_chain:
    push rsi
    
    ; Print any remaining statement
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .nothing_to_print
    
    call check_empty_statement
    cmp byte [empty_statement], 1
    je .skip_print
    
    call print_chain_statement
    call clear_stmt_buffer
    mov byte [stmt_started], 0

.skip_print:
    mov byte [empty_statement], 0

.nothing_to_print:
    ; Print chain end
    mov rsi, chain_end_tag
    call print_string
    
    ; Reset chain state if this was the last chain
    dec dword [chain_depth]
    dec dword [chain_stack_ptr]
    
    ; Check if we're still in a chain
    cmp dword [chain_depth], 0
    jg .still_in_chain
    
    ; No more chains
    mov byte [in_chain_block], 0
    
    ; Get new color for next statements
    call get_next_color
    jmp .chain_done

.still_in_chain:
    ; We're still in a parent chain - restore its color
    mov edx, [chain_stack_ptr]
    dec edx  ; Get index of parent chain
    mov rax, [chain_stack + edx*8]
    mov [chain_color], rax

.chain_done:
    pop rsi
    ret

print_chain_end_tag:
    push rsi
    mov rsi, chain_end_tag
    call print_string
    pop rsi
    ret

; ------------------------------------------------------------
; PRINTING FUNCTIONS
; ------------------------------------------------------------
print_current_statement:
    push rbx
    push rsi
    
    ; Check if empty
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .print_done
    
    ; Trim spaces
    call trim_trailing_spaces
    
    ; Get color
    mov rbx, [current_color]
    
    ; Print opening tag with color to terminal, without color to file
    mov rsi, rbx
    call print_string
    mov rsi, js_start_tag
    call print_string
    
    ; Reset color for terminal, nothing for file
    mov rsi, reset_color_str
    call print_string
    
    ; Indentation
    mov rsi, tab
    call print_string
    
    ; Statement with color to terminal, without to file
    mov rsi, rbx
    call print_string
    mov rsi, current_stmt
    call print_string
    
    ; Reset color for terminal
    mov rsi, reset_color_str
    call print_string
    
    ; Closing indentation and tag
    mov rsi, tab
    call print_string
    
    mov rsi, rbx
    call print_string
    mov rsi, js_end_tag
    call print_string
    
    ; Reset color for terminal
    mov rsi, reset_color_str
    call print_string

.print_done:
    pop rsi
    pop rbx
    ret

print_chain_statement:
    push rbx
    push rsi
    
    ; Check if empty
    mov rsi, current_stmt
    call string_length
    test rax, rax
    jz .chain_print_done
    
    ; Trim spaces
    call trim_trailing_spaces
    
    ; Get chain color from current chain
    mov edx, [chain_stack_ptr]
    dec edx
    mov rbx, [chain_stack + edx*8]
    
    ; Double indentation for chain content
    mov rsi, chain_tab
    call print_string
    mov rsi, chain_tab
    call print_string
    
    ; Print as js statement with color to terminal, without to file
    mov rsi, rbx
    call print_string
    mov rsi, js_start_tag
    call print_string
    
    ; Reset color for terminal
    mov rsi, reset_color_str
    call print_string
    
    ; Indentation
    mov rsi, tab
    call print_string
    
    ; Statement with color to terminal, without to file
    mov rsi, rbx
    call print_string
    mov rsi, current_stmt
    call print_string
    
    ; Reset color for terminal
    mov rsi, reset_color_str
    call print_string
    
    ; Closing indentation and tag
    mov rsi, tab
    call print_string
    
    mov rsi, rbx
    call print_string
    mov rsi, js_end_tag
    call print_string
    
    ; Reset color for terminal
    mov rsi, reset_color_str
    call print_string

.chain_print_done:
    pop rsi
    pop rbx
    ret

; ------------------------------------------------------------
; KEYWORD HANDLING
; ------------------------------------------------------------
append_to_keyword_buffer:
    push rdi
    push rcx
    
    mov rdi, keyword_buffer
    xor rcx, rcx
    
.find_keyword_end:
    cmp rcx, 15
    jge .keyword_overflow
    cmp byte [rdi + rcx], 0
    je .found_keyword_end
    inc rcx
    jmp .find_keyword_end

.found_keyword_end:
    mov al, [char_buffer]
    mov [rdi + rcx], al
    inc rcx
    mov byte [rdi + rcx], 0

.keyword_overflow:
    pop rcx
    pop rdi
    ret

clear_keyword_buffer:
    push rdi
    push rcx
    
    mov rdi, keyword_buffer
    mov rcx, 16
    xor al, al
    rep stosb
    
    pop rcx
    pop rdi
    ret

compare_strings_util:
    push rsi
    push rdi

.compare_strings_loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .strings_not_equal
    test al, al
    jz .strings_equal
    inc rsi
    inc rdi
    jmp .compare_strings_loop

.strings_not_equal:
    xor al, al
    jmp .compare_done

.strings_equal:
    mov al, 1

.compare_done:
    pop rdi
    pop rsi
    ret

; ------------------------------------------------------------
; BUFFER MANAGEMENT
; ------------------------------------------------------------
copy_to_block_stmt:
    push rsi
    push rdi
    push rcx
    
    mov rsi, current_stmt
    mov rdi, block_stmt
    mov rcx, 1024

.copy_block_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jz .copy_done
    loop .copy_block_loop

.copy_done:
    pop rcx
    pop rdi
    pop rsi
    ret

clear_block_stmt_buffer:
    push rdi
    push rcx
    
    mov rdi, block_stmt
    mov rcx, 1024
    xor al, al
    rep stosb
    
    pop rcx
    pop rdi
    ret

clear_stmt_buffer:
    push rdi
    push rcx
    
    mov rdi, current_stmt
    mov rcx, 1024
    xor al, al
    rep stosb
    
    pop rcx
    pop rdi
    ret

append_to_stmt:
    push rdi
    push rcx
    
    mov rdi, current_stmt
    xor rcx, rcx

.find_stmt_end:
    cmp rcx, 1023
    jge .stmt_overflow
    cmp byte [rdi + rcx], 0
    je .found_stmt_end
    inc rcx
    jmp .find_stmt_end

.found_stmt_end:
    mov al, [char_buffer]
    mov [rdi + rcx], al
    inc rcx
    mov byte [rdi + rcx], 0

.stmt_overflow:
    pop rcx
    pop rdi
    ret

; ------------------------------------------------------------
; UTILITY FUNCTIONS
; ------------------------------------------------------------
check_empty_statement:
    push rsi
    
    mov byte [empty_statement], 1
    mov rsi, current_stmt

.empty_check_loop:
    mov al, [rsi]
    cmp al, 0
    je .empty_check_done
    
    cmp al, ' '
    je .next_empty_char
    cmp al, 9
    je .next_empty_char
    cmp al, 10
    je .next_empty_char
    cmp al, 13
    je .next_empty_char
    cmp al, ';'
    je .next_empty_char
    
    mov byte [empty_statement], 0
    jmp .empty_check_done

.next_empty_char:
    inc rsi
    jmp .empty_check_loop

.empty_check_done:
    pop rsi
    ret

trim_trailing_spaces:
    push rdi
    push rsi
    
    mov rdi, current_stmt
    call string_length
    test rax, rax
    jz .trim_done
    
    mov rsi, current_stmt
    add rsi, rax
    dec rsi

.trim_spaces_loop:
    cmp rsi, current_stmt
    jl .trim_done
    mov al, [rsi]
    cmp al, ' '
    je .remove_space
    cmp al, 9
    je .remove_space
    jmp .trim_done

.remove_space:
    mov byte [rsi], 0
    dec rsi
    jmp .trim_spaces_loop

.trim_done:
    pop rsi
    pop rdi
    ret

string_length:
    push rbx
    mov rbx, rsi
    xor rax, rax

.length_loop:
    cmp byte [rbx + rax], 0
    je .length_done
    inc rax
    jmp .length_loop

.length_done:
    pop rbx
    ret

; ------------------------------------------------------------
; DATA SECTION
; ------------------------------------------------------------
segment readable writeable

; Colors for output - alternating colors
reset_color_str   db 1Bh, "[0m", 0
color1           db 1Bh, "[1;33m", 0  ; Bright yellow
color2           db 1Bh, "[1;36m", 0  ; Bright cyan
color3           db 1Bh, "[1;32m", 0  ; Bright green
color4           db 1Bh, "[1;35m", 0  ; Bright magenta

; Tags for JavaScript instances
js_start_tag     db "<js-start>", 0
js_end_tag       db "<js-end>", 10, 0   ; Newline after closing tag
chain_start_tag  db "<chain-start>", 10, 0
chain_end_tag    db "<chain-end>", 10, 0

; Error messages
err_no_file       db "Error: No input file specified.", 10, 0
err_open          db "Error: Could not open file.", 10, 0
err_read          db "Error: Could not read file.", 10, 0
err_create        db "Error: Could not create output file.", 10, 0
err_write         db "Error: Could not write to output file.", 10, 0

; Output formatting
newline           db 10, 0
tab               db "    ", 0
chain_tab         db "    ", 0    ; Tab for chain content

; Output filename
output_filename   db "arch_output", 0

; State variables
in_string         db 0
in_template       db 0
in_comment        db 0
last_char         db 0
skip_next_space   db 0
in_block          db 0
block_started     db 0
empty_statement   db 0
arrow_pending     db 0
at_block_start    db 0
in_chain_block    db 0
expecting_block   db 0
block_declaration db 0
in_block_stmt     db 0
current_keyword   db 0
stmt_started      db 0

; Depth counters
paren_depth       dd 0
brace_depth       dd 0
bracket_depth     dd 0

; Color rotation
color_index       dd 0
color_array       dq color1, color2, color3, color4

; Buffers
current_stmt      rb 1024
block_stmt        rb 1024
char_buffer       db 0
current_color     dq 0
chain_color       dq 0

; Keyword detection
keyword_buffer    rb 16

; Stack for chain tracking (max 16 levels deep)
chain_stack       rq 16  ; Stores chain colors
chain_brace_stack rd 16  ; Stores brace depth when chain started

; Buffer for clean output (no color codes)
clean_buffer      rb 2048
clean_pos         dq 0

; File handles and sizes
file_handle       rq 1
output_handle     rq 1
file_size         rq 1
file_buffer       rb 65536
chain_depth       rd 1
chain_stack_ptr   rd 1    ; Stack pointer for chain tracking