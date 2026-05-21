OUTPUT_ARCH("riscv")
ENTRY(_start)

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

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
    }
}
