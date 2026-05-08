section .data
    arch_output db "../arch_output", 0
    chain_dir db "./chain/", 0
    js_dir db "./js/", 0
    basm_script db "../basm/basm.sh", 0
    chain_file db "./chain/chain", 0
    call_file db "./js/call", 0
    let_file db "./js/let", 0
    const_file db "./js/const", 0
    var_file db "./js/var", 0
    
    ; Tags
    js_start db "<js-start>", 0
    js_end db "<js-end>", 0
    chain_start db "<chain-start>", 0
    chain_end db "<chain-end>", 0
    
    ; Error messages
    open_error db "Error opening arch_output", 10, 0
    read_error db "Error reading arch_output", 10, 0
    create_error db "Error creating file", 10, 0
    exec_error db "Error executing basm.sh", 10, 0
    
    newline db 10, 0
    space db " ", 0
    
    ; Strings for comparison
    let_str db "let", 0
    const_str db "const", 0
    var_str db "var", 0
    
    ; Buffers
    buffer times 4096 db 0
    line_buffer times 1024 db 0
    content_buffer times 4096 db 0
    temp_path times 256 db 0
    command times 512 db 0
    filename times 256 db 0
    temp_method_name times 256 db 0
    
    fd dq 0
    in_chain dq 0
    chain_nesting dq 0

section .text
    global _start
    
_start:
    ; Open arch_output file
    mov rax, 2          ; sys_open
    mov rdi, arch_output
    mov rsi, 0          ; O_RDONLY
    mov rdx, 0
    syscall
    
    cmp rax, 0
    jl .open_error
    mov [fd], rax
    
    ; Main processing loop
.main_loop:
    ; Read a line
    mov rdi, [fd]
    mov rsi, line_buffer
    mov rdx, 1024
    call read_line
    
    cmp rax, 0
    je .close_file      ; EOF
    
    ; Check if we're inside a chain
    mov rax, [in_chain]
    cmp rax, 0
    jne .process_chain
    
    ; Not in chain, check for tags
    mov rdi, line_buffer
    mov rsi, js_start
    call find_tag
    cmp rax, 0
    jne .process_js
    
    mov rdi, line_buffer
    mov rsi, chain_start
    call find_tag
    cmp rax, 0
    jne .start_chain
    
    jmp .main_loop
    
.process_js:
    ; Extract JS content
    mov rdi, line_buffer
    call extract_js_content
    ; rax now points to content in content_buffer
    
    ; Check if it's let/const/var
    mov rdi, rax
    call check_declaration
    cmp rax, 0
    je .not_declaration
    
    ; Handle declaration based on type
    cmp rax, 2
    je .handle_let
    cmp rax, 3
    je .handle_const
    cmp rax, 4
    je .handle_var
    
.not_declaration:
    ; Check if it's a method call
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    call check_method
    cmp rax, 0
    je .handle_custom
    
    ; Handle method
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    call handle_method
    jmp .main_loop
    
.handle_custom:
    ; Custom declaration - use call.asm
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    mov rsi, call_file
    call create_and_execute
    jmp .main_loop
    
.handle_let:
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    mov rsi, let_file
    call create_and_execute
    jmp .main_loop
    
.handle_const:
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    mov rsi, const_file
    call create_and_execute
    jmp .main_loop
    
.handle_var:
    mov rdi, line_buffer
    call extract_js_content
    mov rdi, rax
    mov rsi, var_file
    call create_and_execute
    jmp .main_loop
    
.start_chain:
    ; Start collecting chain content
    mov qword [in_chain], 1
    mov qword [chain_nesting], 1
    
    ; Initialize content buffer
    mov rdi, content_buffer
    mov rsi, line_buffer
    call strcpy
    
    ; Add newline
    mov rdi, content_buffer
    call strlen
    lea rdi, [content_buffer + rax]
    mov rsi, newline
    call strcpy
    
    jmp .main_loop
    
.process_chain:
    ; Add line to chain buffer
    mov rdi, content_buffer
    call strlen
    lea rdi, [content_buffer + rax]
    mov rsi, line_buffer
    call strcpy
    
    ; Add newline
    mov rdi, content_buffer
    call strlen
    lea rdi, [content_buffer + rax]
    mov rsi, newline
    call strcpy
    
    ; Check for nested chain start
    mov rdi, line_buffer
    mov rsi, chain_start
    call find_tag
    cmp rax, 0
    je .check_chain_end
    
    ; Increase nesting
    mov rax, [chain_nesting]
    inc rax
    mov [chain_nesting], rax
    jmp .main_loop
    
