# RiscV Pony Tang Nano 20K - Button-Controlled LED Demo

This package extends the ROM bring-up wrapper with real physical button input.

## Behavior

```text
no button pressed -> LED chase left
btn[0] pressed    -> LED chase right
```

The firmware reads:

```text
0x84 -> in_port
```

and writes:

```text
0x80 -> out_port
```

## Files

```text
rtl/
  tang_nano_20k_pony_top.v

firmware/
  firmware.hex
  button_led.S
  link.ld
  Makefile
  bin_to_hex.py

constraints/
  tang_nano_20k_pony_buttons.cst
  tang_nano_20k_pony_buttons.sdc
```

You should reuse the existing ROM bring-up files:

```text
rom_fetcher.v
core_rom.v
alu.v
control_unit.v
decoder.v
program_counter.v
reg_file.v
ram.v
```

Do not add the old `core.v`, `project.v`, or `spi_fetcher.v` for this ROM-based hardware bring-up.

## Button polarity

The wrapper assumes the Tang Nano buttons are active-low:

```verilog
assign in_port = {6'b0, ~btn};
```

So firmware sees a clean active-high signal:

```text
in_port[0] = 1 when btn[0] is pressed
in_port[1] = 1 when btn[1] is pressed
```

If behavior appears inverted, change the wrapper to:

```verilog
assign in_port = {6'b0, btn};
```

## Constraints

This CST maps:

```text
clk    -> pin 4
btn[0] -> pin 88
btn[1] -> pin 87
leds   -> pins 15..20
```

If your board/project uses the two buttons in the opposite order, just swap pins 87 and 88 in the CST.

## Gowin

Replace the previous top wrapper with this one and replace `firmware.hex`.

Set top module:

```text
tang_nano_20k_pony_top
```

Then synthesize, place and route, generate bitstream, and program with:

```bash
openFPGALoader -b tangnano20k /mnt/c/path/to/project/impl/pnr/<project>.fs
```
