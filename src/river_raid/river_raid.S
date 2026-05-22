# river_raid.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o river_raid.elf river_raid.S
# Extract: riscv64-unknown-elf-objcopy -O binary river_raid.elf river_raid.bin

.equ MMIO_VGA_CTRL,        140
.equ MMIO_VGA_OBJ_INDEX,   148
.equ MMIO_VGA_OBJ_WORD0,   152
.equ MMIO_VGA_OBJ_WORD1,   156
.equ MMIO_VGA_BG_COLOR,    160
.equ MMIO_VGA_OBJ_WORD2,   164
.equ MMIO_FRAMES_COUNTER,  168
.equ MMIO_LINE_COUNTER,    172

.section .text
.globl _start

_start:

    # --------------------------------------------------------
    # 1. SETUP STATIC SCENE
    # --------------------------------------------------------
    # Background: Blue (0x03)
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x03
    SW x2, 0(x1)

    # Rect 4: Top Score Bar (Black, X=0, Y=0, W=320, H=24)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 4
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80000000
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x50030000
    SW x3, 0(x1)

    # Rect 5: Left River Bank (Green, X=0, Y=24, W=40, H=216)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 5
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80000300
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x0A1B0600
    SW x3, 0(x1)

    # Rect 6: Right River Bank (Green, X=280, Y=24, W=40, H=216)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 6
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80000300
    LI x3, 280
    SLLI x3, x3, 15
    OR x2, x2, x3
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x0A1B0600
    SW x3, 0(x1)

    # Sprite 0: Plane Pattern (White)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0x183C7EFF
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF7E3C18
    SW x3, 0(x1)

    # Sprite 1: Enemy Ship Pattern (Red)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0xFFDB7E3C
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0x18181818
    SW x3, 0(x1)

    LI x1, MMIO_VGA_CTRL
    LI x4, 1
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 2. INITIALIZE GAME STATE REGISTERS
    # --------------------------------------------------------
    LI x6, 160      # Plane X
    LI x7, 160      # Enemy X
    LI x8, 24       # Enemy Y
    LI x9, 160      # Bullet X
    LI x10, 200     # Bullet Y
    LI x11, 24      # Island Y (Rect 7)
    LI x12, 0       # Score
    LI x13, 0       # Frame Counter

game_loop:

    # --------------------------------------------------------
    # 3. WAIT FOR VBLANK
    # --------------------------------------------------------
    LI x1, MMIO_FRAMES_COUNTER
    LW x2, 0(x1)

wait_vblank:

    LW x3, 0(x1)
    BEQ x2, x3, wait_vblank
    ADDI x13, x13, 1

    # --------------------------------------------------------
    # 4. DRAW SCORE AT TOP OF SCREEN (Sprites 2 & 3)
    # --------------------------------------------------------
    MV x5, x12
    LI x4, 0
    LI x2, 10

score_div:

    BLT x5, x2, score_div_done
    SUB x5, x5, x2
    ADDI x4, x4, 1
    J score_div

score_div_done:

    # Tens Digit (Sprite 2, Yellow, X=150, Y=8)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, 2
    SW x2, 0(x1)

    LI x2, 0xF8000000
    LI x3, 150
    SLLI x3, x3, 15
    OR x2, x2, x3
    LI x3, 8
    SLLI x3, x3, 5
    OR x2, x2, x3

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)
    JAL x14, get_font
    LI x1, MMIO_VGA_OBJ_WORD1
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x3, 0(x1)

    # Ones Digit (Sprite 3, Yellow, X=158, Y=8)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, 3
    SW x2, 0(x1)

    LI x2, 0xF8000000
    LI x3, 158
    SLLI x3, x3, 15
    OR x2, x2, x3
    LI x3, 8
    SLLI x3, x3, 5
    OR x2, x2, x3

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)
    MV x4, x5
    JAL x14, get_font
    LI x1, MMIO_VGA_OBJ_WORD1
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 5. WORLD PHYSICS
    # --------------------------------------------------------
    # Scroll Island
    ADDI x11, x11, 2
    LI x4, 240
    BLT x11, x4, skip_island_reset
    LI x11, -40

