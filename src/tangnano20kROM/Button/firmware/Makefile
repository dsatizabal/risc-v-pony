# Optional firmware rebuild flow.
#
# The package already includes firmware.hex.
#
# If you edit button_led.S and want to rebuild:
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

firmware.elf: button_led.S link.ld
	$(CC) -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles \
		-ffreestanding -fno-builtin -fno-pic -fno-pie -mno-relax \
		-Wl,--no-relax -Wl,-T,link.ld button_led.S -o $@

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
