/* NOVA-1 cartridge startup.
 *
 * The first 32 bytes of every ROM are the cartridge header the APU reads at
 * power-on: magic "NOVA", entry point, and a 24-byte title. Then _start sets
 * up the stack, copies initialised data from ROM to RAM, clears .bss and calls
 * the Ada binder's main(), which elaborates every package and runs the game.
 */

#ifndef CART_TITLE
#define CART_TITLE "UNTITLED"
#endif

    .section .header, "a"
    .ascii  "NOVA"
    .word   _start
1:  .ascii  CART_TITLE
    .org    1b + 24, 0

    .section .text.start, "ax"
    .globl  _start
_start:
    .option push
    .option norelax
    la      sp, __stack_top
    .option pop

    /* copy .data from its load address in ROM to RAM */
    la      t0, __data_load
    la      t1, __data_start
    la      t2, __data_end
1:  bgeu    t1, t2, 2f
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       1b

    /* zero .bss */
2:  la      t0, __bss_start
    la      t1, __bss_end
3:  bgeu    t0, t1, 4f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       3b

4:  call    main

    /* the main procedure returned: power off with exit code 0 */
    li      t0, 0x30000010
    sw      zero, 0(t0)
5:  j       5b
