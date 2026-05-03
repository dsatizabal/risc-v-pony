# Tang Nano 20K Pony Timer Demo

This demo verifies the new MMIO timer on real Tang Nano hardware.

## Expected behavior

The LED chase still works, and holding `btn[0]` reverses direction.

The important difference is that the firmware no longer uses a simple decrementing software delay. It uses the Pony MMIO timer:

```text
0x80 -> out_port / LEDs
0x84 -> in_port / buttons
0x88 -> timer_value
```

Firmware waits like this:

```asm
lw   x9, 0(x8)       # start = timer
wait_timer:
lw   x11, 0(x8)      # now = timer
sub  x12, x11, x9    # elapsed
bltu x12, x10, wait_timer
```

So if the LEDs continue moving at a stable pace, and the button still changes direction, the timer is working in real hardware.

## Files

```text
rtl/tang_nano_20k_pony_top.v
firmware/timer_led.S
firmware/firmware.hex
constraints/tang_nano_20k_pony_timer.cst
constraints/tang_nano_20k_pony_timer.sdc
```

## Project integration

Use the latest timer-enabled RTL:

```text
core_rom.v
pony_timer.v
rom_fetcher.v
alu.v
control_unit.v
decoder.v
program_counter.v
reg_file.v
ram.v
```

Replace your current `firmware.hex` with the included one.

Use this top:

```text
tang_nano_20k_pony_top
```

## Build firmware manually

```bash
cd firmware
make clean
make
```

Then copy/regenerate `firmware.hex` into the Gowin project.

## Program

```bash
openFPGALoader -b tangnano20k /mnt/c/path/to/project/impl/pnr/<project>.fs
```
