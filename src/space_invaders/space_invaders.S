# space_invaders.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o space_invaders.elf space_invaders.S
# Extract: riscv64-unknown-elf-objcopy -O binary space_invaders.elf space_invaders.bin

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
    # 1. SETUP STATIC BACKGROUND & GROUND
    # --------------------------------------------------------
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x00
    SW x2, 0(x1)

    # Rect 7: Green Ground Line
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 7
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80001B80
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x50028600
    SW x3, 0(x1)

    # Rect 4: The Bullet (Initialized as Width=2, Height=8, Yellow)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 4
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x2, 0x00811E00
    SW x2, 0(x1)

    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 2. STATE REGISTERS
    # --------------------------------------------------------
    LI x6, 160          # Player X
    LI x7, 0xFFFFF      # 20-bit ALIVE MASK (All 20 aliens alive)
    LI x8, 200          # Bullet Y
    LI x9, 0            # Score
    LI x10, 164         # Bullet X
    LI x11, 60          # Armada Base X
    LI x13, 0           # Global Frame Counter

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
    # 4. AUTONOMOUS PHYSICS & COLLISION
    # --------------------------------------------------------

    # Player Auto-Sweep
    SRLI x4, x13, 2
    ANDI x4, x4, 255
    LI x5, 128
    BLT x4, x5, p_right
    LI x6, 256
    SUB x6, x6, x4
    J p_done
p_right:
    LI x6, 40
    ADD x6, x6, x4
p_done:

    # Armada Auto-Wobble
    SRLI x4, x13, 4
    ANDI x4, x4, 63
    LI x5, 32
    BLT x4, x5, a_right
    LI x11, 100
    SUB x11, x11, x4
    J a_done
a_right:
    LI x11, 40
    ADD x11, x11, x4
a_done:

    # Bullet Movement
    ADDI x8, x8, -4
    LI x4, 10
    BGE x8, x4, check_hit

reload_bullet:

    LI x8, 200
    ADDI x10, x6, 4
    J draw_vblank_objects

check_hit:

    # Check Y Bounds
    ADDI x4, x8, -20
    BLT x4, zero, draw_vblank_objects
    LI x5, 150
    BGE x4, x5, draw_vblank_objects

    # Find Row (0 to 4)
    LI x12, 0
    LI x5, 30
row_loop:
    BLT x4, x5, row_found
    SUB x4, x4, x5
    ADDI x12, x12, 1
    J row_loop
row_found:
    LI x5, 12
    BGE x4, x5, draw_vblank_objects

    # Check X Bounds
    SUB x4, x10, x11
    ADDI x4, x4, 4
    BLT x4, zero, draw_vblank_objects
    LI x5, 160
    BGE x4, x5, draw_vblank_objects

    # Find Col (0 to 3)
    LI x2, 0
    LI x5, 40
col_loop:
    BLT x4, x5, col_found
    SUB x4, x4, x5
    ADDI x2, x2, 1
    J col_loop
col_found:
    LI x5, 14
    BGE x4, x5, draw_vblank_objects

    # Check Alive Mask
    SLLI x4, x12, 2
    ADD x4, x4, x2
    LI x5, 1
    SLL x5, x5, x4
    AND x2, x7, x5
    BEQ x2, zero, draw_vblank_objects

    # HIT! Kill Alien, Update Score, Reload Bullet
    XOR x7, x7, x5
    ADDI x9, x9, 1
    LI x4, 99
    BLE x9, x4, skip_cap
    LI x9, 0
skip_cap:
    BEQ x7, zero, respawn_armada
    J reload_bullet
respawn_armada:
    LI x7, 0xFFFFF
    J reload_bullet

draw_vblank_objects:

    # --------------------------------------------------------
    # 5. DRAW VBLANK OBJECTS (Bullet & Score)
    # --------------------------------------------------------

    # Bullet (Rect 4)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 4
    SW x4, 0(x1)

    LI x5, 0x80000000
    SLLI x4, x10, 15
    OR x5, x5, x4
    SLLI x4, x8, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    # Score (Sprites 0 & 1)
    MV x5, x9
    LI x4, 0
    LI x2, 10
s_div:
    BLT x5, x2, s_div_done
    SUB x5, x5, x2
    ADDI x4, x4, 1
    J s_div
s_div_done:

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, 0
    SW x2, 0(x1)
    LI x2, 0xF8000000
    LI x3, 10
    SLLI x3, x3, 15
    OR x2, x2, x3
    LI x3, 10
    SLLI x3, x3, 5
    OR x2, x2, x3
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)
    JAL x14, get_font
    LI x1, MMIO_VGA_OBJ_WORD1
    SW x2, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD2
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, 1
    SW x2, 0(x1)
    LI x2, 0xF8000000
    LI x3, 18
    SLLI x3, x3, 15
    OR x2, x2, x3
    LI x3, 10
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
    # 6. RACING THE BEAM: THE ALIEN ARMADA
    # --------------------------------------------------------
    LI x3, MMIO_LINE_COUNTER

wait_line_0:

    LW x4, 0(x3)
    BNE x4, zero, wait_line_0

