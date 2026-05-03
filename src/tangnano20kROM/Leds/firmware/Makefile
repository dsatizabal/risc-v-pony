# Optional firmware rebuild flow.
#
# The package already includes firmware.hex, so this Makefile is not
# required for the first Gowin build.
#
# If you want to rebuild from assembly:
#   make
#
# Requires:
#   riscv64-unknown-elf-gcc
#   riscv64-unknown-elf-objcopy

CROSS ?= riscv64-unknown-elf
CC      = $(CROSS)-gcc
OBJCOPY = $(CROSS)-objcopy
OBJDUMP = $(CROSS)-objdump

ARCH = rv32e
ABI  = ilp32e

.PHONY: all clean dump

all: firmware.hex

firmware.elf: led_blink.S link.ld
	$(CC) -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles \
		-ffreestanding -fno-builtin -fno-pic -fno-pie -mno-relax \
		-Wl,--no-relax -Wl,-T,link.ld led_blink.S -o $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin
	python3 bin_to_hex.py firmware.bin firmware.hex

firmware.dump: firmware.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

dump: firmware.dump
	cat firmware.dump

clean:
	rm -f *.elf *.bin *.dump
