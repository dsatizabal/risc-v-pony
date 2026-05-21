# missile_cmd_v3.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o missile_cmd_v3.elf missile_cmd_v3.S
# Extract: riscv64-unknown-elf-objcopy -O binary missile_cmd_v3.elf missile_cmd_v3.bin

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
    li x1, MMIO_VGA_BG_COLOR; li x2, 0x00; sw x2, 0(x1) 

    # --- Terrain (Rectangles 6, 7, 8) Color = Orange/Brown (0x38) ---
    # Rect 8: Base Ground (W=320, H=20, X=0, Y=220)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 8; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80001b80; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x50029c00; sw x3, 0(x1)

    # Rect 7: Left Mountain (W=100, H=40, X=40, Y=180)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80141680; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x19051c00; sw x3, 0(x1)

    # Rect 6: Right Mountain (W=80, H=30, X=200, Y=190)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x806417c0; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x1403dc00; sw x3, 0(x1)

    # --- Cities (Rectangles 4, 5) Color = Cyan (0x0F) ---
    # Rect 5: City 1 (X=70, Y=170, W=15, H=10)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 5; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80231540; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x03c14780; sw x3, 0(x1)

    # Rect 4: City 2 (X=230, Y=180, W=15, H=10)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 4; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80731680; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x03c14780; sw x3, 0(x1)

    # --- Crosshair (Sprite 0) ---
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x08083E08; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x08000000; sw x3, 0(x1)

    li x1, MMIO_VGA_CTRL; li x2, 1; sw x2, 0(x1)

    # --------------------------------------------------------
    # 2. REGISTERS
    # --------------------------------------------------------
    li x6, 160      # Crosshair X
    li x7, 100      # Crosshair Y
    li x8, 0        # Line 1 Length (Missile 1)
    li x9, 0        # Line 2 Length (Missile 2)
    li x10, 0       # Explosion Timer (0 = Off)
    li x11, 0       # Latched Explosion X
    li x12, 0       # Latched Explosion Y
    li x13, 0       # Frame Counter

game_loop:
    # --- WAIT FOR VBLANK ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank
    addi x13, x13, 1

    # --------------------------------------------------------
    # 3. PHYSICS & AUTO-AI
    # --------------------------------------------------------
    # Grow Incoming Missiles
    addi x8, x8, 1
    li x4, 200; blt x8, x4, skip_m1_reset
    li x8, 0
skip_m1_reset:
    
    # Delay second missile slightly
    andi x4, x13, 1; beq x4, zero, skip_m2_grow
    addi x9, x9, 1
skip_m2_grow:
    li x4, 220; blt x9, x4, skip_m2_reset
    li x9, 0
skip_m2_reset:

    # Auto-Sweep Crosshair in a figure-8
    srli x4, x13, 1; andi x4, x4, 127
    li x5, 64; blt x4, x5, cx_right
    li x6, 128; sub x6, x6, x4; j calc_cy
cx_right: 
    mv x6, x4
calc_cy:
    slli x6, x6, 1; addi x6, x6, 60     # X bounds: 60 to 188
    
    srli x4, x13, 2; andi x4, x4, 63
    li x5, 32; blt x4, x5, cy_down
    li x7, 64; sub x7, x7, x4; j apply_cy
cy_down: 
    mv x7, x4
apply_cy:
    slli x7, x7, 1; addi x7, x7, 40     # Y bounds: 40 to 104

    # Trigger Explosion periodically
    bne x10, zero, expl_logic
    andi x4, x13, 127
    bne x4, zero, render
    # FIRE!
    li x10, 1
    mv x11, x6      # Latch X
    mv x12, x7      # Latch Y
    j render

    # --------------------------------------------------------
    # 4. STROBING EXPLOSION (Rectangle 2)
    # --------------------------------------------------------
expl_logic:
    addi x10, x10, 1
    li x4, 60
    blt x10, x4, calc_size
    # End Explosion
    li x10, 0                       
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw zero, 0(x1)
    j render

calc_size:
    # Grow to 30, then shrink
    li x4, 30
    blt x10, x4, set_size
    li x15, 60; sub x15, x15, x10   # Shrink Size
    j draw_expl
set_size:
    mv x15, x10                     # Grow Size

draw_expl:
    # Center explosion on latched coordinates
    srli x4, x15, 1
    sub x14, x11, x4                # Adjusted X
    sub x5, x12, x4                 # Adjusted Y

    li x1, MMIO_VGA_OBJ_INDEX; li x4, 2; sw x4, 0(x1)
    
    # Word 0: Enable | X | Y
    li x4, 0x80000000
    slli x2, x14, 15; or x4, x4, x2
    slli x2, x5, 5; or x4, x4, x2
    li x1, MMIO_VGA_OBJ_WORD0; sw x4, 0(x1)

    # Word 1: Width | Height | Strobe Color
    slli x4, x15, 22                # Width
    slli x2, x15, 13; or x4, x4, x2 # Height
    andi x2, x13, 0x3F              # Strobe Color with Frame Counter!
    slli x2, x2, 7; or x4, x4, x2
    li x1, MMIO_VGA_OBJ_WORD1; sw x4, 0(x1)

    # --------------------------------------------------------
    # 5. RENDER LINES AND CROSSHAIR
    # --------------------------------------------------------
render:
    # Crosshair (Sprite 0)
    li x5, 0xfe000000
    slli x4, x6, 15; or x5, x5, x4
    slli x4, x7, 5; or x5, x5, x4
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # Missile 1 (Line Engine 14: X=40, Y=0, Dir=Right)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 14; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x4, 0x80140000; sw x4, 0(x1)
    # Length=x8, Dir=0, Color=Red(0x30)
    slli x4, x8, 22; li x5, 0x1800; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD1; sw x4, 0(x1)

    # Missile 2 (Line Engine 15: X=280, Y=0, Dir=Left)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 15; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x4, 0x808C0000; sw x4, 0(x1)
    # Length=x9, Dir=1, Color=Red(0x30)
    slli x4, x9, 22; li x5, 0x00201800; or x4, x4, x5
    li x1, MMIO_VGA_OBJ_WORD1; sw x4, 0(x1)

    j game_loop