/*
 * RiscV Pony Tang Nano LED-chase firmware
 *
 * This is the source version of firmware.hex.
 *
 * MMIO:
 *   0x80 -> out_port
 *
 * out_port[5:0] is mapped to active-low Tang Nano LEDs by the top-level
 * wrapper, so firmware writes normal active-high LED patterns.
 */

    .section .text
    .globl _start
    .align 2

.equ MMIO_OUT, 128

_start:
    li   x1, MMIO_OUT
    li   x2, 1
    li   x4, 64

main_loop:
    sw   x2, 0(x1)

    lui  x3, 0x00040

delay_loop:
    addi x3, x3, -1
    bne  x3, x0, delay_loop

    slli x2, x2, 1
    bltu x2, x4, main_loop

    li   x2, 1
    j    main_loop
