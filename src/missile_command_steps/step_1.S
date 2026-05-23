# mc_step1.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o mc_step1.elf mc_step1.S
# Extract: riscv64-unknown-elf-objcopy -O binary mc_step1.elf mc_step1.bin

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
    # 1. SETUP BACKGROUND
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x00; sw x2, 0(x1) 

    # Enable VGA
    li x1, MMIO_VGA_CTRL; li x2, 1; sw x2, 0(x1)

    li x13, 0       # Global Frame Counter

game_loop:
    # ========================================================
    # VBLANK: RENDER SCORE AT TOP OF SCREEN
    # ========================================================
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank
    addi x13, x13, 1

    # Draw "1" (Sprite 0, X=130, Y=20, Color=Red/Orange 0x38)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x4, 0xf0000000; li x5, 130; slli x5, x5, 15; or x4, x4, x5; li x5, 20; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 1; jal x14, get_font
    
    # Draw "0" (Sprite 1, X=140, Y=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x4, 0xf0000000; li x5, 140; slli x5, x5, 15; or x4, x4, x5; li x5, 20; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 0; jal x14, get_font

    # Draw "0" (Sprite 2, X=150, Y=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x4, 0xf0000000; li x5, 150; slli x5, x5, 15; or x4, x4, x5; li x5, 20; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 0; jal x14, get_font

    # Hide Sprite 3 for now
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw zero, 0(x1)

    # ========================================================
    # RACING THE BEAM: WAIT FOR LINE 40 TO HIDE SCORE
    # ========================================================
    li x3, MMIO_LINE_COUNTER
wait_line_40: lw x4, 0(x3); li x5, 40; blt x4, x5, wait_line_40

    # If we don't hide them, the Sprites will drag down the screen!
    li x1, MMIO_VGA_OBJ_INDEX
    li x4, 0; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)
    li x4, 1; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)
    li x4, 2; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)

    # ========================================================
    # RACING THE BEAM: WAIT FOR LINE 180 TO DRAW GROUND
    # ========================================================
wait_line_180: lw x4, 0(x3); li x5, 180; blt x4, x5, wait_line_180

    # --- Draw Terrain (Rects 4, 5, 6, 7) Color Red 0x30 ---
    li x1, MMIO_VGA_OBJ_INDEX
    # Rect 7: Floor (Y=220, W=320, H=20)
    li x4, 7; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80001b80; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x50029800; sw x5, 0(x4)

    # Rect 6: Center Mountain (X=130, Y=200, W=60, H=20)
    li x4, 6; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80411900; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x0f029800; sw x5, 0(x4)

    # Rect 5: Left Step (X=0, Y=210, W=40, H=10)
    li x4, 5; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80001a40; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x0a015800; sw x5, 0(x4)

    # Rect 4: Right Step (X=280, Y=210, W=40, H=10)
    li x4, 4; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x808c1a40; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x0a015800; sw x5, 0(x4)

    # --- Draw Center Base (Sprite 0, Red) ---
    li x4, 0; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0xe0501840; sw x5, 0(x4) # X=160, Y=194
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x183C7EFF; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD2; li x5, 0xFFFFFFFF; sw x5, 0(x4)

    # --- TIME-DIVISION MULTIPLEXING: CITIES (Blue 0x03) ---
    andi x6, x13, 1
    beq x6, zero, draw_right_cities

draw_left_cities:
    # City 1 (Sprite 1, X=30, Y=212)
    li x4, 1; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x860f1a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 2 (Sprite 2, X=70, Y=212)
    li x4, 2; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86231a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 3 (Sprite 3, X=110, Y=212)
    li x4, 3; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86371a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    j game_loop

draw_right_cities:
    # City 4 (Sprite 1, X=190, Y=212)
    li x4, 1; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x865f1a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 5 (Sprite 2, X=230, Y=212)
    li x4, 2; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86731a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 6 (Sprite 3, X=270, Y=212)
    li x4, 3; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86871a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    
    j game_loop

# --------------------------------------------------------
# SUBROUTINES
# --------------------------------------------------------
load_city_gfx:
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x003C7E7E; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD2; li x5, 0xFFFFFFFF; sw x5, 0(x4)
    jalr zero, 0(x14)

get_font:
    li x15, 1; beq x4, x15, f_1
    li x15, 2; beq x4, x15, f_2
f_0: li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x3C666666; sw x5, 0(x4); li x4, MMIO_VGA_OBJ_WORD2; li x5, 0x6666663C; sw x5, 0(x4); jalr zero, 0(x14)
f_1: li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x18381818; sw x5, 0(x4); li x4, MMIO_VGA_OBJ_WORD2; li x5, 0x1818187E; sw x5, 0(x4); jalr zero, 0(x14)
f_2: li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x3C66060C; sw x5, 0(x4); li x4, MMIO_VGA_OBJ_WORD2; li x5, 0x1830607E; sw x5, 0(x4); jalr zero, 0(x14)