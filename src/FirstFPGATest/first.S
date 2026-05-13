.section .text
.global _start

_start:
    addi x1, x0, 128      # MMIO_OUT address

main_loop:
    addi x2, x0, 1
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 2
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 4
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 8
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 16
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 32
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 63
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 21       # 010101
    sw   x2, 0(x1)
    jal  x5, delay

    addi x2, x0, 42       # 101010
    sw   x2, 0(x1)
    jal  x5, delay

    jal  x0, main_loop

delay:
    addi x3, x0, 100
delay_outer:
    addi x4, x0, 255
delay_inner:
    addi x4, x4, -1
    bne  x4, x0, delay_inner

    addi x3, x3, -1
    bne  x3, x0, delay_outer

    jalr x0, 0(x5)
