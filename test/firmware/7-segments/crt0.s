.section .init
    .global _start

_start:
    # Set the Stack Pointer (x2) to the very top of our RAM.
    # We will tell the linker our RAM starts at 0x200, and is 128 bytes long.
    # So the top of the stack is 0x200 + 128 = 0x280.
    li sp, 0x280

    # Jump to the C main function
    jal main

trap:
    # If main() ever returns, trap the CPU in an infinite loop
    j trap

