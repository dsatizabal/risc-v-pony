# animation.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o animation.elf animation.S
# Extract: riscv64-unknown-elf-objcopy -O binary animation.elf animation.bin

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
    # 1. SETUP STATIC NEON CITY SKYLINE
    # --------------------------------------------------------
    li x1, MMIO_VGA_BG_COLOR
    li x2, 0x00 # Black sky
    sw x2, 0(x1)

    # We use x1 for INDEX, x2 for WORD0, x3 for WORD1, x4 as a temp

    # Building 1 (Rect 6)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 6; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80001680; sw x2, 0(x1) # X=0, Y=180
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x0f078600; sw x3, 0(x1) # W=60, H=60, C=Green

    # Building 2 (Rect 7)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 7; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x801e1180; sw x2, 0(x1) # X=60, Y=140
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x0c8c8180; sw x3, 0(x1) # W=50, H=100, C=Blue

    # Building 3 (Rect 8)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 8; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x80371400; sw x2, 0(x1) # X=110, Y=160
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x140a0780; sw x3, 0(x1) # W=80, H=80, C=Cyan

    # Building 4 (Rect 9)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 9; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x805f0c80; sw x2, 0(x1) # X=190, Y=100
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x0f119980; sw x3, 0(x1) # W=60, H=140, C=Magenta

    # Building 5 (Rect 10)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 10; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; li x2, 0x807d12c0; sw x2, 0(x1) # X=250, Y=150
    li x1, MMIO_VGA_OBJ_WORD1; li x3, 0x118b5800; sw x3, 0(x1) # W=70, H=90, C=Red

    # --------------------------------------------------------
    # 2. SETUP ALIEN PATTERNS
    # --------------------------------------------------------
    # Alien 1 Pattern (Sprite 0)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x183C7EDB; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0xFF245AA5; sw x3, 0(x1)

    # Alien 2 Pattern (Sprite 1)
    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1; li x2, 0x3C7EDBFF; sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2; li x3, 0x245AA500; sw x3, 0(x1)

    # Enable VGA
    li x1, MMIO_VGA_CTRL; li x4, 1; sw x4, 0(x1)

    # --------------------------------------------------------
    # 3. INITIALIZE ANIMATION PHYSICS STATE
    # --------------------------------------------------------
    # We will use x6-x15 to hold the state of both aliens
    
    # Alien 2 State (Fast)
    li x6,  50      # A2 X
    li x7,  50      # A2 Y
    li x8,  0x3F    # A2 Color (White)
    li x9,  2       # A2 dX (Speed X)
    li x15, 2       # A2 dY (Speed Y)

    # Alien 1 State (Slow)
    li x10, 160     # A1 X
    li x11, 120     # A1 Y
    li x14, 0x30    # A1 Color (Red)
    li x12, 1       # A1 dX (Speed X)
    li x13, 1       # A1 dY (Speed Y)

    # --------------------------------------------------------
    # 4. MAIN ANIMATION LOOP
    # --------------------------------------------------------
animation_loop:

    # --- WAIT FOR VBLANK (SYNC FRAME) ---
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
wait_vblank:
    lw x3, 0(x1)
    beq x2, x3, wait_vblank

    # ==========================================
    # ALIEN 1 PHYSICS (x10, x11)
    # ==========================================
    add x10, x10, x12       # X = X + dX
    li x4, 1
    blt x10, x4, a1_bounce_x
    li x4, 312              # Screen width (320) - Sprite width (8)
    bge x10, x4, a1_bounce_x
    j a1_move_y
a1_bounce_x:
    sub x12, zero, x12      # Reverse X speed
    addi x14, x14, 13       # Change Color
    andi x14, x14, 0x3F     # Keep within 6 bits
    ori x14, x14, 0x03      # Prevent color from ever turning pure black

a1_move_y:
    add x11, x11, x13       # Y = Y + dY
    li x4, 1
    blt x11, x4, a1_bounce_y
    li x4, 232              # Screen height (240) - Sprite height (8)
    bge x11, x4, a1_bounce_y
    j a1_draw
a1_bounce_y:
    sub x13, zero, x13      # Reverse Y speed
    addi x14, x14, 13       # Change Color
    andi x14, x14, 0x3F
    ori x14, x14, 0x03      

a1_draw:
    # Build WORD0: 0x80000000 | (Color << 25) | (X << 15) | (Y << 5)
    li x5, 0x80000000
    slli x4, x14, 25; or x5, x5, x4
    slli x4, x10, 15; or x5, x5, x4
    slli x4, x11, 5;  or x5, x5, x4

    li x1, MMIO_VGA_OBJ_INDEX; li x4, 0; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # ==========================================
    # ALIEN 2 PHYSICS (x6, x7)
    # ==========================================
    add x6, x6, x9          
    li x4, 1
    blt x6, x4, a2_bounce_x
    li x4, 312              
    bge x6, x4, a2_bounce_x
    j a2_move_y
a2_bounce_x:
    sub x9, zero, x9        
    addi x8, x8, 17         
    andi x8, x8, 0x3F
    ori x8, x8, 0x0C        

a2_move_y:
    add x7, x7, x15         
    li x4, 1
    blt x7, x4, a2_bounce_y
    li x4, 232              
    bge x7, x4, a2_bounce_y
    j a2_draw
a2_bounce_y:
    sub x15, zero, x15      
    addi x8, x8, 17
    andi x8, x8, 0x3F
    ori x8, x8, 0x0C

a2_draw:
    li x5, 0x80000000
    slli x4, x8, 25; or x5, x5, x4
    slli x4, x6, 15; or x5, x5, x4
    slli x4, x7, 5;  or x5, x5, x4

    li x1, MMIO_VGA_OBJ_INDEX; li x4, 1; sw x4, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0; sw x5, 0(x1)

    # Loop forever
    j animation_loop
