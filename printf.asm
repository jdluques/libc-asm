global printf

default rel

; Constants
SYS_WRITE equ 1
FD_STDOUT equ 1

BUFSIZ    equ 8192

section .rodata
    null_str  db    "(null)", 0

section .bss
    io_buf    resb  BUFSIZ
    io_idx    resq  1

section .text

; ---------------------------------------------------------------------
; int printf(const char *format, ...)
; Five variadic arguments passed via registers: rsi, rdx, rcx, r8, r9
; The rest of variadic arguments passed via the stack
; Returns number of characters printed
; ---------------------------------------------------------------------
printf:
    push rbp
    mov rbp, rsp

    push r12
    push r13

    ; Save variadic arguments to stack frame
    sub rsp, 48

    mov [rbp - 40], rsi
    mov [rbp - 32], rdx
    mov [rbp - 24], rcx
    mov [rbp - 16], r8
    mov [rbp -  8], r9

    mov rsi, rdi            ; rsi = format string pointer
    xor r12, r12            ; r12 = current argument index tracker
    xor r13, r13            ; r13 = number of characters printed

.parse_loop:
    movzx rdi, byte [rsi]
    test dil, dil
    jz .done

    cmp dil, '%'
    je .handle_specifier

    call add_to_buffer

    test rax, rax
    js .error

    jmp .next_parse

.handle_specifier:
    inc rsi
    movzx rdi, byte [rsi]

.process_arg:
    cmp dil, 's'
    je .handle_str_arg
    cmp dil, 'd'
    je .handle_int_arg
    cmp dil, 'c'
    je .handle_char_arg

    cmp dil, '%'
    je .handle_percentage_literal

    ; Unknown specifier
    mov dil, '%'
    call add_to_buffer

    test rax, rax
    js .error

    movzx rdi, byte [rsi]
    call add_to_buffer
    
    test rax, rax
    js .error

    jmp .next_parse

.handle_str_arg:
    call fetch_argument
    call handle_string
    
    test rax, rax
    js .error

    jmp .next_parse
    
.handle_int_arg:
    call fetch_argument
    call handle_int
    
    test rax, rax
    js .error

    jmp .next_parse

.handle_char_arg:
    call fetch_argument
    call add_to_buffer

    test rax, rax
    js .error

    jmp .next_parse

.handle_percentage_literal:
    call add_to_buffer
    
    test rax, rax
    js .error

.next_parse:
    inc rsi
    jmp .parse_loop

.error:
    mov eax, -1
    jmp .exit

.done:
    call flush_buffer
    
    test rax, rax
    js .error

    mov rax, r13

.exit:
    add rsp, 48

    pop r13
    pop r12

    leave
    ret

; ----------------------------------------------
; --- Helper functions for argument handling ---
; ----------------------------------------------

; ---------------------------------------------------------------------
; void fetch_argument(int arg_num)
; Arguments: r12 = arg_num
; Fetches the arg_num argument for a format specifier
; ---------------------------------------------------------------------
fetch_argument:
    cmp r12, 5
    jae .fetch_from_stack

.fetch_from_regs:
    mov rdi, [rbp - 40 + r12 * 8]
    jmp .done

.fetch_from_stack:
    mov rdx, r12
    sub rdx, 5
    mov rdi, [rbp + 16 + rdx*8]

.done:
    inc r12
    ret

; ------------------------------------------------------------------------
; int handle_string(char *str)
; Arguments: rdi = str
; Adds each char of str to buffer if not null, otherwise it adds '(null)'
; Returns 0 if successful, else returns value less than 0
; ------------------------------------------------------------------------
handle_string:
    push rsi

    test rdi, rdi
    jnz .not_null

    lea rdi, [null_str]

.not_null:
    mov rsi, rdi

.loop:
    movzx rdi, byte [rsi]

    test dil, dil
    jz .done

    call add_to_buffer

    test rax, rax
    js .done

    inc rsi
    jmp .loop

.done:
    pop rsi
    ret

; ---------------------------------------------------------------------
; int handle_int(int n)
; Arguments: rdi = n
; Adds each digit of integer num to buffer, with '-' sign if negative
; Returns 0 if successful, else returns value less than 0
; ---------------------------------------------------------------------
handle_int:
    push rbp
    mov rbp, rsp
    sub rsp, 32             ; Buffer for digits

    lea r8, [rbp - 1]       ; Fill buffer backward
    mov byte [r8], 0        ; Null terminator

    mov r9, 10              ; Used for division rax / 10
    
    test rdi, rdi
    jns .positive
    
    mov ecx, 1               ; Sign tracking
    
    mov rax, rdi            ; Value to convert
    neg rax

    jmp .convert_loop

.positive:
    xor ecx, ecx
    mov rax, rdi


.convert_loop:
    xor edx, edx
    div r9                  ; rdx:rax / r9 -> rax = quotient, rdx = remainder
    add dl, '0'             ; Convert remained number to ASCII
    dec r8                  ; Move to next position in buffer
    mov [r8], dl            ; Add digit to buffer

    test rax, rax
    jnz .convert_loop

    test ecx, ecx
    jz .add_to_buffer_loop

    dec r8
    mov byte [r8], '-'      ; Add '-' to buffer

.add_to_buffer_loop:
    movzx rdi, byte [r8]

    test dil, dil
    jz .done

    call add_to_buffer

    test rax, rax
    js .done

    inc r8
    jmp .add_to_buffer_loop

.done:
    leave
    ret

; --------------------------------------------
; --- Helper functions for buffer handling ---
; --------------------------------------------

; ---------------------------------------------------------------------
; int add_to_buffer(char c)
; Arguments: dil = c
; Adds character to buffer and flushes it if full or on newline
; Returns 0 if successful, else returns value less than 0
; ---------------------------------------------------------------------
add_to_buffer:
    mov rcx, [io_idx]
    mov [io_buf + rcx], dil
    inc rcx
    mov [io_idx], rcx

    cmp rcx, BUFSIZ
    jae .force_flush

    cmp dil, 10
    je .force_flush
    
    xor eax, eax
    jmp .done

.force_flush:
    call flush_buffer
    
.done:
    ret

; ---------------------------------------------------------------------
; int flush_buffer()
; Empties the current buffer to STDOUT
; Returns 0 if successful, else returns value less than 0
; ---------------------------------------------------------------------
flush_buffer:
    push rsi

    mov rsi, io_buf         ; rsi = pointer to buffer

.loop:
    mov rdx, [io_idx]       ; rdx = length to write
    
    test rdx, rdx
    jz .success

    mov rdi, FD_STDOUT
    mov eax, SYS_WRITE
    syscall

    cmp rax, -4095
    jae .error

    add r13, rax            ; Add to global print count the written bytes
    add rsi, rax            ; Move buffer pointer forward to account for written bytes
    sub qword [io_idx], rax ; Substract from length the written bytes 
    jmp .loop

.error:
    cmp rax, -4
    je .loop
    
    jmp .done

.success:
    xor eax, eax

.done:
    pop rsi

    ret
