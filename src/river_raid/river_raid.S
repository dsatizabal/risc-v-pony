# river_raid_auto.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o river_raid_auto.elf river_raid_auto.S
# Extract: riscv64-unknown-elf-objcopy -O binary river_raid_auto.elf river_raid_auto.bin

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
    # 1. SETUP STATIC SCENE
    # --------------------------------------------------------
    # Background: Blue (0x03)
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x03; sw x2, 0(x1)

    # Rect 4: Top Score Bar (Black, X=0, Y=0, W=320, H=24)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80000000; sw x2, 0(x1) 
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x50030000; sw x3, 0(x1) 

    # Rect 5: Left River Bank (Green, X=0, Y=24, W=40, H=216)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80000300; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x0a1b0600; sw x3, 0(x1)

    # Rect 6: Right River Bank (Green, X=280, Y=24, W=40, H=216)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80000300
    li x3, 280; slli x3, x3, 15; or x2, x2, x3; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x0a1b0600; sw x3, 0(x1)

    # Sprite 0: Plane Pattern (White)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x183C7EFF; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0xFF7E3C18; sw x3, 0(x1)

    # Sprite 1: Enemy Ship Pattern (Red)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0xFFDB7E3C; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x18181818; sw x3, 0(x1)

    # Sprite 2: Bullet Pattern (Yellow line)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x18181818; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x18181818; sw x3, 0(x1)

    li x1, MMIO_VGA_CTRL; li x4, 1; sw x4, 0(x1)

    # --------------------------------------------------------
    # 2. INITIALIZE GAME STATE REGISTERS
    # --------------------------------------------------------
    li x6, 160      # Plane X
    li x7, 160      # Enemy X
    li x8, 24       # Enemy Y
    li x9, 160      # Bullet X
    li x10, 200     # Bullet Y
    li x11, 24      # Island Y (Rect 7)
    li x12, 0       # Score

game_loop:
    # --- WAIT FOR VBLANK ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank

    # --- WORLD PHYSICS ---
    # Scroll Island
    addi x11, x11, 2
    li x4, 240
    blt x11, x4, skip_island_reset
    li x11, -40
skip_island_reset:

    # Move Enemy Down
    addi x8, x8, 1
    li x4, 230
    blt x8, x4, skip_enemy_reset
    li x8, 24
    # Pseudo-random X based on frame counter
    andi x7, x2, 127
    addi x7, x7, 60
skip_enemy_reset:

    # Move Bullet Up
    addi x10, x10, -4
    li x4, 24
    bge x10, x4, check_collision
    # Reload bullet to plane
    mv x9, x6
    li x10, 200

check_collision:
    # AABB Collision (Bullet vs Enemy)
    # Is Bullet X >= Enemy X ?
    blt x9, x7, ai_update
    # Is Bullet X < Enemy X + 8 ?
    addi x4, x7, 8
    bge x9, x4, ai_update
    # Is Bullet Y >= Enemy Y ?
    blt x10, x8, ai_update
    # Is Bullet Y < Enemy Y + 8 ?
    addi x4, x8, 8
    bge x10, x4, ai_update

    # HIT!
    addi x12, x12, 1        # Score++
    li x4, 99
    ble x12, x4, skip_score_cap
    li x12, 0
skip_score_cap:
    li x8, 24               # Reset Enemy Y
    andi x7, x2, 127        # Pseudo Random X
    addi x7, x7, 60
    li x10, 24              # Move bullet offscreen to reload

ai_update:
    # Plane chases Enemy X
    beq x6, x7, clamp_plane
    blt x6, x7, plane_right
    addi x6, x6, -1; j clamp_plane
plane_right:
    addi x6, x6, 1
clamp_plane:
    # Keep plane inside river banks
    li x4, 40; blt x6, x4, fix_p_l
    li x4, 272; bge x6, x4, fix_p_r
    j render_graphics
fix_p_l: li x6, 40; j render_graphics
fix_p_r: li x6, 272

render_graphics:
    # --- RENDER SCORE ---
    mv x5, x12; li x4, 0; li x2, 10
score_div: blt x5, x2, score_div_done; sub x5, x5, x2; addi x4, x4, 1; j score_div
score_div_done:
    # Tens (Sprite 3, Yellow, X=150)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 3; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 150; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)
    
    # Ones (Sprite 4, Yellow, X=158)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 4; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 158; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    mv x4, x5
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # --- RENDER ISLAND (Rect 7) ---
    li x5, 0x98000000       # Enable=1, Color=Green (0x0C << 25 = 0x18000000. +80 = 0x98)
    li x4, 150; slli x4, x4, 15; or x5, x5, x4
    slli x4, x11, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x05014000; sw x2, 0(x1) # W=20, H=10

    # --- RENDER PLANE (Sprite 0) ---
    li x5, 0xfe000000       # Enable=1, Color=White
    slli x4, x6, 15; or x5, x5, x4
    li x4, 200; slli x4, x4, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # --- RENDER ENEMY (Sprite 1) ---
    li x5, 0xe0000000       # Enable=1, Color=Red
    slli x4, x7, 15; or x5, x5, x4
    slli x4, x8, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # --- RENDER BULLET (Sprite 2) ---
    li x5, 0xf8000000       # Enable=1, Color=Yellow
    slli x4, x9, 15; or x5, x5, x4
    slli x4, x10, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    j game_loop

# --------------------------------------------------------
# FONT SUBROUTINE
# --------------------------------------------------------
get_font:
    li x15, 1; beq x4, x15, f_1
    li x15, 2; beq x4, x15, f_2
    li x15, 3; beq x4, x15, f_3
    li x15, 4; beq x4, x15, f_4
    li x15, 5; beq x4, x15, f_5
    li x15, 6; beq x4, x15, f_6
    li x15, 7; beq x4, x15, f_7
    li x15, 8; beq x4, x15, f_8
    li x15, 9; beq x4, x15, f_9
f_0: li x2, 0x3C666666; li x3, 0x6666663C; jalr zero, 0(x14)
f_1: li x2, 0x18381818; li x3, 0x1818187E; jalr zero, 0(x14)
f_2: li x2, 0x3C66060C; li x3, 0x1830607E; jalr zero, 0(x14)
f_3: li x2, 0x3C66061C; li x3, 0x0606663C; jalr zero, 0(x14)
f_4: li x2, 0x0C1C3C6C; li x3, 0xCCFE0C0C; jalr zero, 0(x14)
f_5: li x2, 0x7E607C06; li x3, 0x0606663C; jalr zero, 0(x14)
f_6: li x2, 0x3C66607C; li x3, 0x6666663C; jalr zero, 0(x14)
f_7: li x2, 0x7E06060C; li x3, 0x18181818; jalr zero, 0(x14)
f_8: li x2, 0x3C66663C; li x3, 0x6666663C; jalr zero, 0(x14)
f_9: li x2, 0x3C666666; li x3, 0x3E06063C; jalr zero, 0(x14)