# RiscV Pony on Tang Nano 20K - ROM Bring-Up

This package is the first FPGA hardware bring-up for RiscV Pony.

Goal:

```text
Tang Nano 20K clock
  -> RiscV Pony
  -> ROM instruction fetch
  -> firmware writes MMIO out_port at 0x80
  -> out_port[5:0] drives onboard LEDs
```

This intentionally does **not** use external SPI flash yet.

## Files

```text
rtl/
  tang_nano_20k_pony_top.v
  core_rom.v
  rom_fetcher.v

firmware/
  firmware.hex
  led_blink.S
  link.ld
  Makefile
  bin_to_hex.py

constraints/
  tang_nano_20k_pony.cst
  tang_nano_20k_pony.sdc
```

You must also add your existing Pony RTL files to the Gowin project:

```text
alu.v
control_unit.v
decoder.v
program_counter.v
reg_file.v
ram.v
```

Do not add `core.v`, `project.v`, or `spi_fetcher.v` for this first ROM bring-up.
Use `core_rom.v` and `rom_fetcher.v` instead.

## Gowin project setup

1. Create a new Gowin project.
2. Select the Tang Nano 20K device:
   - Series: GW2AR/GW2A(R)
   - Device: GW2AR-18C / GW2A(R)-18C
   - Package: QN88
3. Add these RTL files:
   - `rtl/tang_nano_20k_pony_top.v`
   - `rtl/core_rom.v`
   - `rtl/rom_fetcher.v`
   - your existing Pony `alu.v`
   - your existing Pony `control_unit.v`
   - your existing Pony `decoder.v`
   - your existing Pony `program_counter.v`
   - your existing Pony `reg_file.v`
   - your existing Pony `ram.v`
4. Add `firmware/firmware.hex` to the project, or copy it into the Gowin project root.
5. Add `constraints/tang_nano_20k_pony.cst`.
6. Optionally add `constraints/tang_nano_20k_pony.sdc`.
7. Set top module:
   - `tang_nano_20k_pony_top`
8. Run Synthesis, Place & Route, and Generate Bitstream.

## Program from WSL

Use SRAM programming first:

```bash
openFPGALoader -b tangnano20k /mnt/c/path/to/project/impl/pnr/<project>.fs
```

The LEDs should chase in a one-hot pattern.

## Persistent flash programming

Only after SRAM programming works:

```bash
openFPGALoader -b tangnano20k -f /mnt/c/path/to/project/impl/pnr/<project>.fs
```

## Firmware ROM format

`firmware.hex` is word-addressed:

```text
one 32-bit instruction word per line
```

Example:

```text
08000093
00100113
```

The ROM fetcher uses:

```verilog
inst_data <= rom[pc_addr[ROM_ADDR_WIDTH+1:2]];
```

So the word at line 0 is fetched at PC `0x00000000`, the word at line 1 at PC `0x00000004`, etc.
