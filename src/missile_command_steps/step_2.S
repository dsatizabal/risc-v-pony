# mc_step2.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o mc_step2.elf mc_step2.S
# Extract: riscv64-unknown-elf-objcopy -O binary mc_step2.elf mc_step2.bin

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
    # 1. SETUP BACKGROUND & ENABLE
    # --------------------------------------------------------
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x00; sw x2, 0(x1) 
    li x1, MMIO_VGA_CTRL; li x2, 1; sw x2, 0(x1)

    li x13, 0       # Global Frame Counter
    li x6, 160      # Cursor X
    li x7, 100      # Cursor Y

game_loop:
    # ========================================================
    # PHASE 1: VBLANK (Draw Score & Cursor)
    # ========================================================
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank
    addi x13, x13, 1

    # --- Auto-Move Cursor (Figure-8) ---
    srli x4, x13, 1; andi x4, x4, 127
    li x5, 64; blt x4, x5, cx_right
    li x6, 128; sub x6, x6, x4; j calc_cy
cx_right: mv x6, x4
calc_cy: slli x6, x6, 1; addi x6, x6, 60     # X bounds: 60 to 188
    srli x4, x13, 2; andi x4, x4, 63
    li x5, 32; blt x4, x5, cy_down
    li x7, 64; sub x7, x7, x4; j apply_cy
cy_down: mv x7, x4
apply_cy: slli x7, x7, 1; addi x7, x7, 40    # Y bounds: 40 to 104

    # --- Draw Score "200" (Sprites 0, 1, 2) White=0xfe ---
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x4, 0xfe000000; li x5, 130; slli x5, x5, 15; or x4, x4, x5; li x5, 15; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 2; jal x14, get_font
    
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x4, 0xfe000000; li x5, 140; slli x5, x5, 15; or x4, x4, x5; li x5, 15; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 0; jal x14, get_font

    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x4, 0xfe000000; li x5, 150; slli x5, x5, 15; or x4, x4, x5; li x5, 15; slli x5, x5, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x4, 0; jal x14, get_font

    # --- Draw Cursor (Sprite 3) White Vertical Line ---
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x4, 0xfe000000; slli x5, x6, 15; or x4, x4, x5; slli x5, x7, 5; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x5, 0x18181818; sw x5, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x5, 0x18181818; sw x5, 0(x1)

    # ========================================================
    # PHASE 2: RACING THE BEAM (Wait for Top of Screen)
    # ========================================================
    li x3, MMIO_LINE_COUNTER
wait_line_0: 
    lw x4, 0(x3); bne x4, zero, wait_line_0  # Fixes the missing score bug!

wait_line_40: 
    lw x4, 0(x3); li x5, 40; blt x4, x5, wait_line_40

    # Hide Score Sprites (0, 1, 2)
    li x1, MMIO_VGA_OBJ_INDEX
    li x4, 0; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)
    li x4, 1; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)
    li x4, 2; sw x4, 0(x1); li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)

    # ========================================================
    # PHASE 3: DRAW TERRAIN & CITIES (Wait for Line 180)
    # ========================================================
wait_line_180: 
    lw x4, 0(x3); li x5, 180; blt x4, x5, wait_line_180

    # Hide Cursor (Sprite 3) so we can reuse it!
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; sw zero, 0(x4)

    # --- Draw Terrain (Rects 4, 5, 6, 7) Red 0x30 ---
    li x1, MMIO_VGA_OBJ_INDEX
    # Rect 7: Floor (Y=220, W=320, H=20)
    li x4, 7; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80001b80; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x50029800; sw x5, 0(x4)

    # Rect 6: Center Mountain (X=130, Y=200, W=60, H=20)
    li x4, 6; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80411900; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x0f029800; sw x5, 0(x4)

    # Rect 5: Left Step (X=0, Y=210, W=20, H=10) <--- NARROWED
    li x4, 5; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80001a40; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x05015800; sw x5, 0(x4) 

    # Rect 4: Right Step (X=300, Y=210, W=20, H=10) <--- NARROWED
    li x4, 4; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x80961a40; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x05015800; sw x5, 0(x4)

    # --- Draw Center Base (Sprite 0, Red) ---
    li x4, 0; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0xe0501840; sw x5, 0(x4) # X=160, Y=194
    li x4, MMIO_VGA_OBJ_WORD1; li x5, 0x183C7EFF; sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD2; li x5, 0xFFFFFFFF; sw x5, 0(x4)

    # --- TIME-DIVISION MULTIPLEXING: CITIES (Blue 0x03) ---
    andi x8, x13, 1
    beq x8, zero, draw_right_cities

draw_left_cities:
    # City 1 (Sprite 1, X=30)
    li x4, 1; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x860f1a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 2 (Sprite 2, X=65)
    li x4, 2; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86201a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 3 (Sprite 3, X=100) <--- SPRITE 3 REUSED!
    li x4, 3; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86321a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    j game_loop

draw_right_cities:
    # City 4 (Sprite 1, X=200)
    li x4, 1; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86641a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 5 (Sprite 2, X=235)
    li x4, 2; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0; li x5, 0x86751a80; sw x5, 0(x4)
    jal x14, load_city_gfx
    # City 6 (Sprite 3, X=270) <--- SPRITE 3 REUSED!
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