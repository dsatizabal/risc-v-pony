# simple_line.S
# Compile: riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -o simple_line.elf simple_line.S
# Extract: riscv64-unknown-elf-objcopy -O binary simple_line.elf simple_line.bin

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
    # 2. SELECT LINE HARDWARE ENGINE
    # (Index 8 is the first Line engine in our map)
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_INDEX
    LI x4, 8
    SW x4, 0(x1)

    # --------------------------------------------------------
    # 3. WRITE WORD 0 (Enable, X, Y)
    # Enable = Bit 31
    # X = 110 (Shifted left 15) -> 0x00370000
    # Y = 70  (Shifted left 5)  -> 0x000008C0
    # Combined: 0x803708C0
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD0
    LI x2, 0x803708C0
    SW x2, 0(x1)

    # --------------------------------------------------------
    # 4. WRITE WORD 1 (Length, Direction, Color)
    # Length = 100 (Shifted left 22) -> 0x19000000
    # Direction = 0 for Right (\), 1 for Left (/). Shifted left 21 -> 0x00000000
    # Color = Yellow / 0x3C (Shifted left 7) -> 0x00001E00
    # Combined: 0x19001E00
    # --------------------------------------------------------
    LI x1, MMIO_VGA_OBJ_WORD1
    LI x3, 0x19001E00
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
