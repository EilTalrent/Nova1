    .section .header, "a"
    .ascii "NOVA"
    .word _start
1:  .ascii "ISA TEST"
    .org 1b + 24, 0
    .section .text.start, "ax"
    .globl _start
_start:
    la sp, __stack_top
    la t0, __data_load
    la t1, __data_start
    la t2, __data_end
1:  bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:  call main
    li t0, 0x30000010
    sw a0, 0(t0)
3:  j 3b
