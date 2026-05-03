import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF

@cocotb.test()
async def test_firetest_c(dut):
    """Test: Run RiscV Pony Firetest C firmware"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, bin_file="./firmware/pony_firetest/firmware.bin")

    dut.in_port.value = 10

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
                    dut._log.info(f"Firetest C output detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Booting RiscV Pony Firetest C firmware...")
    await ClockCycles(dut.clk, 25000)

    expected_sequence = [
        0x11, # boot marker
        0x0B, # in_port 10 + 1
        0x0F, # sum_to(5)
        0x15, # mix_value(7, 4)
        0x42, # volatile stack local calculation
        0xAA, # branch path
    ]

    dut._log.info(f"Captured Firetest C sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"Firetest C failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! RiscV Pony executed the C Firetest firmware.")
