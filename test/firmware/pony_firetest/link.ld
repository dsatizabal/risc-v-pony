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
     * Keep this firmware intentionally simple:
     * - no initialized globals
     * - no global bss assumptions
     * - use stack locals and MMIO only
     *
     * Pony is effectively Harvard-style in simulation: instructions are
     * fetched from SPI, while loads/stores access the small internal RAM
     * and MMIO window.
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
