/*
 * RiscV Pony Tang Nano timer-paced LED demo
 *
 * MMIO:
 *   0x80 -> out_port
 *   0x84 -> in_port
 *   0x88 -> timer_value
 *
 * Behavior:
 *   - LED pattern advances based on the hardware timer.
 *   - btn[0] pressed changes the chase direction.
 *
 * This proves on physical FPGA hardware:
 *   - LW from 0x88 reads the MMIO timer
 *   - timer increments independently from firmware execution
 *   - firmware branches based on elapsed timer value
 *   - physical button input still works
 *   - SW to 0x80 still drives LEDs
 */

    .section .text
    .globl _start
    .align 2

.equ MMIO_OUT,   128
.equ MMIO_IN,    132
.equ MMIO_TIMER, 136

_start:
    li   x1, MMIO_OUT
    li   x5, MMIO_IN
    li   x8, MMIO_TIMER

    li   x2, 1          /* LED pattern */
    li   x4, 64         /* upper bound */
    li   x10, 0x00400   /* timer interval high immediate */
    slli x10, x10, 12   /* x10 = 0x00040000 */

main_loop:
    sw   x2, 0(x1)

    lw   x9, 0(x8)      /* start = timer */

wait_timer:
    lw   x11, 0(x8)     /* now = timer */
    sub  x12, x11, x9   /* elapsed = now - start */
    bltu x12, x10, wait_timer

    lw   x6, 0(x5)      /* input */
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
