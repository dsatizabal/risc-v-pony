# Risc V Pony: implemented CocoTB tests

A broad set of tests were implemented during the development of the CPU aiming to have wide covergae of the functions and real scenarios that can be found when implementing a real program. However, we cannot state that the tests are comprehensive and there may be corners uncoveres by the tests.

## The tests model

To perform tests a counterpart of the [SPI fetcher](../src/reg_file.v) was implemented in Python to simulate the Slave in the SPI interface, the [Fake SPI](../test/fake_spi.py) implements that counterpart and has the ability of both read data from a provided memory block or from a disk file, the latter used for real C/Assembly compiled programs.

There's 2 kind of tests: tests that contain a small program and pass a memory block to the Fake SPI and tests that pass a bin file path to the Fake SPI.

There's a [Firmware](../test/firmware/) folder in the test folder that contains all assets related to the code tests, we left the code, the run times and linker but also the genrated elf, bin and hex files for reference. You can always delete the object files and re-compile if desired.


## Implemented tests: direct program block

The following are the tests implemented for the Risc V Pony in direct assembly blocks

- [Core tests](/test/test_core.py) Implement some basics instructions like LUI, BEQ, SW, ADDI, etc.
- [IO tests](../test/test_io.py) mplement some tests that read/write to the configured I/O pins
- [RAM tests](../test/test_ram.py): Implements some write/readback operations to RAM memory
- [Jump tests](../test/test_jump.py): Implement a basic sub routine and call to it
- [Test ALU I-type](../test/test_alu_itype.py) and [Test ALU R-type](../test/test_alu_rtype.py): Perform immediate and registers ALU tests
- [Test branch condition](../test/test_branch_conditions.py): Test all the possible branch instructions
- [Test SPI realistic bin boot](../test/test_spi_realistic_bin_boot.py): Tests a small boot sequence, also was implemented to test a correction to byte endiannes on the Fake SPI
- [Test System Instructions](../test/test_system_instructions.py): Test the implemented behavior of the ECALL / EBREAK / FENCE instructions
- [Test U-type](../test/test_utype_lui_auipc.py): Tests the LUI and AUIPC instructions
- [Test Timer](../test/test_timer_mmio.py): Implements some basics tests based on the timer
- [Test Fibonacci](../test/test_fibonacci.py): Implements fibonacci sequence calculation

## Implemented tests: compiled code

The following are the tests implemented for the Risc V Pony in compiled code

- [Tests C Code](../test/test_c_code.py): A very basics [C program](../test/firmware/counter/main.c) that reads the input port and increments its value putting the increased value in the output port.
- [Firetest Assenbly](../test/test_firetest_asm.py): Runs a [small assembly program](../test/firmware/pony_firetest/firetest_asm.S) that performs some calculations including sum and max value calculation and returns a flag when done
- [Firetest C](../test/test_firetest_c.py): A [small C program](../test/firmware/pony_firetest/main.c) that performs similar calculations to the Assembly Firetests but implemented in C
- [Game logic test](../test/test_game_logic.py): Runs a [small C code](../test/firmware/pony_game_logic/main.c) that resembles some Gamepad IO and game player logic
- [Test interactive](../test/test_interactive.py): Runs a [C code](../test/firmware/7-segments/main.c) that allows to read keyboard input and generate a 7-segment output that increases on every enter hit

> NOTE: The interactive test MUST be disabled for GutHub actions or that will fail!

## Running the tests locally

- In the [test](./test/) folder create a Python Virtual Environment as follows:
```bash
python -m venv .venv
source .venv/bin/activate
```
- Install the requirements:
```bash
pip install -r requirements.txt
```
- Run the tests:
```bash
python -m venv .venv
make
```

You must see all tests passing

## Compiling C and Assembly code

You can use the following commands to compile C and Aseembly code

```bash
riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostartfiles -nostdlib -T link.ld crt0.s main.c -o main.elf -O1
riscv64-unknown-elf-objcopy -O binary main.elf firmware.bin
```

Some more advanced commands are available within some firmware folders in a Makefile, refer to those for further information.

## Testing in FPGA

Please refer to the [FPGA Bringup document](./fpga_bringup.MD)
