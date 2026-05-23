# independent_scale.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o independent_scale.elf independent_scale.S
# Extract: riscv64-unknown-elf-objcopy -O binary independent_scale.elf independent_scale.bin

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
    # 2. SPRITE 0: TALL & SKINNY (1x Width, 8x Height)
    # X = 40, Y = 88
    # Bits 3:0 = 1100 (0xC)
    # Combined WORD0: 0x98140B0C
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98140B0C
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF245AA5
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 3. SPRITE 1: SHORT & WIDE (8x Width, 1x Height)
    # X = 80, Y = 116
    # Bits 3:0 = 0011 (0x3)
    # Combined WORD0: 0x98280E83
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98280E83
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF245AA5
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 4. SPRITE 2: PROPORTIONAL LARGE (4x Width, 4x Height)
    # X = 180, Y = 104
    # Bits 3:0 = 1010 (0xA)
    # Combined WORD0: 0x985A0D0A
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 2
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x985A0D0A
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0xFF245AA5
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 5. SPRITE 3: CLASSIC NORMAL (1x Width, 1x Height)
    # X = 260, Y = 116
    # Bits 3:0 = 0000 (0x0)
    # Combined WORD0: 0x98820E80
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 3
    SW x4, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x98820E80
    SW x2, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x183C7EDB
    SW x3, 0(x1)

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
