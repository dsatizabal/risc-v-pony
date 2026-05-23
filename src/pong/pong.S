# pong_auto_v2.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o pong_auto_v2.elf pong_auto_v2.S
# Extract: riscv64-unknown-elf-objcopy -O binary pong_auto_v2.elf pong_auto_v2.bin

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
    li x1, MMIO_VGA_BG_COLOR
    li x2, 0x00 
    sw x2, 0(x1)

    # Rect 5: Top Scoreboard Bar (X=0, Y=0, W=320, H=24, C=Blue)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80000000; sw x2, 0(x1) 
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x50030180; sw x3, 0(x1) 

    # Rect 6: Left Paddle (W=10, H=40, C=Yellow)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x01451e00; sw x3, 0(x1)

    # Rect 7: Right Paddle (W=10, H=40, C=Red)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x01451800; sw x3, 0(x1)

    # Sprite 0: The Ball
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0xFFFFFFFF; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0xFFFFFFFF; sw x3, 0(x1)

    li x1, MMIO_VGA_CTRL; li x4, 1; sw x4, 0(x1)

    # --------------------------------------------------------
    # 2. INITIALIZE REGISTERS
    # --------------------------------------------------------
    li x6, 160      # Ball X
    li x7, 120      # Ball Y
    li x8, 2        # Ball dX
    li x9, 2        # Ball dY
    li x10, 100     # Left Paddle Y
    li x11, 150     # Right Paddle Y
    li x12, 0       # Left Score
    li x13, 0       # Right Score

game_loop:
    # --- WAIT FOR VBLANK ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank

    # --- BALL PHYSICS ---
    add x6, x6, x8          
    add x7, x7, x9          

    # Top/Bottom Bounce (Ceiling is now Y=24 because of the bar)
    li x4, 24
    blt x7, x4, bounce_y    
    li x4, 232              
    bge x7, x4, bounce_y    
    j check_x_left
bounce_y:
    sub x9, zero, x9        

check_x_left:
    li x4, 20
    bge x6, x4, check_x_right
    sub x8, zero, x8        # Bounce X
    
    # Hit Left Paddle?
    addi x4, x7, 8
    blt x4, x10, update_ai  
    addi x5, x10, 40
    bgt x7, x5, update_ai   
    
    addi x12, x12, 1
    li x4, 99
    ble x12, x4, update_ai
    li x12, 0               
    j update_ai

check_x_right:
    li x4, 292
    blt x6, x4, update_ai
    sub x8, zero, x8        # Bounce X
    
    # Hit Right Paddle? 
    addi x4, x7, 8
    blt x4, x11, update_ai
    addi x5, x11, 40
    bgt x7, x5, update_ai
    
    addi x13, x13, 1
    li x4, 99
    ble x13, x4, update_ai
    li x13, 0

update_ai:
    # --- ORGANIC PADDLE AI ---
    addi x2, x7, -16        # Target Y

    # Left Paddle chase
    beq x10, x2, clamp_l
    blt x10, x2, l_down
    addi x10, x10, -2; j clamp_l
l_down:
    addi x10, x10, 2
clamp_l:
    li x4, 24; blt x10, x4, fix_l_top
    li x4, 200; bge x10, x4, fix_l_bot
    j ai_right
fix_l_top: li x10, 24; j ai_right
fix_l_bot: li x10, 200

ai_right:
    # Right Paddle chase
    beq x11, x2, clamp_r
    blt x11, x2, r_down
    addi x11, x11, -2; j clamp_r
r_down:
    addi x11, x11, 2
clamp_r:
    li x4, 24; blt x11, x4, fix_r_top
    li x4, 200; bge x11, x4, fix_r_bot
    j render_graphics
fix_r_top: li x11, 24; j render_graphics
fix_r_bot: li x11, 200

render_graphics:
    # --- RENDER SCORE FONTS ---
    # Left Score (Div/Mod by 10)
    mv x5, x12; li x4, 0; li x2, 10
l_div: blt x5, x2, l_div_done; sub x5, x5, x2; addi x4, x4, 1; j l_div
l_div_done:
    # Left Tens (Sprite 1)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 1; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 80; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)
    
    # Left Ones (Sprite 2)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 2; sw x2, 0(x1)
    li x2, 0xf8000000; li x3, 88; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    mv x4, x5 # move Ones into x4 for get_font
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # Right Score (Div/Mod by 10)
    mv x5, x13; li x4, 0; li x2, 10
r_div: blt x5, x2, r_div_done; sub x5, x5, x2; addi x4, x4, 1; j r_div
r_div_done:
    # Right Tens (Sprite 3)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 3; sw x2, 0(x1)
    li x2, 0xe0000000; li x3, 220; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # Right Ones (Sprite 4)
    li x1, MMIO_VGA_OBJ_INDEX; li x2, 4; sw x2, 0(x1)
    li x2, 0xe0000000; li x3, 228; slli x3, x3, 15; or x2, x2, x3; li x3, 8; slli x3, x3, 5; or x2, x2, x3
    li x1, MMIO_VGA_OBJ_WORD0; sw x2, 0(x1)
    mv x4, x5
    jal x14, get_font
    li x1, MMIO_VGA_OBJ_WORD1; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; sw x3, 0(x1)

    # --- DRAW BALL ---
    li x5, 0xfe000000; slli x4, x6, 15; or x5, x5, x4; slli x4, x7, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # --- DRAW LEFT PADDLE ---
    li x5, 0x80000000; li x4, 10; slli x4, x4, 15; or x5, x5, x4; slli x4, x10, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # --- DRAW RIGHT PADDLE ---
    li x5, 0x80000000; li x4, 300; slli x4, x4, 15; or x5, x5, x4; slli x4, x11, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    j game_loop

# --------------------------------------------------------
# FONT SUBROUTINE (Bypassing Harvard Architecture Limits)
# Input: x4 = digit (0-9)
# Output: x2 = WORD1, x3 = WORD2
# Return Address: x14
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
