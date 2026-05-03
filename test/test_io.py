import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from fake_spi import FakeSPIFlash

@cocotb.test()
async def test_mmio(dut):
    """Test: Memory-Mapped I/O (Reading from in_port, writing to out_port)"""

    # 1. Define the Machine Code
    memory_map = {
        0x00000000: 0x08000093, # ADDI x1, x0, 128  (x1 = OUT Address)
        0x00000004: 0x08400113, # ADDI x2, x0, 132  (x2 = IN Address)
        0x00000008: 0x00012183, # LW   x3, 0(x2)    (Load from IN port into x3)
        0x0000000C: 0x00118193, # ADDI x3, x3, 1    (Add 1 to the input value)
        0x00000010: 0x0030a023, # SW   x3, 0(x1)    (Store the result to OUT port)
        0x00000014: 0x00000063  # BEQ  x0, x0, 0    (Infinite loop trap)
    }

    # 2. Start the clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # 3. Instantiate Fake SPI Memory
    fake_flash = FakeSPIFlash(dut, memory_map)

    # 4. Set the Physical Input Pins (Let's feed it the number 41)
    dut.in_port.value = 41

    # 5. Apply System Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # 6. Let the processor run!
    # 6 instructions * ~65 cycles = ~390 cycles. Wait 500 to be safe.
    dut._log.info("Executing Memory-Mapped I/O Program...")
    await ClockCycles(dut.clk, 500)

    # 7. Verify the results
    # We fed '41' into the physical pins. The CPU should have added 1 and
    # pushed '42' out to the physical output pins.
    _raw = dut.out_port.value
    assert 'x' not in _raw.binstr, f"out_port still X after 500 cycles — GL init issue"
    final_out = _raw.integer

    dut._log.info(f"Physical Input Port was: 41")
    dut._log.info(f"Physical Output Port is: {final_out}")

    # Assertions
    assert final_out == 42, f"MMIO Failed! Expected 42 on out_port, got {final_out}"

    dut._log.info("WORLD CONTACT! The CPU successfully read from and wrote to physical pins!")
