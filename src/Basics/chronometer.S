# chronometer.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o chronometer.elf chronometer.S
# Extract: riscv64-unknown-elf-objcopy -O binary chronometer.elf chronometer.bin

.equ MMIO_VGA_CTRL,        140
.equ MMIO_VGA_OBJ_INDEX,   148
.equ MMIO_VGA_OBJ_WORD0,   152
.equ MMIO_VGA_OBJ_WORD1,   156
.equ MMIO_VGA_BG_COLOR,    160
.equ MMIO_VGA_OBJ_WORD2,   164
.equ MMIO_FRAMES_COUNTER,  168

.section .text
.globl _start

_start:

    # --------------------------------------------------------
    # 1. SETUP BACKGROUND & ENABLE
    # --------------------------------------------------------
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x00
    SW x2, 0(x1)

    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 2. INITIALIZE COUNTERS
    # --------------------------------------------------------
    LI x13, 0       # Frame Counter (0 to 59)
    LI x8, 0        # Seconds Counter (0 to 99)

game_loop:

    # --------------------------------------------------------
    # 3. WAIT FOR VBLANK (1/60th of a second)
    # --------------------------------------------------------
    LI x1, MMIO_FRAMES_COUNTER
    LW x2, 0(x1)

wait_vblank:

    LW x3, 0(x1)
    BEQ x2, x3, wait_vblank

    # --------------------------------------------------------
    # 4. UPDATE TIME REGISTERS
    # --------------------------------------------------------
    ADDI x13, x13, 1
    LI x4, 60
    BLT x13, x4, render

    # If 60 frames passed, reset frames and increment seconds
    LI x13, 0
    ADDI x8, x8, 1
    LI x4, 100
    BLT x8, x4, render

    # If 100 seconds passed, reset seconds back to 00
    LI x8, 0

render:

    # --------------------------------------------------------
    # 5. DIVIDE SECONDS INTO TENS AND ONES
    # --------------------------------------------------------
    MV x5, x8
    LI x9, 0
    LI x2, 10

div_loop:

    BLT x5, x2, div_done
    SUB x5, x5, x2
    ADDI x9, x9, 1
    J div_loop

div_done:

    # --------------------------------------------------------
    # 6. DRAW TENS DIGIT (Sprite 0, X=152, Y=116)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # Word 0: 0xFE4C0E80 (Enable=1, Color=White, X=152, Y=116)
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0xFE4C0E80
    SW x2, 0(x1)

    MV x4, x9
    JAL x14, get_font

    LI x1, MMIO_VGA_OBJ_WORD1
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 7. DRAW ONES DIGIT (Sprite 1, X=160, Y=116)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)

    # Word 0: 0xFE500E80 (Enable=1, Color=White, X=160, Y=116)
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0xFE500E80
    SW x2, 0(x1)

    MV x4, x5
    JAL x14, get_font

    LI x1, MMIO_VGA_OBJ_WORD1
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x3, 0(x1)

    J game_loop

# --------------------------------------------------------
# 8. FONT SUBROUTINE (0-9)
# --------------------------------------------------------
get_font:

    LI x15, 1
    BEQ x4, x15, f_1
    LI x15, 2
    BEQ x4, x15, f_2
    LI x15, 3
    BEQ x4, x15, f_3
    LI x15, 4
    BEQ x4, x15, f_4
    LI x15, 5
    BEQ x4, x15, f_5
    LI x15, 6
    BEQ x4, x15, f_6
    LI x15, 7
    BEQ x4, x15, f_7
    LI x15, 8
    BEQ x4, x15, f_8
    LI x15, 9
    BEQ x4, x15, f_9

f_0:

    LI x2, 0x3C666666
    LI x3, 0x6666663C
    JALR zero, 0(x14)

f_1:

    LI x2, 0x18381818
    LI x3, 0x1818187E
    JALR zero, 0(x14)

f_2:

    LI x2, 0x3C66060C
    LI x3, 0x1830607E
    JALR zero, 0(x14)

f_3:

    LI x2, 0x3C66061C
    LI x3, 0x0606663C
    JALR zero, 0(x14)

f_4:

    LI x2, 0x0C1C3C6C
    LI x3, 0xCCFE0C0C
    JALR zero, 0(x14)

f_5:

    LI x2, 0x7E607C06
    LI x3, 0x0606663C
    JALR zero, 0(x14)

f_6:

    LI x2, 0x3C66607C
    LI x3, 0x6666663C
    JALR zero, 0(x14)

f_7:

    LI x2, 0x7E06060C
    LI x3, 0x18181818
    JALR zero, 0(x14)

f_8:

    LI x2, 0x3C66663C
    LI x3, 0x6666663C
    JALR zero, 0(x14)

f_9:

    LI x2, 0x3C666666
    LI x3, 0x3E06063C
    JALR zero, 0(x14)