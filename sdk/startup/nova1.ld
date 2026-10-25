/* NOVA-1 cartridge memory layout */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 1M
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 256K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.header))
        KEEP(*(.text.start))
        *(.text .text.*)
    } > ROM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > ROM

    .data : ALIGN(4)
    {
        __data_start = .;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT > ROM
    __data_load = LOADADDR(.data);

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ : { *(.comment) *(.eh_frame*) *(.note*) *(.riscv.attributes) }
}
