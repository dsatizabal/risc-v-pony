# montezuma.S
# Compile with: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o montezuma.elf montezuma.S
# Then objcopy to .bin

.equ MMIO_OUT,             128
.equ MMIO_VGA_CTRL,        140
.equ MMIO_GAMEPAD,         144
.equ MMIO_VGA_OBJ_INDEX,   148
.equ MMIO_VGA_OBJ_WORD0,   152
.equ MMIO_VGA_OBJ_WORD1,   156
.equ MMIO_VGA_BG_COLOR,    160
.equ MMIO_VGA_OBJ_WORD2,   164
.equ MMIO_FRAMES_COUNTER,  168

.equ COLOR_BLACK,  0x00
.equ COLOR_GREEN,  0x0C
.equ COLOR_CYAN,   0x0F
.equ COLOR_RED,    0x30
.equ COLOR_YELLOW, 0x3C

.section .text
.globl _start

_start:
    # --------------------------------------------------------
    # 1. INIT STATIC SCENE
    # --------------------------------------------------------

    # Set Background to Black
    li x1, MMIO_VGA_BG_COLOR
    li x2, COLOR_BLACK
    sw x2, 0(x1)

    # RECT 6: Floor (Y=200, W=320, H=40, COLOR_GREEN)
    li x1, MMIO_VGA_OBJ_INDEX
    li x2, 6
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0
    li x2, 0x80001900
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1
    li x2, 0x50050600
    sw x2, 0(x1)

    # RECT 7: Cyan Platform (X=100, Y=150, W=60, H=10, COLOR_CYAN)
    li x1, MMIO_VGA_OBJ_INDEX
    li x2, 7
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0
    li x2, 0x800c92c0   # Enable=1, X=100, Y=150
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1
    li x2, 0x0f014780   # W=60, H=10, C=CYAN
    sw x2, 0(x1)

    # SPRITE 1: Yellow Key (X=200, Y=192)
    li x1, MMIO_VGA_OBJ_INDEX
    li x2, 1
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0
    li x2, 0xfa191800   # Enable=1, Color=YELLOW, X=200, Y=192
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1
    li x2, 0x70888870   # Key Top
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2
    li x2, 0x101c1018   # Key Bottom
    sw x2, 0(x1)

    # --------------------------------------------------------
    # 2. INIT PLAYER (PEDRO)
    # --------------------------------------------------------

    # We will use x14 for Player X, x15 for Player Y
    li x14, 100     # Initial X
    li x15, 50      # Initial Y (High up in the air so we can watch him fall!)

    # Load Pedro's Pattern into Sprite 0
    li x1, MMIO_VGA_OBJ_INDEX
    li x2, 0
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD1
    li x2, 0x3E7F3E1C
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD2
    li x2, 0x1C362200
    sw x2, 0(x1)

    # Enable VGA
    li x1, MMIO_VGA_CTRL
    li x2, 1
    sw x2, 0(x1)

    # --------------------------------------------------------
    # 3. MAIN GAME LOOP
    # --------------------------------------------------------
game_loop:

    # --- RENDER PEDRO ---
    # Construct WORD0 dynamically: Enable(bit 31) | COLOR_RED(bits 25-30) | X | Y
    li x10, 0xec000000      # Base: Enable=1, Color=RED (0x30 << 25 = 0x60000000, 0x80+0x60 = 0xE0... actually let's use 0xE0000000)
    li x10, 0xe0000000      # 0xE0000000 = Enable=1, Color=RED (0x30)

    slli x11, x14, 15       # Shift X into position
    or x10, x10, x11
    slli x12, x15, 5        # Shift Y into position
    or x10, x10, x12

    li x1, MMIO_VGA_OBJ_INDEX
    li x2, 0
    sw x2, 0(x1)
    li x1, MMIO_VGA_OBJ_WORD0
    sw x10, 0(x1)

    # --- READ GAMEPAD ---
    li x1, MMIO_GAMEPAD
    lw x2, 0(x1)

    li x3, 0x100            # Check Right (Bit 8)
    and x4, x2, x3
    beq x4, zero, check_left
    addi x14, x14, 2        # Move Right

check_left:
    li x3, 0x200            # Check Left (Bit 9)
    and x4, x2, x3
    beq x4, zero, apply_physics
    addi x14, x14, -2       # Move Left

    # --- PHYSICS & COLLISION ---
apply_physics:
    addi x15, x15, 2        # Gravity: Fall down 2 pixels per frame

    # 1. Floor Collision (Floor is at Y=200, Pedro is 8 pixels tall)
    # If Y >= 192, snap to 192
    li x5, 192
    blt x15, x5, check_platform
    mv x15, x5              # Snap to floor
    j wait_vblank           # Skip platform check if we hit the floor

check_platform:
    # 2. Platform Collision (Platform is at X=100 to 160, Y=150)
    # Are we falling through Y=142 (150 - 8)?
    li x5, 142
    blt x15, x5, wait_vblank # Above platform
    li x6, 146
    bge x15, x6, wait_vblank # Already below platform (don't snap up)

    # Are we within X bounds? (Pedro X+8 > 100, and Pedro X < 160)
    li x5, 92
    blt x14, x5, wait_vblank # Too far left
    li x5, 160
    bge x14, x5, wait_vblank # Too far right

    # We hit the platform!
    li x15, 142             # Snap to platform top

    # --- WAIT FOR VBLANK (SYNC FRAME) ---
wait_vblank:
    li x1, MMIO_FRAMES_COUNTER
    lw x2, 0(x1)
vblank_poll:
    lw x3, 0(x1)
    beq x2, x3, vblank_poll

    j game_loop