import cocotb
import os
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Detect Gate Level simulation mode
GATES = os.environ.get('GATES', 'no').lower() == 'yes'

@cocotb.test()
async def test_load_store(dut):
    """Test: SW (Store Word) and LW (Load Word) to Internal RAM"""

    # Machine code + MMIO write-out so results are visible at gate-level.
    # Write x3 first (42), then x2 (0): transitions 0->42->0 are both detectable.
    # 0x00: ADDI x1, x0, 16   (x1 = RAM Address 16)
    # 0x04: ADDI x2, x0, 42   (x2 = Data 42)
    # 0x08: SW   x2, 0(x1)    (RAM[16] = x2)
    # 0x0C: ADDI x2, x0, 0    (x2 = 0, clear!)
    # 0x10: LW   x3, 0(x1)    (x3 = RAM[16])
    # 0x14: ADDI x5, x0, 128  (MMIO_OUT address)
    # 0x18: SW x3, 0(x5)      -> out_port = 42
    # 0x1C: SW x2, 0(x5)      -> out_port = 0
    # 0x20: BEQ x0, x0, 0     (trap)
    memory_map = {
        0x00000000: 0x01000093,
        0x00000004: 0x02a00113,
        0x00000008: 0x0020a023,
        0x0000000C: 0x00000113,
        0x00000010: 0x0000a183,
        0x00000014: 0x08000293,  # ADDI x5, x0, 128
        0x00000018: 0x0032A023,  # SW x3, 0(x5)
        0x0000001C: 0x0022A023,  # SW x2, 0(x5)
        0x00000020: 0x00000063,  # BEQ x0, x0, 0
    }

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, memory_map)

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Monitor out_port for transitions -- works at both RTL and Gate Level
    captured = []
    async def monitor_output():
        prev = 0
        while True:
            await RisingEdge(dut.clk)
            _raw = dut.out_port.value
            if 'x' in _raw.binstr:
                continue
            curr = _raw.integer
            if curr != prev:
                captured.append(curr)
                prev = curr
    cocotb.start_soon(monitor_output())

    dut._log.info("Executing Load/Store Memory Program...")
    await ClockCycles(dut.clk, 700)

    assert len(captured) >= 2, \
        f"Expected 2 MMIO writes to out_port, got {len(captured)}: {captured}"
    x3_val = captured[0]  # x3 written first (42, loaded from RAM)
    x2_val = captured[1]  # x2 written second (0, cleared)

    dut._log.info(f"x3 (Loaded from RAM) = {x3_val}")
    dut._log.info(f"x2 (Cleared Register) = {x2_val}")

    assert x3_val == 42, f"LW Failed! x3 holds {x3_val} instead of 42."
    assert x2_val == 0,  f"Clear Failed! x2 holds {x2_val} instead of 0."

    # RTL-only: also peek directly at the Verilog RAM array
    if not GATES:
        ram_val = dut.uut.processor.data_memory.memory[4].value.integer
        dut._log.info(f"RTL-only: Direct RAM[4] = {ram_val}")
        assert ram_val == 42, f"SW Failed! RAM holds {ram_val} instead of 42."

    dut._log.info("SUCCESS! Data was successfully stored to and loaded from Internal RAM!")