skip_island_reset:

    # Move Enemy Down
    ADDI x8, x8, 1
    LI x4, 230
    BLT x8, x4, skip_enemy_reset
    LI x8, 24
    ANDI x7, x13, 127
    ADDI x7, x7, 60

skip_enemy_reset:

    # Move Bullet Up
    ADDI x10, x10, -4
    LI x4, 24
    BGE x10, x4, check_bullet_collision
    # Reload bullet to plane
    MV x9, x6
    LI x10, 200

check_bullet_collision:

    # AABB Collision (Bullet vs Enemy)
    BLT x9, x7, ai_update
    ADDI x4, x7, 8
    BGE x9, x4, ai_update
    BLT x10, x8, ai_update
    ADDI x4, x8, 8
    BGE x10, x4, ai_update

    # HIT ENEMY!
    ADDI x12, x12, 1
    LI x4, 99
    BLE x12, x4, skip_score_cap
    LI x12, 0

skip_score_cap:

    LI x8, 24
    ANDI x7, x13, 127
    ADDI x7, x7, 60
    LI x10, 24

ai_update:

    # Auto-Plane logic
    BEQ x6, x7, check_player_crash
    BLT x6, x7, plane_right
    ADDI x6, x6, -1
    J check_player_crash

plane_right:

    ADDI x6, x6, 1

check_player_crash:

    # 1. Check Shore Collision
    LI x4, 40
    BLT x6, x4, handle_crash
    LI x4, 272
    BGE x6, x4, handle_crash

    # 2. Check Island Collision (Plane vs Rect 7: X=150, W=20, H=10, Y=x11)
    # Is Plane X+8 >= Island X (150)? -> x6 >= 142
    LI x4, 142
    BLT x6, x4, race_the_beam
    # Is Plane X <= Island X+W (170)?
    LI x4, 170
    BGE x6, x4, race_the_beam
    # Is Plane Y+8 >= Island Y (x11)? -> 208 >= x11
    LI x4, 208
    BLT x4, x11, race_the_beam
    # Is Plane Y <= Island Y+H (x11+10)? -> 200 <= x11 + 10
    ADDI x4, x11, 10
    LI x5, 200
    BLT x4, x5, race_the_beam

handle_crash:

    # Reset Score and Center Plane
    LI x12, 0
    LI x6, 160

    # --------------------------------------------------------
    # 6. RACING THE BEAM (Wait for Line 24)
    # --------------------------------------------------------
race_the_beam:

    LI x3, MMIO_LINE_COUNTER

wait_line_0:

    LW x4, 0(x3)
    BNE x4, zero, wait_line_0

wait_line_24:

    LW x4, 0(x3)
    LI x5, 24
    BLT x4, x5, wait_line_24

    # --------------------------------------------------------
    # 7. DRAW MAIN PLAYFIELD (After Line 24)
    # --------------------------------------------------------
    # Hide Sprite 3 (Ones Digit)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 3
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW zero, 0(x1)

    # Convert Sprite 2 from "Tens Digit" into "Bullet"
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 2
    SW x4, 0(x1)

    LI x5, 0xF8000000
    SLLI x4, x9, 15
    OR x5, x5, x4
    SLLI x4, x10, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x4, 0x18181818
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x4, 0x18181818
    SW x4, 0(x1)

    # RENDER ISLAND (Rect 7, Black = 0x00)
    LI x5, 0x80000000
    LI x4, 150
    SLLI x4, x4, 15
    OR x5, x5, x4
    SLLI x4, x11, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 7
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0x05014000
    SW x2, 0(x1)

    # RENDER PLANE (Sprite 0, White)
    LI x5, 0xFE000000
    SLLI x4, x6, 15
    OR x5, x5, x4
    LI x4, 200
    SLLI x4, x4, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    # RENDER ENEMY (Sprite 1, Red)
    LI x5, 0xE0000000
    SLLI x4, x7, 15
    OR x5, x5, x4
    SLLI x4, x8, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    J game_loop

# --------------------------------------------------------
# 8. FONT SUBROUTINE
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
