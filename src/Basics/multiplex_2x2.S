# multiplex_2x2.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o multiplex_2x2.elf multiplex_2x2.S
# Extract: riscv64-unknown-elf-objcopy -O binary multiplex_2x2.elf multiplex_2x2.bin

.equ MMIO_VGA_CTRL,      140
.equ MMIO_VGA_OBJ_INDEX, 148
.equ MMIO_VGA_OBJ_WORD0, 152
.equ MMIO_VGA_OBJ_WORD1, 156
.equ MMIO_VGA_BG_COLOR,  160
.equ MMIO_VGA_OBJ_WORD2, 164
.equ MMIO_FRAMES_COUNTER,168
.equ MMIO_LINE_COUNTER,  172

.section .text
.globl _start

_start:

    # --------------------------------------------------------
    # 1. SETUP BACKGROUND (Black) AND SELECT SPRITE 0
    # --------------------------------------------------------
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x00
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # Load Graphic Pattern into Sprite 0 (Green Alien)
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF245AA5
    SW x3, 0(x1)

    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    LI x13, 0

game_loop:

    # --------------------------------------------------------
    # 2. VBLANK: WAIT FOR NEW FRAME
    # --------------------------------------------------------
    LI x1, MMIO_FRAMES_COUNTER
    LW x2, 0(x1)

wait_vblank:

    LW x3, 0(x1)
    BEQ x2, x3, wait_vblank
    ADDI x13, x13, 1

    # --------------------------------------------------------
    # 3. DRAW THE TOP ROW (Y=50)
    # --------------------------------------------------------
    ANDI x4, x13, 1
    BEQ x4, zero, draw_top_right

draw_top_left:

    # Enable=1, Color=Green(0x0C), X=100(0x32), Y=50(0x32) -> 0x98320640
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98320640
    SW x2, 0(x1)
    J sync_beam

draw_top_right:

    # Enable=1, Color=Green, X=200(0x64), Y=50(0x32) -> 0x98640640
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98640640
    SW x2, 0(x1)

sync_beam:

    # --------------------------------------------------------
    # 4. RACING THE BEAM: WAIT FOR TOP OF SCREEN THEN LINE 100
    # --------------------------------------------------------
    LI x3, MMIO_LINE_COUNTER

wait_line_0:

    LW x4, 0(x3)
    BNE x4, zero, wait_line_0

wait_line_100:

    LW x4, 0(x3)
    LI x5, 100
    BLT x4, x5, wait_line_100

    # --------------------------------------------------------
    # 5. DRAW THE BOTTOM ROW (Y=150)
    # --------------------------------------------------------
    ANDI x4, x13, 1
    BEQ x4, zero, draw_bottom_right

draw_bottom_left:

    # Enable=1, Color=Green, X=100(0x32), Y=150(0x96) -> 0x983212C0
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x983212C0
    SW x2, 0(x1)
    J game_loop

draw_bottom_right:

    # Enable=1, Color=Green, X=200(0x64), Y=150(0x96) -> 0x986412C0
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x986412C0
    SW x2, 0(x1)
    J game_loop
