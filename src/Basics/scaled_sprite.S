# scaled_sprite.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o scaled_sprite.elf scaled_sprite.S
# Extract: riscv64-unknown-elf-objcopy -O binary scaled_sprite.elf scaled_sprite.bin

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
    # 2. SELECT SPRITE HARDWARE ENGINE (Index 0)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 3. WRITE WORD 0 (Enable, Color, X, Y, SCALE!)
    # Enable = Bit 31 -> 0x80000000
    # Color = Bright Green 0x0C (Shift left 25) -> 0x18000000
    # X = 128 (Shift left 15) -> 0x00400000
    # Y = 88 (Shift left 5)  -> 0x00000B00
    # Scale = 8x (Set bits 1:0 to binary 11) -> 0x00000003
    # Combined: 0x98400B03
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98400B03
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 4. WRITE WORD 1 (Top 4 rows of the Alien)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 5. WRITE WORD 2 (Bottom 4 rows of the Alien)
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
