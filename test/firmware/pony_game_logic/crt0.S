/*
 * RiscV Pony bare-metal startup for game-logic firmware.
 *
 * Current simulation memory map:
 *   0x80 -> out_port
 *   0x84 -> in_port
 *
 * Keep stack below MMIO. The first pushed word lands at 0x7C.
 */

    .section .init, "ax"
    .globl _start
    .align 2

_start:
    li   sp, 0x80
    call main

_halt:
    j    _halt
