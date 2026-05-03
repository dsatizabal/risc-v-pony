import cocotb
import os
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Detect Gate Level simulation mode
GATES = os.environ.get('GATES', 'no').lower() == 'yes'

@cocotb.test()
async def test_jal_jalr(dut):
    """Test: JAL (Function Call) and JALR (Function Return)"""

    # Subroutine moved to 0x20 to make room for MMIO write-out in main.
    # Execution flow: 0x00 -> 0x20 -> 0x24 -> 0x04 -> 0x08 -> 0x0C -> 0x10 -> 0x14 -> 0x18
    # out_port transitions: 0 -> 4 -> 42 -> 99 (all distinct, all detectable)
    #
    # 0x00: JAL x1, 32        (Jump to 0x20, save 0x04 in x1)
    # 0x04: ADDI x2, x0, 99  (executed after subroutine returns)
    # 0x08: ADDI x5, x0, 128 (MMIO_OUT address)
    # 0x0C: SW x1, 0(x5)     -> out_port = 4  (return address)
    # 0x10: SW x3, 0(x5)     -> out_port = 42 (subroutine result)
    # 0x14: SW x2, 0(x5)     -> out_port = 99 (main continuation)
    # 0x18: BEQ x0, x0, 0    (trap)
    # --- SUBROUTINE at 0x20 ---
    # 0x20: ADDI x3, x0, 42
    # 0x24: JALR x0, 0(x1)   (return)
    memory_map = {
        0x00000000: 0x020000ef, # JAL x1, 32
        0x00000004: 0x06300113, # ADDI x2, x0, 99
        0x00000008: 0x08000293, # ADDI x5, x0, 128
        0x0000000C: 0x0012A023, # SW x1, 0(x5)
        0x00000010: 0x0032A023, # SW x3, 0(x5)
        0x00000014: 0x0022A023, # SW x2, 0(x5)
        0x00000018: 0x00000063, # BEQ x0, x0, 0
        # Subroutine:
        0x00000020: 0x02a00193, # ADDI x3, x0, 42
        0x00000024: 0x00008067, # JALR x0, 0(x1)
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

    dut._log.info("Executing Function Call & Return Program...")
    await ClockCycles(dut.clk, 800)

    assert len(captured) >= 3, \
        f"Expected 3 MMIO writes to out_port, got {len(captured)}: {captured}"
    x1_val = captured[0]  # return address = 4
    x3_val = captured[1]  # subroutine result = 42
    x2_val = captured[2]  # main continuation = 99

    dut._log.info(f"x1 (Return Address) = {x1_val}")
    dut._log.info(f"x3 (Subroutine execution) = {x3_val}")
    dut._log.info(f"x2 (Main routine return) = {x2_val}")

    assert x1_val == 4,  f"JAL Failed to link! Expected return address 4, got {x1_val}"
    assert x3_val == 42, f"JAL Failed to jump! Subroutine payload x3 = {x3_val}"
    assert x2_val == 99, f"JALR Failed to return! Main payload x2 = {x2_val}"

    dut._log.info("GRAND SLAM! The CPU successfully executed a function call and return!")
