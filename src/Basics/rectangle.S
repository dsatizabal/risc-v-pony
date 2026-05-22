# rectangle.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o rectangle.elf rectangle.S
# Extract: riscv64-unknown-elf-objcopy -O binary rectangle.elf rectangle.bin

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
    # 2. SELECT RECTANGLE HARDWARE ENGINE
    # (Index 4 is the first Rectangle in our trimmed memory map)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 4
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 3. WRITE WORD 0 (Enable, X, Y)
    # Enable = Bit 31
    # X = 140 (Shifted left 15) -> 0x00460000
    # Y = 100 (Shifted left 5)  -> 0x00000C80
    # Combined: 0x80460C80
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x80460C80
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 4. WRITE WORD 1 (Width, Height, Color)
    # Width = 40  (Shifted left 22) -> 0x0A000000
    # Height = 40 (Shifted left 13) -> 0x00050000
    # Color = Red / 0x30 (Shifted left 7)  -> 0x00001800
    # Combined: 0x0A051800
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x0A051800
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 5. TURN ON THE MONITOR
    # --------------------------------------------------------
    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 6. INFINITE HALT LOOP
    # --------------------------------------------------------
halt_loop:

    J halt_loop