.check_chain_end:
    mov rdi, line_buffer
    mov rsi, chain_end
    call find_tag
    cmp rax, 0
    je .main_loop
    
    ; Decrease nesting
    mov rax, [chain_nesting]
    dec rax
    mov [chain_nesting], rax
    cmp rax, 0
    jne .main_loop
    
    ; Chain ended, process it
    mov rdi, content_buffer
    mov rsi, chain_file
    call create_and_execute
    
    ; Reset chain state
    mov qword [in_chain], 0
    mov byte [content_buffer], 0  ; Clear buffer
    jmp .main_loop
    
.close_file:
    mov rax, 3          ; sys_close
    mov rdi, [fd]
    syscall
    
    ; Exit
    mov rax, 60         ; sys_exit
    xor rdi, rdi
    syscall
    
.open_error:
    mov rax, 1          ; sys_write
    mov rdi, 1
    mov rsi, open_error
    mov rdx, 26
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; ============================================
; Helper Functions
; ============================================

; Function: read_line
; Reads a line from file descriptor
; Input: rdi = fd, rsi = buffer
; Output: rax = bytes read (0 for EOF)
read_line:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov rbx, rdi        ; fd
    mov r12, rsi        ; buffer
    xor r13, r13        ; byte count
    
.read_char:
    ; Read one character
    mov rax, 0          ; sys_read
    mov rdi, rbx
    lea rsi, [rsp-1]    ; temp buffer on stack
    mov rdx, 1
    syscall
    
    cmp rax, 0
    jle .eof
    
    ; Check for newline
    mov al, [rsp-1]
    cmp al, 10
    je .line_end
    
    ; Store character
    mov [r12 + r13], al
    inc r13
    cmp r13, 1023
    jl .read_char
    
.line_end:
    mov byte [r12 + r13], 0
    mov rax, r13        ; return length
    jmp .done
    
.eof:
    mov byte [r12], 0
    xor rax, rax
    
.done:
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: find_tag
; Finds tag in line
; Input: rdi = line, rsi = tag
; Output: rax = pointer to tag or 0 if not found
find_tag:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov rbx, rdi        ; line
    mov r12, rsi        ; tag
    
    ; Get tag length
    mov rdi, r12
    call strlen
    mov r13, rax        ; tag length
    
    ; If line is empty, return 0
    cmp byte [rbx], 0
    je .not_found
    
.search_loop:
    ; Check if we have enough characters left
    mov rdi, rbx
    call strlen
    cmp rax, r13
    jl .not_found
    
    ; Compare current position with tag
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call strncmp
    cmp rax, 0
    je .found
    
    ; Move to next character
    inc rbx
    jmp .search_loop
    
.found:
    mov rax, rbx
    jmp .done
    
.not_found:
    xor rax, rax
    
.done:
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: extract_js_content
; Extracts content between <js-start> and <js-end>
; Input: rdi = line buffer
; Output: rax = pointer to content in content_buffer
extract_js_content:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov rbx, rdi        ; line buffer
    
    ; Find js_start
    mov rdi, rbx
    mov rsi, js_start
    call find_tag
    cmp rax, 0
    je .empty
    mov r12, rax        ; save position
    
    ; Skip js_start tag
    mov rdi, js_start
    call strlen
    add r12, rax        ; skip js_start
    
    ; Find js_end from this position
    mov rdi, r12
    mov rsi, js_end
    call find_tag
    cmp rax, 0
    je .empty
    mov r13, rax        ; position of js_end
    
    ; Calculate content length
    mov rax, r13
    sub rax, r12
    
    ; Copy to content_buffer
    mov rdi, content_buffer
    mov rsi, r12
    mov rdx, rax
    call strncpy
    
    ; Null terminate
    mov byte [content_buffer + rax], 0
    
    ; Trim leading/trailing spaces
    mov rdi, content_buffer
    call trim_spaces
    
    mov rax, content_buffer
    jmp .done
    
.empty:
    mov byte [content_buffer], 0
    mov rax, content_buffer
    
.done:
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: check_declaration
; Checks if content starts with let/const/var
; Input: rdi = content
; Output: rax = 0 (not), 2 (let), 3 (const), 4 (var)
check_declaration:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi
    
    ; Skip leading spaces
