/*
 * RiscV Pony Tang Nano button-controlled LED firmware
 *
 * MMIO:
 *   0x80 -> out_port
 *   0x84 -> in_port
 *
 * Top-level wrapper exposes onboard buttons as active-high bits:
 *   in_port[0] = 1 when btn[0] is pressed
 *   in_port[1] = 1 when btn[1] is pressed
 *
 * Behavior:
 *   no button  -> LED chase left
 *   btn[0]     -> LED chase right
 *
 * The firmware writes normal active-high LED patterns. The Tang Nano
 * top-level wrapper inverts out_port[5:0] because the LEDs are active-low.
 */

    .section .text
    .globl _start
    .align 2

.equ MMIO_OUT, 128
.equ MMIO_IN,  132

_start:
    li   x1, MMIO_OUT
    li   x5, MMIO_IN
    li   x2, 1
    li   x4, 64

main_loop:
    sw   x2, 0(x1)

    lui  x3, 0x00040

delay_loop:
    addi x3, x3, -1
    bne  x3, x0, delay_loop

    lw   x6, 0(x5)
    andi x7, x6, 1
    bne  x7, x0, move_right

move_left:
    slli x2, x2, 1
    bltu x2, x4, main_loop
    li   x2, 1
    j    main_loop

move_right:
    srli x2, x2, 1
    bne  x2, x0, main_loop
    li   x2, 32
    j    main_loop
