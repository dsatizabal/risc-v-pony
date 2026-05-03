![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# RiscV Pony

<img src="./img/risc-v-pony.png" width=500 />

A simple multi-cycle RiscV RV32E implementation.

Implement basics instructions like:

- Arithmetic
- Logics
- Storage
- Branching

Supports running C code compiled for RiscV.

- [Read the documentation for project](docs/info.md)

## Running the local tests

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
- Observe that some tests rely on the [firmware](./test/firmware/) folder where two C programs lie: [the counter demo](./test/firmware/counter/) and the [7 segments demo](./test/firmware/7-segments/). The bin file must exist for those tests to run, if those files are not there follow this instructions:

-- Navigate to one of the demo folders and run:
```bash
riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostartfiles -nostdlib -T link.ld crt0.s main.c -o main.elf -O1
riscv64-unknown-elf-objcopy -O binary main.elf firmware.bin
```
--Observe that the following files MUST exists to properly compile the program:

crt0.s
```javascript
.section .init
    .global _start

_start:
    # Set the Stack Pointer (x2) to the very top of our RAM.
    # We will tell the linker our RAM starts at 0x200, and is 128 bytes long.
    # So the top of the stack is 0x200 + 128 = 0x280.
    li sp, 0x280

    # Jump to the C main function
    jal main

trap:
    # If main() ever returns, trap the CPU in an infinite loop
    j trap

```

link.ld
```javascript
MEMORY {
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 1024   /* 1KB of SPI Flash */
    RAM (rw) : ORIGIN = 0x00000200, LENGTH = 128    /* 128 Bytes of internal SRAM */
}

SECTIONS {
    /* Put the boot code and program instructions in ROM */
    .text : {
        *(.init)
        *(.text*)
    } > ROM

    /* Put variables in RAM */
    .data : { *(.data*) *(.rodata*) *(.sdata*) } > RAM AT> ROM
    .bss  : { *(.bss*) *(.sbss*) } > RAM
}
```

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