.skip_spaces:
    mov al, [rbx]
    cmp al, ' '
    jne .check_let
    inc rbx
    jmp .skip_spaces
    
.check_let:
    ; Check for "let"
    mov rdi, rbx
    mov rsi, let_str
    mov rdx, 3
    call strncmp
    cmp rax, 0
    jne .check_const
    
    ; Check that next character is space
    mov al, [rbx + 3]
    cmp al, ' '
    je .is_let
    cmp al, 0
    je .is_let
    
.check_const:
    ; Check for "const"
    mov rdi, rbx
    mov rsi, const_str
    mov rdx, 5
    call strncmp
    cmp rax, 0
    jne .check_var
    
    ; Check that next character is space
    mov al, [rbx + 5]
    cmp al, ' '
    je .is_const
    cmp al, 0
    je .is_const
    
.check_var:
    ; Check for "var"
    mov rdi, rbx
    mov rsi, var_str
    mov rdx, 3
    call strncmp
    cmp rax, 0
    jne .not_declaration
    
    ; Check that next character is space
    mov al, [rbx + 3]
    cmp al, ' '
    je .is_var
    cmp al, 0
    je .is_var
    
.not_declaration:
    xor rax, rax
    jmp .done
    
.is_let:
    mov rax, 2
    jmp .done
.is_const:
    mov rax, 3
    jmp .done
.is_var:
    mov rax, 4
    
.done:
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: check_method
; Checks if content is a method call (has dot and parentheses)
; Input: rdi = content
; Output: rax = 1 if method, 0 otherwise
check_method:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi
    
    ; Skip leading spaces
.skip_spaces:
    mov al, [rbx]
    cmp al, 0
    je .not_method
    cmp al, ' '
    jne .start_check
    inc rbx
    jmp .skip_spaces
    
.start_check:
    ; Look for dot
    mov rdi, rbx
    mov al, '.'
    call strchr
    cmp rax, 0
    je .not_method
    
    ; Look for parentheses
    mov rdi, rbx
    mov al, '('
    call strchr
    cmp rax, 0
    je .not_method
    
    mov rax, 1
    jmp .done
    
.not_method:
    xor rax, rax
    
.done:
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: handle_method
; Handles method calls like console.log()
; Input: rdi = content
handle_method:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    mov rbx, rdi        ; content
    
    ; Extract method name (last part before parentheses)
    mov rdi, rbx
    call extract_method_name
    mov r12, rax        ; method name
    
    ; Build path to method file
    mov rdi, temp_path
    mov rsi, js_dir
    call strcpy
    
    ; Extract first part (directory name)
    mov rdi, rbx
    call extract_first_part
    mov r13, rax        ; first part
    
    ; Check if it's console
    mov rdi, r13
    mov rsi, console_str
    call strcmp
    cmp rax, 0
    je .is_console
    
    ; Check if it's process
    mov rdi, r13
    mov rsi, process_str
    call strcmp
    cmp rax, 0
    je .is_process
    
    ; Default: use call.asm
    mov rdi, rbx
    mov rsi, call_file
    call create_and_execute
    jmp .done
    
.is_console:
    ; Build path: ./js/console/<method>.asm
    mov rdi, temp_path
    mov rsi, console_dir
    call strcat
    
    ; Append method name
    mov rdi, temp_path
    mov rsi, r12
    call strcat
    
    ; Create and execute
    mov rdi, rbx
    mov rsi, temp_path
    call create_and_execute
    jmp .done
    
.is_process:
    ; Build path: ./js/process/<method>.asm
    mov rdi, temp_path
    mov rsi, process_dir
    call strcat
    
    ; Append method name
    mov rdi, temp_path
    mov rsi, r12
    call strcat
    
    ; Create and execute
    mov rdi, rbx
    mov rsi, temp_path
    call create_and_execute
    
.done:
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: extract_method_name
; Extracts method name from content (e.g., "log" from "console.log()")
; Input: rdi = content
; Output: rax = pointer to method name in temp_method_name
extract_method_name:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi
    
    ; Find last dot before parentheses
    mov rdi, rbx
    mov al, '.'
    call strrchr_before_paren
    cmp rax, 0
    je .no_method
    
    inc rax             ; Skip the dot
    
    ; Copy to temp_method_name
    mov rdi, temp_method_name
    mov rsi, rax
    call strcpy
    
    ; Remove parentheses and following characters
    mov rdi, temp_method_name
    mov al, '('
    call strchr
    cmp rax, 0
    je .done
    mov byte [rax], 0   ; Null terminate at '('
    
