ENTRY(_start)

SECTIONS
{
    . = 0x00000000;

    .text : {
        *(.text*)
    }

    /DISCARD/ : {
        *(.comment)
        *(.riscv.attributes)
        *(.eh_frame*)
        *(.debug*)
    }
}
