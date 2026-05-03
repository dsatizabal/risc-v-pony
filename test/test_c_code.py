import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

@cocotb.test()
async def test_c_firmware(dut):
    """Test: Run compiled C firmware from disk"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, bin_file="./firmware/counter/firmware.bin")

    dut.in_port.value = 100

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    dut._log.info("Booting C Firmware...")

    # Wait for out_port to update 3 times by monitoring transitions.
    # The firmware writes 100, 101, 102 sequentially to MMIO_OUT (address 128),
    # so each write produces a distinct edge on out_port.
    # This replaces internal mem_we/is_mmio_out/rs2_data monitoring so it
    # works at both RTL and Gate Level.
    outputs_seen = 0
    prev_out = 0  # out_port resets to 0

    while outputs_seen < 3:
        await RisingEdge(dut.clk)
        _raw = dut.out_port.value
        if 'x' in _raw.binstr:
            continue
        curr_out = _raw.integer
        if curr_out != prev_out:
            val = curr_out
            dut._log.info(f"C CODE MMIO WRITE: {val}")

            if outputs_seen == 0:
                assert val == 100, f"First output: expected 100, got {val}"
            if outputs_seen == 1:
                assert val == 101, f"Second output: expected 101, got {val}"
            if outputs_seen == 2:
                assert val == 102, f"Third output: expected 102, got {val}"

            prev_out = curr_out
            outputs_seen += 1

    dut._log.info("SUCCESS! The RISC-V core is executing compiled C code!")