.done:
    mov rax, temp_method_name
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
    
.no_method:
    mov byte [temp_method_name], 0
    mov rax, temp_method_name
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: extract_first_part
; Extracts first part before dot
; Input: rdi = content
; Output: rax = pointer to first part in filename
extract_first_part:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi
    
    ; Skip leading spaces
.skip_spaces:
    mov al, [rbx]
    cmp al, ' '
    jne .start_copy
    inc rbx
    jmp .skip_spaces
    
.start_copy:
    mov rdi, filename
    xor rcx, rcx
    
.copy_loop:
    mov al, [rbx]
    cmp al, 0
    je .end
    cmp al, '.'
    je .end
    cmp al, '('
    je .end
    cmp al, ' '
    je .end
    
    mov [rdi + rcx], al
    inc rbx
    inc rcx
    jmp .copy_loop
    
.end:
    mov byte [rdi + rcx], 0
    mov rax, filename
    
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: create_and_execute
; Creates file and executes .asm via basm.sh
; Input: rdi = content, rsi = file path (without extension)
create_and_execute:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    
    mov rbx, rdi        ; content
    mov r12, rsi        ; file path
    
    ; Create file
    mov rax, 2          ; sys_open
    mov rdi, r12
    mov rsi, 0x241      ; O_CREAT|O_WRONLY|O_TRUNC
    mov rdx, 0644o      ; permissions
    syscall
    
    cmp rax, 0
    jl .create_err
    
    mov r13, rax        ; file descriptor
    
    ; Get content length
    mov rdi, rbx
    call strlen
    mov r14, rax        ; length
    
    ; Write content
    mov rax, 1          ; sys_write
    mov rdi, r13
    mov rsi, rbx
    mov rdx, r14
    syscall
    
    ; Close file
    mov rax, 3          ; sys_close
    mov rdi, r13
    syscall
    
    ; Build command: ../basm/basm.sh <file.asm>
    mov rdi, command
    mov rsi, basm_script
    call strcpy
    
    mov rdi, command
    mov rsi, space
    call strcat
    
    ; Append .asm extension to filename
    mov rdi, temp_path
    mov rsi, r12
    call strcpy
    
    mov rdi, temp_path
    mov rsi, asm_ext
    call strcat
    
    mov rdi, command
    mov rsi, temp_path
    call strcat
    
    ; Execute command
    call system_exec
    
    jmp .done
    
.create_err:
    ; Write error message
    mov rax, 1
    mov rdi, 1
    mov rsi, create_error
    mov rdx, 20
    syscall
    
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; ============================================
; String utility functions
; ============================================

; Function: strlen
; Input: rdi = string
; Output: rax = length
strlen:
    push rbp
    mov rbp, rsp
    xor rax, rax
    
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; Function: strcpy
; Input: rdi = dest, rsi = src
strcpy:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi        ; save dest
    
.loop:
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    cmp al, 0
    jne .loop
    
    mov rax, rbx        ; return dest
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: strcat
; Input: rdi = dest, rsi = src
strcat:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi        ; save dest
    
    ; Find end of dest
.find_end:
    cmp byte [rdi], 0
    je .copy
    inc rdi
    jmp .find_end
    
.copy:
    ; Copy src to end
.loop:
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    cmp al, 0
    jne .loop
    
    mov rax, rbx        ; return dest
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: strncmp
; Input: rdi = s1, rsi = s2, rdx = n
; Output: rax = 0 if equal, non-zero otherwise
strncmp:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    mov rbx, rdi
    mov r12, rsi
    xor rcx, rcx
    
.loop:
    cmp rcx, rdx
    je .equal
    
    mov al, [rbx + rcx]
    mov dl, [r12 + rcx]
    cmp al, dl
    jne .not_equal
    
    cmp al, 0
    je .equal
    
    inc rcx
    jmp .loop
    
.equal:
    xor rax, rax
    jmp .done
    
.not_equal:
    movzx rax, al
    movzx rdx, dl
    sub rax, rdx
    
.done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: strcmp
; Input: rdi = s1, rsi = s2
; Output: rax = 0 if equal, non-zero otherwise
strcmp:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    mov rbx, rdi
    mov r12, rsi
    
