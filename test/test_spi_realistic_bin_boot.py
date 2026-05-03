import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF


@cocotb.test()
async def test_spi_realistic_bin_boot(dut):
    """Test: boot from a realistic little-endian firmware.bin over SPI"""

    # This is a normal little-endian RISC-V binary image, not a word-swapped
    # simulation-only image. The fake SPI flash will return bytes in increasing
    # address order, exactly like a real SPI flash.
    words = [
        0x08000093, # ADDI  x1, x0, 128
        0x0ff00113, # ADDI  x2, x0, 255
        0x02a00193, # ADDI  x3, x0, 42
        0x0020a023, # SW    x2, 0(x1)
        0x0030a023, # SW    x3, 0(x1)
        0x00000063, # BEQ   x0, x0, 0
    ]

    firmware = b"".join(word.to_bytes(4, byteorder="little") for word in words)

    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(firmware)
        firmware_path = f.name

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, bin_file=firmware_path)

    captured_sequence = []

    async def monitor_mmio():
        prev = 0
        while True:
            await RisingEdge(dut.clk)
            _raw = dut.out_port.value
            if 'x' in _raw.binstr:
                continue

            curr = _raw.integer & 0xFF
            if curr != prev:
                if curr != _SENTINEL:
                    captured_sequence.append(curr)
                    dut._log.info(f"SPI realistic-bin output detected: 0x{curr:02X}")
                prev = curr

    dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Booting from realistic byte-addressed SPI flash model...")
    await ClockCycles(dut.clk, 2500)

    assert captured_sequence == [42], \
        f"Realistic SPI bin boot failed! Expected [42], got {captured_sequence}"

    dut._log.info("SUCCESS! Realistic SPI byte-stream boot produced the expected result.")

    Path(firmware_path).unlink(missing_ok=True)
