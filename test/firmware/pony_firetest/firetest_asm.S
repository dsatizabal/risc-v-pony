/*
 * RiscV Pony Firetest - assembly version
 *
 * Expected output sequence, ignoring 0xFF sentinels:
 *   0x21, 0x0F, 0x15, 0x42, 0xAA
 */

    .section .init, "ax"
    .globl _start
    .align 2

.equ MMIO_OUT, 128
.equ MMIO_IN,  132
.equ SENTINEL, 255

_start:
    li   sp, 0x80

    li   a0, 0x21
    jal  ra, emit

    li   a0, 5
    jal  ra, sum_to
    jal  ra, emit

    li   a0, 7
    li   a1, 4
    jal  ra, mix_value
    jal  ra, emit

    addi sp, sp, -8
    li   t0, 0x33
    sw   t0, 0(sp)
    lw   t1, 0(sp)
    addi t1, t1, 0x0F
    sw   t1, 4(sp)
    lw   a0, 4(sp)
    addi sp, sp, 8
    jal  ra, emit

    li   t0, 3
    li   t1, 9
    bltu t0, t1, branch_pass
    li   a0, 0xEE
    jal  ra, emit
    j    done

branch_pass:
    li   a0, 0xAA
    jal  ra, emit

done:
    j    done

emit:
    li   t0, MMIO_OUT
    li   t1, SENTINEL
    sw   t1, 0(t0)
    sw   a0, 0(t0)
    ret

sum_to:
    li   t0, 0
    li   t1, 1

sum_loop:
    bltu a0, t1, sum_done
    add  t0, t0, t1
    addi t1, t1, 1
    j    sum_loop

sum_done:
    add  a0, t0, zero
    ret

mix_value:
    add  t0, a0, a0
    add  t0, t0, a1
    addi a0, t0, 3
    ret