.loop:
    mov al, [rbx]
    mov dl, [r12]
    cmp al, dl
    jne .not_equal
    
    cmp al, 0
    je .equal
    
    inc rbx
    inc r12
    jmp .loop
    
.equal:
    xor rax, rax
    jmp .done
    
.not_equal:
    movzx rax, al
    movzx rdx, dl
    sub rax, rdx
    
.done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: strncpy
; Input: rdi = dest, rsi = src, rdx = n
strncpy:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    mov rbx, rdi        ; dest
    mov r12, rsi        ; src
    xor rcx, rcx        ; counter
    
.loop:
    cmp rcx, rdx
    je .done
    
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    
    cmp al, 0
    je .done
    
    inc rcx
    jmp .loop
    
.done:
    mov rax, rbx
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: strchr
; Input: rdi = string, al = char
; Output: rax = pointer to char or 0
strchr:
    push rbp
    mov rbp, rsp
    
.loop:
    mov dl, [rdi]
    cmp dl, 0
    je .not_found
    cmp dl, al
    je .found
    inc rdi
    jmp .loop
    
.found:
    mov rax, rdi
    jmp .done
    
.not_found:
    xor rax, rax
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; Function: strrchr_before_paren
; Finds last dot before parentheses
; Input: rdi = string
; Output: rax = pointer to last dot or 0
strrchr_before_paren:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, rdi
    xor rax, rax        ; last found dot
    
.scan:
    mov cl, [rbx]
    cmp cl, 0
    je .done
    cmp cl, '('
    je .done
    cmp cl, ')'
    je .done
    
    cmp cl, '.'
    jne .next
    mov rax, rbx        ; update last dot
    
.next:
    inc rbx
    jmp .scan
    
.done:
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: trim_spaces
; Trims leading and trailing spaces
; Input: rdi = string
trim_spaces:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    mov rbx, rdi
    
    ; Skip leading spaces
.skip_leading:
    mov al, [rbx]
    cmp al, ' '
    jne .copy_start
    inc rbx
    jmp .skip_leading
    
.copy_start:
    ; If we're at the same position, no leading spaces
    cmp rbx, rdi
    je .trim_trailing
    
    ; Copy rest of string
    mov r12, rdi        ; destination
    
.copy_loop:
    mov al, [rbx]
    mov [r12], al
    cmp al, 0
    je .trim_trailing_dest
    inc rbx
    inc r12
    jmp .copy_loop
    
.trim_trailing_dest:
    ; Trim trailing spaces from destination
    mov rdi, r12
    jmp .trim_trailing_from
    
.trim_trailing:
    ; Find end of string
    mov rdi, rbx
    call strlen
    lea r12, [rbx + rax] ; points to null terminator
    
.trim_trailing_from:
    ; Move back while there are spaces
.trim_loop:
    dec r12
    cmp r12, rdi
    jl .done
    mov al, [r12]
    cmp al, ' '
    jne .not_space
    mov byte [r12], 0
    jmp .trim_loop
    
.not_space:
    inc r12
    mov byte [r12], 0
    
.done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Function: system_exec
; Executes command via fork/exec
system_exec:
    push rbp
    mov rbp, rsp
    
    ; Fork
    mov rax, 57         ; sys_fork
    syscall
    
    cmp rax, 0
    jl .fork_error
    jg .parent
    
    ; Child process - execute basm.sh
    ; Prepare arguments
    mov rdi, basm_script
    lea rsi, [argv]     ; argv array
    mov rdx, 0          ; envp
    
    mov rax, 59         ; sys_execve
    syscall
    
    ; If execve fails
    mov rax, 60
    mov rdi, 1
    syscall
    
.parent:
    ; Wait for child
    push rax            ; save pid
    
    mov rdi, rax
    xor rsi, rsi
    xor rdx, rdx
    xor r10, r10
    mov rax, 61         ; sys_wait4
    syscall
    
    pop rax             ; restore pid
    
    jmp .done
    
.fork_error:
    ; Write error
    mov rax, 1
    mov rdi, 1
    mov rsi, exec_error
    mov rdx, 24
    syscall
    
.done:
    mov rsp, rbp
    pop rbp
    ret

section .data
    ; Additional strings
    console_str db "console", 0
    process_str db "process", 0
    console_dir db "console/", 0
    process_dir db "process/", 0
    asm_ext db ".asm", 0
    
    ; For execve
    argv dq basm_script, temp_path, 0