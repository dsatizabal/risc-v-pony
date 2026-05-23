# collision.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o collision.elf collision.S
# Extract: riscv64-unknown-elf-objcopy -O binary collision.elf collision.bin

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
    # 2. LOAD GRAPHICS (Solid 8x8 Blocks)
    # --------------------------------------------------------
    # Sprite 0 (Sweeper)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0xFFFFFFFF
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    SW x2, 0(x1)

    # Sprite 1 (Target)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0xFFFFFFFF
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 3. INITIALIZE STATE REGISTERS
    # --------------------------------------------------------
    LI x13, 0       # Frame Counter
    LI x6, 100      # Sweeper X
    LI x7, 116      # Sweeper Y (Fixed center)
    LI x8, 156      # Target X (Fixed center)
    LI x9, 116      # Target Y (Fixed center)

game_loop:

    # --------------------------------------------------------
    # 4. WAIT FOR VBLANK
    # --------------------------------------------------------
    LI x1, MMIO_FRAMES_COUNTER
    LW x2, 0(x1)

wait_vblank:

    LW x3, 0(x1)
    BEQ x2, x3, wait_vblank
    ADDI x13, x13, 1

    # --------------------------------------------------------
    # 5. AUTO-SWEEP LOGIC FOR SPRITE 0
    # --------------------------------------------------------
    SRLI x4, x13, 1
    ANDI x4, x4, 127
    LI x5, 64
    BLT x4, x5, move_right

move_left:

    LI x5, 128
    SUB x4, x5, x4
    J apply_x

move_right:

    # x4 is already between 0 and 63

apply_x:

    SLLI x4, x4, 1
    LI x6, 100
    ADD x6, x6, x4

    # --------------------------------------------------------
    # 6. CALL COLLISION DETECTION
    # --------------------------------------------------------
    JAL x14, check_collision

    # --------------------------------------------------------
    # 7. DRAW TARGET (SPRITE 1) BASED ON COLLISION RESULT
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)

    # Base Enable Bit (0x80000000)
    LI x5, 0x80000000

    # If x10 == 1 (Hit), use Green. Else, use Red.
    BNE x10, zero, target_hit

target_miss:

    # Red = 0x30 << 25 = 0x60000000
    LI x4, 0x60000000
    J apply_target_color

target_hit:

    # Green = 0x0C << 25 = 0x18000000
    LI x4, 0x18000000

apply_target_color:

    OR x5, x5, x4

    # Pack Target X and Y
    SLLI x4, x8, 15
    OR x5, x5, x4
    SLLI x4, x9, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    # --------------------------------------------------------
    # 8. DRAW SWEEPER (SPRITE 0)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # Enable=1, White=0x3F (0xFE000000)
    LI x5, 0xFE000000

    # Pack Sweeper X and Y
    SLLI x4, x6, 15
    OR x5, x5, x4
    SLLI x4, x7, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    J game_loop

# --------------------------------------------------------
# SUBROUTINE: AABB Collision Detection (8x8 Objects)
# Inputs:
#   x6, x7 = Object 1 (X, Y)
#   x8, x9 = Object 2 (X, Y)
# Outputs:
#   x10 = 1 if Collision, 0 if Miss
# Uses: x4 (Scratch)
# --------------------------------------------------------
check_collision:

    LI x10, 0

    # Test 1: Is Obj1 completely to the LEFT of Obj2? (X1 + 8 < X2)
    ADDI x4, x6, 8
    BLT x4, x8, collision_return

    # Test 2: Is Obj1 completely to the RIGHT of Obj2? (X2 + 8 < X1)
    ADDI x4, x8, 8
    BLT x4, x6, collision_return

    # Test 3: Is Obj1 completely ABOVE Obj2? (Y1 + 8 < Y2)
    ADDI x4, x7, 8
    BLT x4, x9, collision_return

    # Test 4: Is Obj1 completely BELOW Obj2? (Y2 + 8 < Y1)
    ADDI x4, x9, 8
    BLT x4, x7, collision_return

    # Overlap!
    LI x10, 1

collision_return:

    JALR zero, 0(x14)
