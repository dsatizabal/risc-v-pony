# RiscV Pony Firetest firmware build
#
# Requires a RISC-V bare-metal GCC toolchain in PATH, for example:
#   riscv64-unknown-elf-gcc
#   riscv64-unknown-elf-objcopy
#   riscv64-unknown-elf-objdump

CROSS ?= riscv64-unknown-elf
CC      = $(CROSS)-gcc
OBJCOPY = $(CROSS)-objcopy
OBJDUMP = $(CROSS)-objdump

ARCH = rv32e
ABI  = ilp32e

COMMON_FLAGS = \
	-march=$(ARCH) \
	-mabi=$(ABI) \
	-msmall-data-limit=0 \
	-ffreestanding \
	-fno-builtin \
	-fno-pic \
	-fno-pie \
	-mno-relax \
	-O2 \
	-Wall \
	-Wextra

LDFLAGS = \
	-nostdlib \
	-nostartfiles \
	-Wl,--no-relax \
	-Wl,-T,link.ld

.PHONY: all clean c asm dump-c dump-asm

all: c asm

c: firmware.elf firmware.bin firmware.dump

asm: firetest_asm.elf firetest_asm.bin firetest_asm.dump

firmware.elf: crt0.S main.c link.ld
	$(CC) $(COMMON_FLAGS) $(LDFLAGS) crt0.S main.c -o $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.dump: firmware.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

firetest_asm.elf: firetest_asm.S link.ld
	$(CC) $(COMMON_FLAGS) $(LDFLAGS) firetest_asm.S -o $@

firetest_asm.bin: firetest_asm.elf
	$(OBJCOPY) -O binary $< $@

firetest_asm.dump: firetest_asm.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

dump-c: firmware.dump
	cat firmware.dump

dump-asm: firetest_asm.dump
	cat firetest_asm.dump

clean:
	rm -f *.elf *.bin *.dump
