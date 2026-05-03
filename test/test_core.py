import cocotb
import os
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Detect Gate Level simulation mode
GATES = os.environ.get('GATES', 'no').lower() == 'yes'

@cocotb.test()
async def test_simple_addition(dut):
    """Test: ADDI x1, 5 -> ADDI x2, 7 -> ADD x3, x1, x2"""

    # Machine code + MMIO write-out so results are visible at gate-level
    # 0x00: ADDI x1, x0, 5
    # 0x04: ADDI x2, x0, 7
    # 0x08: ADD  x3, x1, x2
    # 0x0C: ADDI x4, x0, 128  (MMIO_OUT address)
    # 0x10: SW x1, 0(x4)      -> out_port = 5
    # 0x14: SW x2, 0(x4)      -> out_port = 7
    # 0x18: SW x3, 0(x4)      -> out_port = 12
    # 0x1C: BEQ x0, x0, 0     (trap)
    memory_map = {
        0x00000000: 0x00500093,
        0x00000004: 0x00700113,
        0x00000008: 0x002081b3,
        0x0000000C: 0x08000213,  # ADDI x4, x0, 128
        0x00000010: 0x00122023,  # SW x1, 0(x4)
        0x00000014: 0x00222023,  # SW x2, 0(x4)
        0x00000018: 0x00322023,  # SW x3, 0(x4)
        0x0000001C: 0x00000063,  # BEQ x0, x0, 0
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

    dut._log.info("Processor is running. Fetching instructions over SPI...")
    await ClockCycles(dut.clk, 600)

    assert len(captured) >= 3, \
        f"Expected 3 MMIO writes to out_port, got {len(captured)}: {captured}"
    x1_val, x2_val, x3_val = captured[0], captured[1], captured[2]

    dut._log.info(f"x1 = {x1_val}")
    dut._log.info(f"x2 = {x2_val}")
    dut._log.info(f"x3 = {x3_val}")

    assert x1_val == 5,  f"x1 failed! Expected 5, got {x1_val}"
    assert x2_val == 7,  f"x2 failed! Expected 7, got {x2_val}"
    assert x3_val == 12, f"x3 failed! Expected 12 (5+7), got {x3_val}"

    dut._log.info("SUCCESS! The RISC-V core executed the program correctly!")


@cocotb.test()
async def test_branch_loop(dut):
    """Test: A simple loop using BNE"""

    # Machine code + MMIO write-out (x2 first, then x1 for distinct edges)
    # Original loop: x1 counts 3->0, x2 accumulates 0+5+5+5=15, x3 = x2
    # 0x18: ADDI x4, x0, 128  (MMIO_OUT address)
    # 0x1C: SW x2, 0(x4)      -> out_port = 15
    # 0x20: SW x1, 0(x4)      -> out_port = 0
    # 0x24: BEQ x0, x0, 0     (trap)
    memory_map = {
        0x00000000: 0x00300093, # ADDI x1, x0, 3
        0x00000004: 0x00000113, # ADDI x2, x0, 0
        0x00000008: 0x00510113, # ADDI x2, x2, 5
        0x0000000C: 0xfff08093, # ADDI x1, x1, -1
        0x00000010: 0xfe009ce3, # BNE  x1, x0, -8
        0x00000014: 0x002001b3, # ADD  x3, x0, x2
        0x00000018: 0x08000213, # ADDI x4, x0, 128
        0x0000001C: 0x00222023, # SW x2, 0(x4)      -> 15
        0x00000020: 0x00122023, # SW x1, 0(x4)      -> 0
        0x00000024: 0x00000063, # BEQ x0, x0, 0
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

    dut._log.info("Executing Branch Loop Program...")
    await ClockCycles(dut.clk, 1500)

    assert len(captured) >= 2, \
        f"Expected 2 MMIO writes to out_port, got {len(captured)}: {captured}"
    x2_val = captured[0]  # x2 written first (15)
    x1_val = captured[1]  # x1 written second (0)

    dut._log.info(f"Final Loop Counter (x1) = {x1_val}")
    dut._log.info(f"Final Accumulator (x2) = {x2_val}")

    assert x1_val == 0,  f"Loop failed to terminate! x1 = {x1_val}"
    assert x2_val == 15, f"Accumulator math failed! x2 = {x2_val}"

    # RTL-only: also verify x3 via internal register file
    if not GATES:
        x3_val = dut.uut.processor.regs.registers[3].value.integer
        dut._log.info(f"RTL-only: x3 = {x3_val}")
        assert x3_val == 15, f"ADD x3, x0, x2 failed! x3 = {x3_val}"

    dut._log.info("SUCCESS! The CPU successfully executed a backward branch loop!")
