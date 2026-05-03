import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Sentinel value written to out_port before each Fibonacci number so that
# repeated consecutive values (e.g. 1,1) still produce a detectable edge.
# 0xFF is safe: the first 10 Fibonacci numbers are all <= 34.
_SENTINEL = 0xFF

@cocotb.test()
async def test_fibonacci(dut):
    """Heavy Duty Test: Compute 10 Fibonacci numbers and stream them to MMIO"""

    # INIT (5 instructions):
    #   0x00: ADDI x1, x0, 128   (MMIO_OUT address)
    #   0x04: ADDI x2, x0, 10    (loop counter)
    #   0x08: ADDI x3, x0, 0     (fib_a = 0)
    #   0x0C: ADDI x4, x0, 1     (fib_b = 1)
    #   0x10: ADDI x6, x0, 255   (sentinel = 0xFF)
    #
    # LOOP (7 instructions, starts at 0x14):
    #   0x14: SW x6, 0(x1)       -> out_port = 0xFF  (sentinel before each value)
    #   0x18: SW x3, 0(x1)       -> out_port = fib   (guarantees 0xFF->fib edge)
    #   0x1C: ADD x5, x3, x4     (next = a + b)
    #   0x20: ADD x3, x0, x4     (a = b)
    #   0x24: ADD x4, x0, x5     (b = next)
    #   0x28: ADDI x2, x2, -1    (counter--)
    #   0x2C: BNE x2, x0, -24   (back to 0x14)
    #
    #   0x30: BEQ x0, x0, 0      (trap)
    memory_map = {
        0x00000000: 0x08000093, # ADDI x1, x0, 128
        0x00000004: 0x00a00113, # ADDI x2, x0, 10
        0x00000008: 0x00000193, # ADDI x3, x0, 0
        0x0000000C: 0x00100213, # ADDI x4, x0, 1
        0x00000010: 0x0ff00313, # ADDI x6, x0, 255
        # Loop:
        0x00000014: 0x0060a023, # SW x6, 0(x1)   sentinel
        0x00000018: 0x0030a023, # SW x3, 0(x1)   fib value
        0x0000001c: 0x004182b3, # ADD x5, x3, x4
        0x00000020: 0x004001b3, # ADD x3, x0, x4
        0x00000024: 0x00500233, # ADD x4, x0, x5
        0x00000028: 0xfff10113, # ADDI x2, x2, -1
        0x0000002c: 0xfe0114e3, # BNE x2, x0, -24 (-> 0x14)
        0x00000030: 0x00000063, # BEQ x0, x0, 0
    }

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, memory_map)

    captured_sequence = []

    # Monitor out_port for transitions, filtering out the 0xFF sentinel.
    # Works at both RTL and Gate Level -- no internal signal access.
    async def monitor_mmio():
        prev = 0
        while True:
            await RisingEdge(dut.clk)
            _raw = dut.out_port.value
            if 'x' in _raw.binstr:
                continue
            curr = _raw.integer
            if curr != prev:
                if curr != _SENTINEL:
                    captured_sequence.append(curr)
                    dut._log.info(f"🔥 MMIO OUTPUT DETECTED: {curr} 🔥")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Start monitor after reset so prev=0 is well-defined (no X-state)
    cocotb.start_soon(monitor_mmio())

    dut._log.info("Starting Fibonacci computation engine...")
    await ClockCycles(dut.clk, 10000)

    dut._log.info(f"Final Captured Sequence: {captured_sequence}")

    expected_sequence = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
    assert captured_sequence == expected_sequence, \
        f"Bridge collapsed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("HEAVY DUTY TEST PASSED! The CPU is structurally sound!")
