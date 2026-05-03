# RiscV Pony game-logic firmware build

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

.PHONY: all clean dump

all: firmware.elf firmware.bin firmware.dump

firmware.elf: crt0.S main.c link.ld
	$(CC) $(COMMON_FLAGS) $(LDFLAGS) crt0.S main.c -o $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.dump: firmware.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

dump: firmware.dump
	cat firmware.dump

clean:
	rm -f *.elf *.bin *.dump
