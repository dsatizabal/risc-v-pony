# invaders_auto.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o invaders_auto.elf invaders_auto.S
# Extract: riscv64-unknown-elf-objcopy -O binary invaders_auto.elf invaders_auto.bin

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
    # 1. SETUP STATIC BACKGROUND & PATTERNS
    # --------------------------------------------------------
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x00; sw x2, 0(x1) # Black Sky
    
    # Rect 7: Green Ground Line
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80001b80; sw x2, 0(x1) # Y=220
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x50028600; sw x3, 0(x1) # W=320, H=20, Green

    # Sprite 4: Player Ship (White)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x18183C7E; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0xFFFFFFFF; sw x3, 0(x1)

    # Sprite 5: Bullet (Yellow Line)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x18181818; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x18181818; sw x3, 0(x1)

    li x1, MMIO_VGA_CTRL; li x2, 1; sw x2, 0(x1)

    # --------------------------------------------------------
    # 2. STATE REGISTERS (Strict RV32E Limits)
    # --------------------------------------------------------
    li x6, 160          # Player X
    li x7, 0xFFFFF      # 20-bit ALIVE MASK (All 20 aliens alive)
    li x8, 200          # Bullet Y
    li x9, 0            # Score
    li x10, 164         # Bullet X
    li x11, 60          # Armada Base X
    li x13, 0           # Global Frame Counter (32-bit continuous)

game_loop:
    # --- WAIT FOR VBLANK ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank
    addi x13, x13, 1        # Increment continuous frame counter

    # --------------------------------------------------------
    # 3. AUTONOMOUS PHYSICS & COLLISION
    # --------------------------------------------------------
    
    # Player Auto-Sweep (Uses global frame counter sine-wave trick)
    srli x4, x13, 2         # Divide frames by 4
    andi x4, x4, 255        # Wrap at 255
    li x5, 128; blt x4, x5, p_right
    li x6, 256; sub x6, x6, x4; j p_done    # Moving Left
p_right: li x6, 40; add x6, x6, x4          # Moving Right
p_done:

    # Armada Auto-Wobble
    srli x4, x13, 4         # Divide frames by 16
    andi x4, x4, 63         # Wrap at 63
    li x5, 32; blt x4, x5, a_right
    li x11, 100; sub x11, x11, x4; j a_done # Moving Left
a_right: li x11, 40; add x11, x11, x4       # Moving Right
a_done:

    # Bullet Movement
    addi x8, x8, -4
    li x4, 10; bge x8, x4, check_hit
reload_bullet:
    li x8, 200              # Reload to Player Y
    addi x10, x6, 4         # Center on Player X
    j draw_fixed

check_hit:
    # --- EXACT COLLISION DETECTION ---
    # 1. Check Y Bounds
    addi x4, x8, -20        # Bullet Y - Armada Top
    blt x4, zero, draw_fixed
    li x5, 150
    bge x4, x5, draw_fixed

    # Find Row (0 to 4)
    li x12, 0; li x5, 30
row_loop: blt x4, x5, row_found; sub x4, x4, x5; addi x12, x12, 1; j row_loop
row_found:
    li x5, 12; bge x4, x5, draw_fixed   # Hit the empty gap between rows!

    # 2. Check X Bounds
    sub x4, x10, x11        # Bullet X - Armada Base X
    addi x4, x4, 4          # Forgiveness width
    blt x4, zero, draw_fixed
    li x5, 160
    bge x4, x5, draw_fixed

    # Find Col (0 to 3)
    li x2, 0; li x5, 40
col_loop: blt x4, x5, col_found; sub x4, x4, x5; addi x2, x2, 1; j col_loop
col_found:
    li x5, 14; bge x4, x5, draw_fixed   # Hit the empty gap between columns!

    # 3. Check Alive Mask
    slli x4, x12, 2         # Row * 4
    add x4, x4, x2          # + Col (Bit Index)
    li x5, 1; sll x5, x5, x4
    and x2, x7, x5
    beq x2, zero, draw_fixed # Bullet passed through a dead alien!

    # HIT! Kill Alien, Update Score, Reload Bullet
    xor x7, x7, x5          # Flip the alive bit to 0!
    addi x9, x9, 1          # Score++
    li x4, 99; ble x9, x4, skip_cap; li x9, 0
skip_cap:
    beq x7, zero, respawn_armada
    j reload_bullet
respawn_armada:
    li x7, 0xFFFFF          # Revive all aliens!
    j reload_bullet


draw_fixed:
    # --------------------------------------------------------
    # 4. DRAW FIXED OBJECTS & SCORE
    # --------------------------------------------------------
    # Player (Sprite 4)
    li x5, 0xfe000000; slli x4, x6, 15; or x5, x5, x4; li x4, 210; slli x4, x4, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # Bullet (Sprite 5)
    li x5, 0xfa000000; slli x4, x10, 15; or x5, x5, x4; slli x4, x8, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # Score (Sprites 0 & 1)
    mv x5, x9; li x4, 0; li x2, 10
