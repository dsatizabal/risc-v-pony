# mc_step4.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o mc_step4.elf mc_step4.S
# Extract: riscv64-unknown-elf-objcopy -O binary mc_step4.elf mc_step4.bin

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
    li x1, MMIO_VGA_BG_COLOR;
    li x2, 0x00;
    sw x2, 0(x1)
    li x1, MMIO_VGA_CTRL;
    li x2, 1;
    sw x2, 0(x1)

    li x13, 0       # Global Frame Counter
    li x6, 160      # Cursor X
    li x7, 100      # Cursor Y
    li x8, 0        # Missile 1 Length
    li x9, 0        # Missile 2 Length

    # --- Explosion Registers ---
    li x10, 0       # Explosion Timer (0 = Off)
    li x11, 0       # Latched Explosion X
    li x12, 0       # Latched Explosion Y

game_loop:
    # ========================================================
    # PHASE 1: VBLANK (Physics, Top-Screen Rendering)
    # ========================================================
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank
    addi x13, x13, 1

    # --- Auto-Move Cursor ---
    srli x4, x13, 1;
    andi x4, x4, 127
    li x5, 64;
    blt x4, x5, cx_right
    li x6, 128;
    sub x6, x6, x4;
    j calc_cy
cx_right:
    mv x6, x4
calc_cy:
    slli x6, x6, 1;
    addi x6, x6, 60
    srli x4, x13, 2;
    andi x4, x4, 63
    li x5, 32;
    blt x4, x5, cy_down
    li x7, 64;
    sub x7, x7, x4;
    j apply_cy
cy_down:
    mv x7, x4
apply_cy:
    slli x7, x7, 1;
    addi x7, x7, 40

    # --- Grow Missiles ---
    addi x8, x8, 1;
    li x4, 180;
    blt x8, x4, skip_m1;
    li x8, 0
skip_m1:
    andi x4, x13, 1;
    beq x4, zero, skip_m2
    addi x9, x9, 1;
    li x4, 180;
    blt x9, x4, skip_m2;
    li x9, 0
skip_m2:
    # --- Explosion Trigger (Every ~128 frames) ---
    bne x10, zero, process_expl
    andi x4, x13, 127
    bne x4, zero, skip_expl
    # Fire Explosion!
    li x10, 1
    mv x11, x6      # Latch Cursor X
    mv x12, x7      # Latch Cursor Y
    j skip_expl

process_expl:
    addi x10, x10, 1;
    li x4, 40
    blt x10, x4, skip_expl
    li x10, 0       # End explosion

skip_expl:
    # --- Draw Score "200" (Sprites 0, 1, 2) White ---
    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 0;
    sw x4, 0(x1)
    li x4, 0xfe000000;
    li x5, 130;
    slli x5, x5, 15;
    or x4, x4, x5;
    li x5, 15;
    slli x5, x5, 5;
    or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0;
    sw x4, 0(x1)
    li x4, 2;
    jal x14, get_font

    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 1;
    sw x4, 0(x1)
    li x4, 0xfe000000;
    li x5, 140;
    slli x5, x5, 15;
    or x4, x4, x5;
    li x5, 15;
    slli x5, x5, 5;
    or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0;
    sw x4, 0(x1)
    li x4, 0;
    jal x14, get_font

    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 2;
    sw x4, 0(x1)
    li x4, 0xfe000000;
    li x5, 150;
    slli x5, x5, 15;
    or x4, x4, x5;
    li x5, 15;
    slli x5, x5, 5;
    or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0;
    sw x4, 0(x1)
    li x4, 0;
    jal x14, get_font

    # --- Draw Cursor (Sprite 3) Horizontal Line ---
    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 3;
    sw x4, 0(x1)
    li x4, 0xfe000000;
    slli x5, x6, 15;
    or x4, x4, x5;
    slli x5, x7, 5;
    or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD0;
    sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1;
    li x5, 0x0000FF00;
    sw x5, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2;
    sw zero, 0(x1)

    # --- Draw Missile 1 (Line 8) ---
    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 8;
    sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0;
    li x4, 0x801e0000;
    sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1;
    slli x4, x8, 22;
    li x5, 0x1800;
    or x4, x4, x5;
    sw x4, 0(x1)

    # --- Draw Missile 2 (Line 9) ---
    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 9;
    sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0;
    li x4, 0x80820000;
    sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1;
    slli x4, x9, 22;
    li x5, 0x00201800;
    or x4, x4, x5;
    sw x4, 0(x1)

    # --- DRAW EXPLOSION (Using Rect 4 temporarily in the sky!) ---
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    beq x10, zero, hide_expl

    # Calculate Size (Grow to 20, shrink to 0)
    li x4, 20;
    blt x10, x4, expl_grow
    li x15, 40;
    sub x15, x15,
    x10; j expl_apply
expl_grow:
    mv x15, x10
