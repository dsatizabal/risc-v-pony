<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A multi-cycle RV32E RISC-V soft-core. Instructions are fetched from an external SPI Flash chip over a 4-wire SPI bus (command `0x03`, 24-bit address, 32-bit data — 64 clock cycles per fetch). Each instruction passes through a 3-stage loop: **FETCH → WAIT → EXECUTE**. During EXECUTE the register file is read, the ALU computes the result, and the program counter is updated — all in a single clock cycle.

The core supports the full RV32I base integer instruction set reduced to 16 registers (RV32E): arithmetic (ADD/SUB/AND/OR/XOR/shifts/comparisons), immediate variants, all six branch types (BEQ/BNE/BLT/BGE/BLTU/BGEU), JAL/JALR, LUI/AUIPC, and byte/halfword/word loads and stores.

Data memory is 128 bytes of internal SRAM (addresses 0–127). Two memory-mapped I/O registers are appended to the address space:

- **Address 128 (`0x80`)** — write the low byte to the 8-bit output port (`uo_out`)
- **Address 132 (`0x84`)** — read the 8-bit input port (`ui_in`) as a zero-extended 32-bit value

## How to test

Power the Tiny Tapeout dev board and connect an SPI Flash chip (see External Hardware). Program the Flash with your RV32E binary (the chip can be pre-programmed off-board using any SPI programmer).

**Minimal smoke test — blink an LED:**

1. Write a short RV32E program that loads a value, increments it in a loop, and stores the result to address 128. Compile with a bare-metal RV32E toolchain (e.g. `riscv32-unknown-elf-gcc -march=rv32e -mabi=ilp32e`) and flash the binary to the SPI chip starting at address `0x000000`.
2. Connect an LED (with a current-limiting resistor) to any `uo_out` pin.
3. Assert reset (`rst_n` low), then release it. The LED should blink at a rate determined by your loop delay.

**7-segment display test:**

Connect a common-cathode 7-segment display (with 8 × 330 Ω resistors) to `uo_out[7:0]`. Write a program that repeatedly stores segment patterns to address 128 and loops through the digits 0–9 with a software delay. Each digit pattern should be visible on the display.

**I/O round-trip test:**

Set switches or jumpers on `ui_in[7:0]` to a known value. Write a program that loads from address 132 and stores the result (optionally incremented) to address 128. Confirm `uo_out` matches the expected value.

Reset is applied by holding `rst_n` low for at least one clock cycle. The PC starts at `0x000000`, so the first instruction in the Flash is executed first.

## External hardware

- **SPI NOR Flash** (e.g. W25Q32, AT25SF041, or any chip supporting the `0x03` Read command) — stores the program binary. Connect to the bidirectional pins: `uio[0]` = CS, `uio[1]` = SCK, `uio[2]` = MOSI, `uio[3]` = MISO. Bypass capacitor (100 nF) recommended close to the VCC pin.
- **7-segment display** (common-cathode, single digit) — connect segments A–G + DP to `uo_out[7:0]` for visual output tests.
- **8 × 330 Ω resistors** — current limiting for the 7-segment display.
- **LED + 330 Ω resistor** — for a simple blink test on any `uo_out` pin.
- **DIP switches or jumpers** (optional) — drive `ui_in[7:0]` to test the input port.
