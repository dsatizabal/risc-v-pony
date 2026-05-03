/*
 * RiscV Pony bare-metal startup
 *
 * The current Pony core has a tiny internal data RAM mapped below 0x80
 * and MMIO at:
 *   0x80 -> out_port
 *   0x84 -> in_port
 *
 * Keep the stack small. The first pushed word will land at 0x7C.
 */

    .section .init, "ax"
    .globl _start
    .align 2

_start:
    li   sp, 0x80
    call main

_halt:
    j    _halt