expl_apply:
    slli x15, x15, 1    # Multiply by 2 for width/height (max 40x40)

    # Calculate Centered X/Y
    srli x4, x15, 1             # Half size
    sub x5, x11, x4             # X
    sub x2, x12, x4             # Y

    # Draw Word 0 (Enable + X + Y)
    li x4, 0x80000000;
    slli x5, x5, 15;
    or x4, x4, x5;
    slli x2, x2, 5;
    or x4, x4, x2
    li x1, MMIO_VGA_OBJ_WORD0;
    sw x4, 0(x1)

    # Draw Word 1 (Width + Height + STROBE COLOR)
    slli x4, x15, 22            # Width
    slli x2, x15, 13;
    or x4, x4, x2 # Height
    andi x2, x13, 0x3F          # Fast Frame Counter
    slli x2, x2, 7;
    or x4, x4, x2 # Shift into Color position
    li x1, MMIO_VGA_OBJ_WORD1;
    sw x4, 0(x1)
    j sync_beam

hide_expl:
    li x1, MMIO_VGA_OBJ_WORD0;
    sw zero, 0(x1)

    # ========================================================
    # PHASE 2: RACING THE BEAM (Wait for Top of Screen)
    # ========================================================
sync_beam:
    li x3, MMIO_LINE_COUNTER
wait_line_0:
    lw x4, 0(x3);
    bne x4, zero, wait_line_0
wait_line_40:
    lw x4, 0(x3);
    li x5, 40;
    blt x4, x5, wait_line_40

    # Hide Score Sprites (0, 1, 2)
    li x1, MMIO_VGA_OBJ_INDEX
    li x4, 0;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    sw zero, 0(x4)
    li x4, 1;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    sw zero, 0(x4)
    li x4, 2;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    sw zero, 0(x4)

    # ========================================================
    # PHASE 3: DRAW TERRAIN & CITIES (Wait for Line 180)
    # ========================================================
wait_line_180:
    lw x4, 0(x3);
    li x5, 180;
    blt x4, x5, wait_line_180

    # Hide Cursor (Sprite 3)
    li x1, MMIO_VGA_OBJ_INDEX;
    li x4, 3; sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0;
    sw zero, 0(x4)

    # --- Draw Terrain (Rects 4, 5, 6, 7) Red 0x30 ---
    li x1, MMIO_VGA_OBJ_INDEX
    li x4, 7;
    sw x4, 0(x1) # Floor
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x80001b80;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x50029800;
    sw x5, 0(x4)

    li x4, 6;
    sw x4, 0(x1) # Mountain
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x80411900;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x0f029800;
    sw x5, 0(x4)

    li x4, 5;
    sw x4, 0(x1) # Left Step
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x80001a40;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x05015800;
    sw x5, 0(x4)

    # OVERWRITING EXPLOSION (Rect 4) WITH TERRAIN
    li x4, 4;
    sw x4, 0(x1) # Right Step
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x80961a40;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x05015800;
    sw x5, 0(x4)

    # --- Draw Center Base (Sprite 0, Red) ---
    li x4, 0;
    sw x4, 0(x1)
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0xe0501840;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x183C7EFF;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD2;
    li x5, 0xFFFFFFFF;
    sw x5, 0(x4)

    # --- TIME-DIVISION MULTIPLEXING: CITIES ---
    # FIXED: Safely using x4 instead of clobbering our x10 timer!
    andi x4, x13, 1
    beq x4, zero, draw_right_cities
draw_left_cities:
    li x4, 1;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x860f1a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    li x4, 2;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x86201a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    li x4, 3;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x86321a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    j game_loop
draw_right_cities:
    li x4, 1;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x86641a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    li x4, 2;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x86751a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    li x4, 3;
    sw x4, 0(x1);
    li x4, MMIO_VGA_OBJ_WORD0;
    li x5, 0x86871a80;
    sw x5, 0(x4);
    jal x14, load_city_gfx
    j game_loop

# --------------------------------------------------------
# SUBROUTINES
# --------------------------------------------------------
load_city_gfx:
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x003C7E7E;
    sw x5, 0(x4)
    li x4, MMIO_VGA_OBJ_WORD2;
    li x5, 0xFFFFFFFF;
    sw x5, 0(x4)
    jalr zero, 0(x14)

get_font:
    li x15, 1;
    beq x4, x15, f_1;
    li x15, 2;
    beq x4, x15, f_2
f_0:
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x3C666666;
    sw x5, 0(x4);
    li x4, MMIO_VGA_OBJ_WORD2;
    li x5, 0x6666663C;
    sw x5, 0(x4);
    jalr zero, 0(x14)
f_1:
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x18381818;
    sw x5, 0(x4);
    li x4, MMIO_VGA_OBJ_WORD2;
    li x5, 0x1818187E;
    sw x5, 0(x4);
    jalr zero, 0(x14)
f_2:
    li x4, MMIO_VGA_OBJ_WORD1;
    li x5, 0x3C66060C;
    sw x5, 0(x4);
    li x4, MMIO_VGA_OBJ_WORD2;
    li x5, 0x1830607E;
    sw x5, 0(x4);
    jalr zero, 0(x14)
