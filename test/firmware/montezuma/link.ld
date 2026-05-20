OUTPUT_ARCH("riscv")
ENTRY(_start)

/* In this architecture, SPI fetches instructions from 0x00000000 */
MEMORY
{
    rom (rx) : ORIGIN = 0x00000000, LENGTH = 16M
}

SECTIONS
{
    .text : {
        *(.text)
        *(.rodata*)
    } > rom

    /* Discard standard C library sections we don't need */
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
    }
}
