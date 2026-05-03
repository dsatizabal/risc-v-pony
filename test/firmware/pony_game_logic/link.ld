ENTRY(_start)

SECTIONS
{
    . = 0x00000000;

    .text : {
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    }

    . = ALIGN(4);

    /*
     * This tiny Pony runtime does not copy .data or clear .bss.
     * Keep state in stack locals, registers, constants, or MMIO.
     */
    .data : {
        *(.sdata*)
        *(.data*)
    }

    .bss : {
        *(.sbss*)
        *(.bss*)
        *(COMMON)
    }

    ASSERT(SIZEOF(.data) == 0, "Initialized .data is not supported by this simple Pony startup")
    ASSERT(SIZEOF(.bss) == 0, "Global .bss is not initialized by this simple Pony startup")

    /DISCARD/ : {
        *(.comment)
        *(.riscv.attributes)
        *(.eh_frame*)
        *(.debug*)
    }
}
