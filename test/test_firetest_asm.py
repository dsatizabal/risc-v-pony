import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF

@cocotb.test()
async def test_firetest_asm(dut):
    """Test: Run RiscV Pony Firetest assembly firmware"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, bin_file="./firmware/pony_firetest/firetest_asm.bin")

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
                    dut._log.info(f"Firetest ASM output detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Booting RiscV Pony Firetest assembly firmware...")
    await ClockCycles(dut.clk, 20000)

    expected_sequence = [
        0x21, # boot marker
        0x0F, # sum_to(5)
        0x15, # mix_value(7, 4)
        0x42, # stack store/load calculation
        0xAA, # branch path
    ]

    dut._log.info(f"Captured Firetest ASM sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"Firetest ASM failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! RiscV Pony executed the assembly Firetest firmware.")
