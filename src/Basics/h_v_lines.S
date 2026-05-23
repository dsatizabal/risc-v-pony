# h_v_lines.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o h_v_lines.elf h_v_lines.S
# Extract: riscv64-unknown-elf-objcopy -O binary h_v_lines.elf h_v_lines.bin

.equ MMIO_VGA_CTRL,      140
.equ MMIO_VGA_OBJ_INDEX, 148
.equ MMIO_VGA_OBJ_WORD0, 152
.equ MMIO_VGA_OBJ_WORD1, 156
.equ MMIO_VGA_BG_COLOR,  160

.section .text
.globl _start

_start:

    # --------------------------------------------------------
    # 1. SETUP BACKGROUND COLOR (Black = 0x00)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_BG_COLOR
    LI x2, 0x00
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 2. HORIZONTAL LINE (Rectangle Engine 4)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 4
    SW x4, 0(x1)

    # WORD 0 (Enable=1, X=0, Y=119)
    # Enable = 0x80000000
    # X = 0
    # Y = 119 (Shifted left 5) -> 0x00000EE0
    # Combined: 0x80000EE0
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80000EE0
    SW x2, 0(x1)

    # WORD 1 (Width=320, Height=2, Color=Bright Green 0x0C)
    # Width = 320 (Shifted left 22) -> 0x50000000
    # Height = 2 (Shifted left 13)  -> 0x00004000
    # Color = 0x0C (Shifted left 7) -> 0x00000600
    # Combined: 0x50004600
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x50004600
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 3. VERTICAL LINE (Rectangle Engine 5)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 5
    SW x4, 0(x1)

    # WORD 0 (Enable=1, X=159, Y=0)
    # Enable = 0x80000000
    # X = 159 (Shifted left 15) -> 0x004F8000
    # Y = 0
    # Combined: 0x804F8000
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x804F8000
    SW x2, 0(x1)

    # WORD 1 (Width=2, Height=240, Color=Bright Green 0x0C)
    # Width = 2 (Shifted left 22)   -> 0x00800000
    # Height = 240 (Shifted left 13)-> 0x001E0000
    # Color = 0x0C (Shifted left 7) -> 0x00000600
    # Combined: 0x009E0600
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x009E0600
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 4. TURN ON THE MONITOR
    # --------------------------------------------------------
    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 5. INFINITE HALT LOOP
    # --------------------------------------------------------
halt_loop:

    J halt_loop