wait_line_20:

    LW x4, 0(x3)
    LI x5, 20
    BLT x4, x5, wait_line_20

    # Load Alien Graphic Pattern into Sprites 0,1,2,3
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, MMIO_VGA_OBJ_WORD1
    LI x10, MMIO_VGA_OBJ_WORD2
    LI x4, 0x183C7EDB
    LI x5, 0xFF245AA5

    LI x14, 0
    SW x14, 0(x1)
    SW x4, 0(x2)
    SW x5, 0(x10)
    LI x14, 1
    SW x14, 0(x1)
    SW x4, 0(x2)
    SW x5, 0(x10)
    LI x14, 2
    SW x14, 0(x1)
    SW x4, 0(x2)
    SW x5, 0(x10)
    LI x14, 3
    SW x14, 0(x1)
    SW x4, 0(x2)
    SW x5, 0(x10)

    # Draw the 5 Rows!
    LI x12, 0
    LI x15, 20
    JAL x14, draw_alien_row
wait_line_50:
    LW x4, 0(x3)
    LI x5, 50
    BLT x4, x5, wait_line_50
    LI x12, 1
    LI x15, 50
    JAL x14, draw_alien_row
wait_line_80:
    LW x4, 0(x3)
    LI x5, 80
    BLT x4, x5, wait_line_80
    LI x12, 2
    LI x15, 80
    JAL x14, draw_alien_row
wait_line_110:
    LW x4, 0(x3)
    LI x5, 110
    BLT x4, x5, wait_line_110
    LI x12, 3
    LI x15, 110
    JAL x14, draw_alien_row
wait_line_140:
    LW x4, 0(x3)
    LI x5, 140
    BLT x4, x5, wait_line_140
    LI x12, 4
    LI x15, 140
    JAL x14, draw_alien_row

    # --------------------------------------------------------
    # 7. RACING THE BEAM: THE PLAYER SHIP
    # --------------------------------------------------------
wait_line_160:

    LW x4, 0(x3)
    LI x5, 160
    BLT x4, x5, wait_line_160

    # Draw Player (Sprite 0)
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    LI x5, 0xFE000000
    SLLI x4, x6, 15
    OR x5, x5, x4
    LI x4, 210
    SLLI x4, x4, 5
    OR x5, x5, x4

    LI x1, MMIO_VGA_OBJ_WORD0
    SW x5, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x5, 0x18183C7E
    SW x5, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x5, 0xFFFFFFFF
    SW x5, 0(x1)

    # Hide Sprites 1, 2, 3 so they don't drag aliens to the bottom
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x2, MMIO_VGA_OBJ_WORD0

    LI x4, 1
    SW x4, 0(x1)
    SW zero, 0(x2)
    LI x4, 2
    SW x4, 0(x1)
    SW zero, 0(x2)
    LI x4, 3
    SW x4, 0(x1)
    SW zero, 0(x2)

    # Restore Bullet X from Player X for the next loop
    ADDI x10, x6, 4

    J game_loop

# --------------------------------------------------------
# SUBROUTINE: Draw 4 Aliens
# --------------------------------------------------------
draw_alien_row:

    SRLI x4, x13, 5
    LI x5, 5
    BLT x4, x5, check_vis
    LI x4, 5

check_vis:

    BGE x12, x4, skip_draw

    SLLI x4, x12, 2
    SRL x5, x7, x4

    # Draw Sprite 0
    ANDI x4, x5, 1
    SLLI x4, x4, 31
    LI x2, 0x0C000000
    OR x2, x2, x4
    SLLI x4, x15, 5
    OR x2, x2, x4
    SLLI x4, x11, 15
    OR x2, x2, x4
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)

    # Draw Sprite 1
    SRLI x5, x5, 1
    ANDI x4, x5, 1
    SLLI x4, x4, 31
    LI x2, 0x0C000000
    OR x2, x2, x4
    SLLI x4, x15, 5
    OR x2, x2, x4
    ADDI x4, x11, 40
    SLLI x4, x4, 15
    OR x2, x2, x4
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)

    # Draw Sprite 2
    SRLI x5, x5, 1
    ANDI x4, x5, 1
    SLLI x4, x4, 31
    LI x2, 0x0C000000
    OR x2, x2, x4
    SLLI x4, x15, 5
    OR x2, x2, x4
    ADDI x4, x11, 80
    SLLI x4, x4, 15
    OR x2, x2, x4
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 2
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)

    # Draw Sprite 3
    SRLI x5, x5, 1
    ANDI x4, x5, 1
    SLLI x4, x4, 31
    LI x2, 0x0C000000
    OR x2, x2, x4
    SLLI x4, x15, 5
    OR x2, x2, x4
    ADDI x4, x11, 120
    SLLI x4, x4, 15
    OR x2, x2, x4
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 3
    SW x4, 0(x1)
    LI x1, MMIO_VGA_OBJ_WORD0
    SW x2, 0(x1)

skip_draw:

    JALR zero, 0(x14)

# --------------------------------------------------------
# FONT SUBROUTINE (0-9)
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
