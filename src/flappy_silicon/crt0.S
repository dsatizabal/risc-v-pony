# crt0.S
# Minimal startup file for bare-metal RV32E

.section .text.init
.globl _start

_start:

    # --------------------------------------------------------
    # 1. INITIALIZE THE STACK POINTER (sp / x2)
    # Automatically pulls the top of RAM from link.ld
    # --------------------------------------------------------
    LA sp, __stack_top

    # --------------------------------------------------------
    # 2. JUMP TO C CODE
    # --------------------------------------------------------
    JAL ra, main

    # --------------------------------------------------------
    # 3. INFINITE HALT (If main ever returns)
    # --------------------------------------------------------
halt_loop:

    J halt_loop
