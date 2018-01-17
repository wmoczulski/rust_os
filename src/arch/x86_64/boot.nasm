global start
extern long_mode_start

section .text
bits 32

check_multiboot:
    cmp eax, 0x36d76289
    jne .no_multiboot
    ret
.no_multiboot:
    mov al, "0"
    jmp error


; stolen from: http://wiki.osdev.org/Setting_Up_Long_Mode#Detection_of_CPUID
check_cpuid:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    cmp eax, ecx
    je .no_cpuid
    ret
.no_cpuid:
    mov al, "1"
    jmp error


check_long_mode:
    ; test if extended processor info is available
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no_long_mode

    ; use extended info to test if long mode is available
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz .no_long_mode
    ret
.no_long_mode:
    mov al, "2"
    jmp error


set_up_page_tables:
    ; point last p4 ptr to p4
    mov eax, p4_table
    or eax, 0b11 ; present + writable
    mov [p4_table + 511 * 8], eax
    ; pointing p4 entry to p3 table
    mov eax, p3_table
    or eax, 0b11 ; present + writable
    mov [p4_table], eax 

    ; pointing p3 entry to p2 table
    mov eax, p2_table
    or eax, 0b11 ; present + writable
    mov [p3_table], eax 

    mov ecx, 0
.map_p2_table:
    ; point ECX-th P2 entry to a huge page that starts at address 2MiB * ECX
    mov eax, 0x200000
    mul ecx ; by eax
    or eax, 0b10000011 ; present + writable + huge
    mov [p2_table + ecx * 8], eax

    inc ecx
    cmp ecx, 512
    jne .map_p2_table

    ret

enable_paging:
    mov eax, p4_table
    mov cr3, eax

    ; enable PAE flag in cr4
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; set the long mode bit in the efer msr
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; enable paging in the cr0 register
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret


start:
    mov esp, stack_top
    mov edi, ebx ; pass multiboot info ptr to rust_main

    call check_multiboot
    call check_cpuid
    call check_long_mode

    call set_up_page_tables
    call enable_paging


    lgdt [gdt64.pointer]



    jmp gdt64.code:long_mode_start ; go to long mode

    mov dword [0xb8000], 0x2f4b2f4f ; print ok after system finished
    hlt

; Prints `ERR` and error
; parameter: error code (in ascii) in al
error:
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f3a4f52
    mov dword [0xb8008], 0x4f204f20
    mov byte  [0xb800a], al
    hlt


section .rodata
gdt64:
    dq 0
.code: equ $ - gdt64
    dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53) ; code segment
.pointer:
    dw $ - gdt64 - 1
    dq gdt64


section .bss
align 4096
p4_table:
    resb 4096
p3_table:
    resb 4096
p2_table:
    resb 4096


stack_bottom:
    resb 4 * 4096
stack_top: