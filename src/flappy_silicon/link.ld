/* link.ld */
OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  /* 64KB of unified RAM/ROM starting at 0x00000000 */
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
  .text : {
    /* Force the startup assembly to be at the very beginning of memory */
    *(.text.init)
    *(.text*)
  } > RAM

  .rodata : {
    *(.rodata*)
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss : {
    __bss_start = .;
    *(.bss*)
    __bss_end = .;
  } > RAM

  /* Provide the stack pointer address to the assembly startup file */
  PROVIDE( __stack_top = ORIGIN(RAM) + LENGTH(RAM) );
}
