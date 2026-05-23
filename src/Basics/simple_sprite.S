# simple_sprite.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o simple_sprite.elf simple_sprite.S
# Extract: riscv64-unknown-elf-objcopy -O binary simple_sprite.elf simple_sprite.bin

.equ MMIO_VGA_CTRL,      140
.equ MMIO_VGA_OBJ_INDEX, 148
.equ MMIO_VGA_OBJ_WORD0, 152
.equ MMIO_VGA_OBJ_WORD1, 156
.equ MMIO_VGA_BG_COLOR,  160
.equ MMIO_VGA_OBJ_WORD2, 164

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
    # 2. SELECT SPRITE HARDWARE ENGINE
    # (Index 0 is the first Sprite engine in our map)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 3. WRITE WORD 0 (Enable, Color, X, Y)
    # Enable = Bit 31 -> 0x80000000
    # Color = Bright Green 0x0C (Shifted left 25) -> 0x18000000
    # X = 156 (Shifted left 15) -> 0x004E0000
    # Y = 116 (Shifted left 5)  -> 0x00000E80
    # Combined: 0x984E0E80
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x984E0E80
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 4. WRITE WORD 1 (Top 4 rows of the Alien)
    # Row 0: 00011000 = 0x18
    # Row 1: 00111100 = 0x3C
    # Row 2: 01111110 = 0x7E
    # Row 3: 11011011 = 0xDB
    # Combined: 0x183C7EDB
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 5. WRITE WORD 2 (Bottom 4 rows of the Alien)
    # Row 4: 11111111 = 0xFF
    # Row 5: 00100100 = 0x24
    # Row 6: 01011010 = 0x5A
    # Row 7: 10100101 = 0xA5
    # Combined: 0xFF245AA5
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF245AA5
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 6. TURN ON THE MONITOR
    # --------------------------------------------------------
    LI x1, MMIO_VGA_CTRL
    LI x2, 1
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 7. INFINITE HALT LOOP
    # --------------------------------------------------------
halt_loop:

    J halt_loop
