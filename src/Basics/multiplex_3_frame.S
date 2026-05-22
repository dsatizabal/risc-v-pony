# multiplex_3_frame.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o multiplex_3_frame.elf multiplex_3_frame.S
# Extract: riscv64-unknown-elf-objcopy -O binary multiplex_3_frame.elf multiplex_3_frame.bin

.equ MMIO_VGA_CTRL,      140
.equ MMIO_VGA_OBJ_INDEX, 148
.equ MMIO_VGA_OBJ_WORD0, 152
.equ MMIO_VGA_OBJ_WORD1, 156
.equ MMIO_VGA_BG_COLOR,  160
.equ MMIO_VGA_OBJ_WORD2, 164
.equ MMIO_FRAMES_COUNTER,168

.section .text
.globl _start

_start:

    # --------------------------------------------------------
    # 1. SETUP BACKGROUND & ENABLE VGA
    # --------------------------------------------------------
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x00
    SW x2, 0(x1)

    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 2. INITIALIZE REGISTERS
    # x13 = Frame Counter
    # x8  = Shared Missile Length
    # x9  = Multiplex Phase (0, 1, or 2)
    # --------------------------------------------------------
    LI x13, 0
    LI x8, 0
    LI x9, 0

game_loop:

    # --------------------------------------------------------
    # 3. WAIT FOR VBLANK (60 Hz)
    # --------------------------------------------------------
    LI x1, MMIO_FRAMES_COUNTER
    LW x2, 0(x1)

wait_vblank:

    LW x3, 0(x1)
    BEQ x2, x3, wait_vblank

    # --------------------------------------------------------
    # 4. UPDATE MULTIPLEX PHASE (0 -> 1 -> 2 -> 0)
    # --------------------------------------------------------
    ADDI x9, x9, 1
    LI x4, 3
    BLT x9, x4, phase_ok
    LI x9, 0

phase_ok:

    # --------------------------------------------------------
    # 5. GROW MISSILE LENGTH SLOWLY (Every 2 frames)
    # --------------------------------------------------------
    ADDI x13, x13, 1
    ANDI x4, x13, 1
    BEQ x4, zero, skip_grow

    ADDI x8, x8, 1
    LI x4, 180
    BLT x8, x4, skip_grow
    LI x8, 0

skip_grow:

    # --------------------------------------------------------
    # 6. CALCULATE STARTING X-COORDINATE BASED ON PHASE
    # --------------------------------------------------------
    LI x4, 0
    BEQ x9, x4, set_m1
    LI x4, 1
    BEQ x9, x4, set_m2

set_m3:

    LI x5, 200
    J draw_objects

set_m1:

    LI x5, 40
    J draw_objects

set_m2:

    LI x5, 120

draw_objects:

    # --------------------------------------------------------
    # 7. DRAW THE YELLOW TAIL (Line Engine 8)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 8
    SW x4, 0(x1)

    # Word 0: Enable(0x80000000) | X(x5 << 15) | Y(0 << 5)
    LI x4, 0x80000000
    SLLI x2, x5, 15
    OR x4, x4, x2
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x4, 0(x1)

    # Word 1: Length(x8 << 22) | Dir(Right=0) | Yellow(0x3C << 7 = 0x1E00)
    SLLI x4, x8, 22
    LI x2, 0x1E00
    OR x4, x4, x2
    LI x1, MMIO_VGA_OBJ_WORD1
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 8. DRAW THE WHITE TIP (Sprite Engine 0)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # Calculate Tip Coordinates (Start + Length)
    ADD x6, x5, x8
    MV x7, x8

    # Word 0: Enable & White(0xFE000000) | X(x6 << 15) | Y(x7 << 5)
    LI x4, 0xFE000000
    SLLI x2, x6, 15
    OR x4, x4, x2
    SLLI x2, x7, 5
    OR x4, x4, x2
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x4, 0(x1)

    # Word 1 & 2: A 2x2 solid white pixel block at the top left
    LI x4, 0xC0C00000
    LI x1, MMIO_VGA_OBJ_WORD1
    SW x4, 0(x1)

    LI x4, 0x00000000
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x4, 0(x1)

    J game_loop
