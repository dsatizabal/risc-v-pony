# missile_cmd_auto.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o missile_cmd_auto.elf missile_cmd_auto.S
# Extract: riscv64-unknown-elf-objcopy -O binary missile_cmd_auto.elf missile_cmd_auto.bin

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
    # 1. SETUP STATIC SCENE (Cities & Ground)
    # --------------------------------------------------------
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x00; sw x2, 0(x1) 

    # Rect 7: Ground (Green, Y=220, W=320, H=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80001b80; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x50028600; sw x3, 0(x1)

    # Rect 6: City 1 (Cyan, X=60, Y=200, W=20, H=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x801e1900; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x05028780; sw x3, 0(x1)

    # Rect 5: City 2 (Cyan, X=150, Y=200, W=20, H=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x804b1900; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x05028780; sw x3, 0(x1)

    # Rect 4: City 3 (Cyan, X=240, Y=200, W=20, H=20)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80781900; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x05028780; sw x3, 0(x1)

    # Sprite 2: Enemy Missile (Red Ball)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x183C3C18; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x00000000; sw x3, 0(x1)

    # Sprite 3: Crosshair (White Plus)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x08083E08; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x08000000; sw x3, 0(x1)

    li x1, MMIO_VGA_CTRL; li x2, 1; sw x2, 0(x1)

    # --------------------------------------------------------
    # 2. STATE REGISTERS
    # --------------------------------------------------------
    li x6, 280      # Enemy X
    li x7, 30       # Enemy Y
    li x8, 160      # Crosshair X
    li x9, 200      # Crosshair Y
    li x10, 0       # Explosion Timer (0 = Inactive)
    li x11, 0       # Score

game_loop:
    # --- WAIT FOR VBLANK ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank

    # --- PHYSICS & AI ---
    bne x10, zero, handle_explosion

    # 1. Move Enemy (Down-Left)
    addi x6, x6, -1
    addi x7, x7, 1

    # 2. Crosshair AI (Tracks Enemy aggressively)
    beq x8, x6, track_y
    blt x8, x6, move_cr_right
    addi x8, x8, -2; j track_y
move_cr_right: 
    addi x8, x8, 2
track_y:
    beq x9, x7, check_hit
    blt x9, x7, move_cr_down
    addi x9, x9, -2; j check_hit
move_cr_down: 
    addi x9, x9, 2

check_hit:
    # 3. Collision Detection (Abs(dX) < 4 && Abs(dY) < 4)
    sub x4, x6, x8
    bge x4, zero, abs_x; sub x4, zero, x4   # x4 = Abs(dX)
abs_x: 
    li x5, 4; bge x4, x5, check_floor
    
    sub x4, x7, x9
    bge x4, zero, abs_y; sub x4, zero, x4   # x4 = Abs(dY)
abs_y: 
    li x5, 4; bge x4, x5, check_floor

    # HIT! Trigger Explosion & Score++
    li x10, 1
    addi x11, x11, 1
    li x4, 99; ble x11, x4, render; li x11, 0; j render

check_floor:
    # 4. Did Enemy hit the cities? (Y >= 200)
    li x4, 200
    blt x7, x4, render
    # Missed! Reset Enemy and Crosshair
    li x6, 280; li x7, 30
    li x8, 160; li x9, 200
    j render

handle_explosion:
    # 5. Advance Explosion Timer
    addi x10, x10, 1
    li x4, 60                   # Explosion lasts 60 frames (1 sec)
    blt x10, x4, render_explosion
    
    # End Explosion, Reset actors
    li x10, 0
    li x6, 280; li x7, 30
    li x8, 160; li x9, 200
    
    # Hide Sprite 4 (Explosion)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw zero, 0(x1)
    j render

render_explosion:
    # Determine pattern based on timer x10
    li x4, 20; blt x10, x4, exp_small
    li x4, 40; blt x10, x4, exp_med
exp_large:
    li x2, 0x3C428181; li x3, 0x423C0000; j draw_exp
exp_med:
    li x2, 0x3C7EFFFF; li x3, 0x7E3C0000; j draw_exp
exp_small:
    li x2, 0x00183C18; li x3, 0x00000000
draw_exp:
    # Draw Explosion at Crosshair location (Sprite 4)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)
    
    li x5, 0xfa000000           # Enable=1, Color=Yellow
    slli x4, x8, 15; or x5, x5, x4
    slli x4, x9, 5;  or x5, x5, x4
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

render:
    # --- RENDER SCORE ---
    mv x5, x11; li x4, 0; li x2, 10
s_div: blt x5, x2, s_div_done; sub x5, x5, x2; addi x4, x4, 1; j s_div
s_div_done:
    # Tens (Sprite 0, X=10)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 0; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 10; slli x3, x3, 15; or x2, x2, x3; li x3, 10; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    jal x14, get_font; li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1); li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)
    
    # Ones (Sprite 1, X=18)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 1; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 18; slli x3, x3, 15; or x2, x2, x3; li x3, 10; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    mv x4, x5
    jal x14, get_font; li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1); li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # --- RENDER ENEMY (Sprite 2) ---
    bne x10, zero, skip_enemy   # Hide enemy if exploding
    li x5, 0xe0000000           # Color=Red
    slli x4, x6, 15; or x5, x5, x4
    slli x4, x7, 5;  or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)
skip_enemy:

    # --- RENDER CROSSHAIR (Sprite 3) ---
    li x5, 0xfe000000           # Color=White
    slli x4, x8, 15; or x5, x5, x4
    slli x4, x9, 5;  or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 3; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    j game_loop

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