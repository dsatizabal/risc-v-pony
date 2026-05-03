MEMORY {
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 1024   /* 1KB of SPI Flash */
    RAM (rw) : ORIGIN = 0x00000200, LENGTH = 128    /* 128 Bytes of internal SRAM */
}

SECTIONS {
    /* Put the boot code and program instructions in ROM */
    .text : {
        *(.init)
        *(.text*)
    } > ROM

    /* Put variables in RAM */
    .data : { *(.data*) *(.rodata*) *(.sdata*) } > RAM AT> ROM
    .bss  : { *(.bss*) *(.sbss*) } > RAM
}

