import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF


async def _run_program(dut, memory_map, cycles):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, memory_map)

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
                    dut._log.info(f"SYSTEM test output detected: 0x{curr:02X}")
                prev = curr

    dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    await ClockCycles(dut.clk, cycles)

    return captured_sequence


@cocotb.test()
async def test_fence_is_nop(dut):
    """Test: FENCE is accepted as a legal NOP"""

    # Program:
    #   x1 = MMIO_OUT
    #   x2 = SENTINEL
    #   x3 = 41
    #   FENCE
    #   x3 = x3 + 1
    #   emit x3
    #   trap forever
    memory_map = {
        0x00000000: 0x08000093, # ADDI  x1, x0, 128
        0x00000004: 0x0ff00113, # ADDI  x2, x0, 255
        0x00000008: 0x02900193, # ADDI  x3, x0, 41
        0x0000000C: 0x0ff0000f, # FENCE
        0x00000010: 0x00118193, # ADDI  x3, x3, 1
        0x00000014: 0x0020a023, # SW    x2, 0(x1)
        0x00000018: 0x0030a023, # SW    x3, 0(x1)
        0x0000001C: 0x00000063, # BEQ   x0, x0, 0
    }

    captured_sequence = await _run_program(dut, memory_map, 1000)

    assert captured_sequence == [42], \
        f"FENCE-as-NOP failed! Expected [42], got {captured_sequence}"

    dut._log.info("SUCCESS! FENCE behaved as a legal NOP.")


@cocotb.test()
async def test_ebreak_halts_core(dut):
    """Test: EBREAK halts before the following instruction sequence"""

    # Program:
    #   emit 0x11
    #   EBREAK
    #   attempt to emit 0xEE
    #
    # Expected: only 0x11 appears.
    memory_map = {
        0x00000000: 0x08000093, # ADDI  x1, x0, 128
        0x00000004: 0x0ff00113, # ADDI  x2, x0, 255
        0x00000008: 0x01100193, # ADDI  x3, x0, 0x11
        0x0000000C: 0x0020a023, # SW    x2, 0(x1)
        0x00000010: 0x0030a023, # SW    x3, 0(x1)
        0x00000014: 0x00100073, # EBREAK
        0x00000018: 0x0ee00193, # ADDI  x3, x0, 0xEE
        0x0000001C: 0x0020a023, # SW    x2, 0(x1)
        0x00000020: 0x0030a023, # SW    x3, 0(x1)
        0x00000024: 0x00000063, # BEQ   x0, x0, 0
    }

    captured_sequence = await _run_program(dut, memory_map, 2000)

    assert captured_sequence == [0x11], \
        f"EBREAK halt failed! Expected [0x11], got {captured_sequence}"

    dut._log.info("SUCCESS! EBREAK halted the core before later writes.")


@cocotb.test()
async def test_ecall_halts_core(dut):
    """Test: ECALL halts before the following instruction sequence"""

    # Program:
    #   emit 0x22
    #   ECALL
    #   attempt to emit 0xEE
    #
    # Expected: only 0x22 appears.
    memory_map = {
        0x00000000: 0x08000093, # ADDI  x1, x0, 128
        0x00000004: 0x0ff00113, # ADDI  x2, x0, 255
        0x00000008: 0x02200193, # ADDI  x3, x0, 0x22
        0x0000000C: 0x0020a023, # SW    x2, 0(x1)
        0x00000010: 0x0030a023, # SW    x3, 0(x1)
        0x00000014: 0x00000073, # ECALL
        0x00000018: 0x0ee00193, # ADDI  x3, x0, 0xEE
        0x0000001C: 0x0020a023, # SW    x2, 0(x1)
        0x00000020: 0x0030a023, # SW    x3, 0(x1)
        0x00000024: 0x00000063, # BEQ   x0, x0, 0
    }

    captured_sequence = await _run_program(dut, memory_map, 2000)

    assert captured_sequence == [0x22], \
        f"ECALL halt failed! Expected [0x22], got {captured_sequence}"

    dut._log.info("SUCCESS! ECALL halted the core before later writes.")