s_div: blt x5, x2, s_div_done; sub x5, x5, x2; addi x4, x4, 1; j s_div
s_div_done:
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 0; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 10; slli x3, x3, 15; or x2, x2, x3; li x3, 10; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    jal x14, get_font; li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1); li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)
    
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 1; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 18; slli x3, x3, 15; or x2, x2, x3; li x3, 10; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    mv x4, x5
    jal x14, get_font; li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1); li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # --------------------------------------------------------
    # 5. VERTICAL MULTIPLEXING (RACING THE BEAM)
    # --------------------------------------------------------
    li x3, MMIO_LINE_COUNTER
wait_line_20: lw x4, 0(x3); li x5, 20; blt x4, x5, wait_line_20

    # Load Alien Graphic Pattern into Sprites 0,1,2,3
    li x1, MMIO_VGA_OBJ_INDEX; li x2, MMIO_VGA_OBJ_WORD1; li x10, MMIO_VGA_OBJ_WORD2
    li x4, 0x183C7EDB; li x5, 0xFF245AA5
    li x14, 0; sw x14, 0(x1); sw x4, 0(x2); sw x5, 0(x10)
    li x14, 1; sw x14, 0(x1); sw x4, 0(x2); sw x5, 0(x10)
    li x14, 2; sw x14, 0(x1); sw x4, 0(x2); sw x5, 0(x10)
    li x14, 3; sw x14, 0(x1); sw x4, 0(x2); sw x5, 0(x10)

    # Draw the 5 Rows!
    li x12, 0; li x15, 20;  jal x14, draw_alien_row
wait_line_50: lw x4, 0(x3); li x5, 50; blt x4, x5, wait_line_50
    li x12, 1; li x15, 50;  jal x14, draw_alien_row
wait_line_80: lw x4, 0(x3); li x5, 80; blt x4, x5, wait_line_80
    li x12, 2; li x15, 80;  jal x14, draw_alien_row
wait_line_110: lw x4, 0(x3); li x5, 110; blt x4, x5, wait_line_110
    li x12, 3; li x15, 110; jal x14, draw_alien_row
wait_line_140: lw x4, 0(x3); li x5, 140; blt x4, x5, wait_line_140
    li x12, 4; li x15, 140; jal x14, draw_alien_row

    # Restore Bullet X from Player X for the next frame physics calculation
    addi x10, x6, 4 

    j game_loop

# --------------------------------------------------------
# SUBROUTINE: Draw 4 Aliens (Masked by Alive Mask & Intro Sequence)
# Inputs: x12 = Row Index, x15 = Target Y
# --------------------------------------------------------
draw_alien_row:
    # 1. The Line-by-Line Appearance Sequence
    srli x4, x13, 5         # Reveal 1 row every 32 frames (~0.5 sec)
    li x5, 5; blt x4, x5, check_vis; li x4, 5
check_vis:
    bge x12, x4, skip_draw  # Skip drawing if row isn't visible yet

    # 2. Extract the 4 alive bits for this specific row
    slli x4, x12, 2         # Row * 4
    srl x5, x7, x4          # Shift alive mask so this row is at the bottom

    # Draw Sprite 0 (Col 0)
    andi x4, x5, 1; slli x4, x4, 31         # If alive, x4 = 0x80000000 (Enable=1)
    li x2, 0x0c000000; or x2, x2, x4        # Base: Color Green
    slli x4, x15, 5; or x2, x2, x4          # Pack Y
    slli x4, x11, 15; or x2, x2, x4         # Pack X
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)

    # Draw Sprite 1 (Col 1)
    srli x5, x5, 1
    andi x4, x5, 1; slli x4, x4, 31
    li x2, 0x0c000000; or x2, x2, x4
    slli x4, x15, 5; or x2, x2, x4
    addi x4, x11, 40; slli x4, x4, 15; or x2, x2, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)

    # Draw Sprite 2 (Col 2)
    srli x5, x5, 1
    andi x4, x5, 1; slli x4, x4, 31
    li x2, 0x0c000000; or x2, x2, x4
    slli x4, x15, 5; or x2, x2, x4
    addi x4, x11, 80; slli x4, x4, 15; or x2, x2, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)

    # Draw Sprite 3 (Col 3)
    srli x5, x5, 1
    andi x4, x5, 1; slli x4, x4, 31
    li x2, 0x0c000000; or x2, x2, x4
    slli x4, x15, 5; or x2, x2, x4
    addi x4, x11, 120; slli x4, x4, 15; or x2, x2, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)

skip_draw:
    jalr zero, 0(x14)

# --------------------------------------------------------
# FONT SUBROUTINE (0-9)
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