global malloc
global free

default rel

; +-------------------------+
; | size = x                |
; | free = 0/1              |
; | x bytes for user        |
; +-------------------------+

section .data
    SYS_BRK     equ 12
    
section .bss
    heap_start  resq 1
    heap_end    resq 1

section .text

; --------------------------------------------------------------------------------
; void malloc(size_t size)
; --------------------------------------------------------------------------------
malloc:
    push rbp
    push r12
    push r13

    ; Align size to 8 bytes for performance
    add rdi, 7
    and rdi, -8
    mov r12, rdi

    ; Init heap if first run
    mov rax, [heap_start]
    test rax, rax
    jnz .search_free_list

    ; sys_brk(0)
    mov eax, SYS_BRK
    xor rdi, rdi
    syscall

    mov [heap_start], rax
    mov [heap_end], rax

.search_free_list:
    mov rsi, [heap_start]   ; rsi = current block

.loop:
    cmp rsi, [heap_end]
    jae .grow_heap          ; Reached end of heap, need to request space

    mov rax, [rsi]          ; rax = block size
    mov rbx, [rsi + 8]      ; rbx = is_free

    test rbx, rbx
    jz .next_block          ; if not free, skip

    cmp rax, r12
    jb .next_block          ; if too small, skip

    mov qword [rsi + 8], 0  ; Mark as not free
    lea rax, [rsi + 16]     ; Return pointer to payload
    jmp .exit

.next_block:
    add rsi, 16             ; Skip header
    add rsi, rax            ; Move to next block: current + size
    jmp .loop

.grow_heap:
    ; Calculate total size to request: header (16) + payload size (r12)
    mov eax, SYS_BRK
    lea rdi, [r12 + 16]
    add rdi, [heap_end]      ; New break address
    syscall

    cmp rax, [heap_end]
    je .out_of_memory

    ; Set up header at old heap_end
    mov rsi, [heap_end]
    mov [rsi], r12          ; Store size
    mov qword [rsi + 8], 0  ; is_free = 0 (allocated)

    mov [heap_end], rax     ; Update heap_end to new break
    lea rax, [rsi + 16]     ; Return payload pointer
    jmp .exit

.out_of_memory:
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbp
    ret

; --------------------------------------------------------------------------------
; void my_free(void *ptr)
; --------------------------------------------------------------------------------
free:
    test rdi, rdi
    jz .done
    
    ; Move pointer back 16 bytes to reach the header
    sub rdi, 16
    mov qword [rdi + 8], 1    ; Mark as free

.done:
    ret
