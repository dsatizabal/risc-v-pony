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
    li   x2, 32
    li   x4, 1

main_loop:
    sw   x2, 0(x1)

    lui  x3, 0x00100

delay_loop:
    addi x3, x3, -1
    bne  x3, x0, delay_loop

    li   x3, 32
    beq   x2, x3, load1

    li   x3, 1
    beq   x2, x3, load16

    li   x3, 16
    beq   x2, x3, load2

    li   x3, 2
    beq   x2, x3, load8

    li   x3, 8
    beq   x2, x3, load4

    li   x2, 32
    j    main_loop

load1:
    li   x2, 1
    j    main_loop

load2:
    li   x2, 2
    j    main_loop

load4:
    li   x2, 4
    j    main_loop

load8:
    li   x2, 8
    j    main_loop

load16:
    li   x2, 16
    j    main_loop

