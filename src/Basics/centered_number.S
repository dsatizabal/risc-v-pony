# centered_number.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o centered_number.elf centered_number.S
# Extract: riscv64-unknown-elf-objcopy -O binary centered_number.elf centered_number.bin

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
    # 2. DRAW LEFT DIGIT "8" (Sprite Engine 0)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 0
    SW x4, 0(x1)

    # WORD 0 (Enable=1, Color=White(0x3F), X=152, Y=116)
    # Enable & Color = 0xFE000000
    # X = 152 (Shifted left 15) -> 0x004C0000
    # Y = 116 (Shifted left 5)  -> 0x00000E80
    # Combined: 0xFE4C0E80
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0xFE4C0E80
    SW x2, 0(x1)

    # WORD 1 & WORD 2 (Font Pattern for "8")
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x3C66663C
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0x6666663C
    SW x3, 0(x1)

    # --------------------------------------------------------
    # 3. DRAW RIGHT DIGIT "3" (Sprite Engine 1)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 1
    SW x4, 0(x1)

    # WORD 0 (Enable=1, Color=White(0x3F), X=160, Y=116)
    # Enable & Color = 0xFE000000
    # X = 160 (Shifted left 15) -> 0x00500000
    # Y = 116 (Shifted left 5)  -> 0x00000E80
    # Combined: 0xFE500E80
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0xFE500E80
    SW x2, 0(x1)

    # WORD 1 & WORD 2 (Font Pattern for "3")
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x3C66061C
    SW x3, 0(x1)

    LI x1, MMIO_VGA_OBJ_WORD2
    LI x3, 0x0606663C
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
