import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash
from test_wait_utils import wait_for_captured_count, wait_until_signal_value

# Sentinel value written to out_port before each ALU result so repeated
# or zero values still produce a detectable edge on the output port.
_SENTINEL = 0xFF

@cocotb.test()
async def test_alu_rtype(dut):
    """Test: RV32E R-type ALU instructions"""

    # This program exercises the currently-supported R-type integer ALU
    # instructions and streams each result to MMIO_OUT.
    #
    # Expected visible result sequence:
    #   SUB  = 9 - 4       = 5
    #   SLL  = 1 << 3      = 8
    #   SLT  = -1 < 1      = 1
    #   SLTU = 1 < -1      = 1
    #   XOR  = 0x55 ^ 0x0F = 0x5A
    #   SRL  = 0x80 >> 2   = 0x20
    #   SRA  = -8 >> 1     = -4  -> low out_port byte = 0xFC
    #   OR   = 0x50 | 0x0F = 0x5F
    #   AND  = 0x5A & 0x0F = 0x0A
    #
    # Register plan:
    #   x1  = MMIO_OUT address, 128
    #   x2  = sentinel, 255
    #   x3  = result register
    #   x4+ = operands
    #
    # NOTE: This test only uses x0-x15 so it remains compatible with RV32E.
    memory_map = {
        # Common setup
        0x00000000: 0x08000093, # ADDI x1, x0, 128
        0x00000004: 0x0ff00113, # ADDI x2, x0, 255

        # -------------------------------------------------------------
        # SUB: x3 = x4 - x5 = 9 - 4 = 5
        # -------------------------------------------------------------
        0x00000008: 0x00900213, # ADDI x4, x0, 9
        0x0000000C: 0x00400293, # ADDI x5, x0, 4
        0x00000010: 0x405201b3, # SUB  x3, x4, x5
        0x00000014: 0x0020a023, # SW   x2, 0(x1)
        0x00000018: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # SLL: x3 = x6 << x7 = 1 << 3 = 8
        # -------------------------------------------------------------
        0x0000001C: 0x00100313, # ADDI x6, x0, 1
        0x00000020: 0x00300393, # ADDI x7, x0, 3
        0x00000024: 0x007311b3, # SLL  x3, x6, x7
        0x00000028: 0x0020a023, # SW   x2, 0(x1)
        0x0000002C: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # SLT: x3 = (-1 < 1) signed = 1
        # -------------------------------------------------------------
        0x00000030: 0xfff00413, # ADDI x8, x0, -1
        0x00000034: 0x00100493, # ADDI x9, x0, 1
        0x00000038: 0x009421b3, # SLT  x3, x8, x9
        0x0000003C: 0x0020a023, # SW   x2, 0(x1)
        0x00000040: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # SLTU: x3 = (1 < 0xFFFFFFFF) unsigned = 1
        # -------------------------------------------------------------
        0x00000044: 0x00100513, # ADDI x10, x0, 1
        0x00000048: 0xfff00593, # ADDI x11, x0, -1
        0x0000004C: 0x00b531b3, # SLTU x3, x10, x11
        0x00000050: 0x0020a023, # SW   x2, 0(x1)
        0x00000054: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # XOR: x3 = 0x55 ^ 0x0F = 0x5A
        # -------------------------------------------------------------
        0x00000058: 0x05500613, # ADDI x12, x0, 0x55
        0x0000005C: 0x00f00693, # ADDI x13, x0, 0x0F
        0x00000060: 0x00d641b3, # XOR  x3, x12, x13
        0x00000064: 0x0020a023, # SW   x2, 0(x1)
        0x00000068: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # SRL: x3 = 0x80 >> 2 = 0x20
        # -------------------------------------------------------------
        0x0000006C: 0x08000713, # ADDI x14, x0, 0x80
        0x00000070: 0x00200793, # ADDI x15, x0, 2
        0x00000074: 0x00f751b3, # SRL  x3, x14, x15
        0x00000078: 0x0020a023, # SW   x2, 0(x1)
        0x0000007C: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # SRA: x3 = -8 >> 1 = -4, visible low byte = 0xFC
        # -------------------------------------------------------------
        0x00000080: 0xff800213, # ADDI x4, x0, -8
        0x00000084: 0x00100293, # ADDI x5, x0, 1
        0x00000088: 0x405251b3, # SRA  x3, x4, x5
        0x0000008C: 0x0020a023, # SW   x2, 0(x1)
        0x00000090: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # OR: x3 = 0x50 | 0x0F = 0x5F
        # -------------------------------------------------------------
        0x00000094: 0x05000313, # ADDI x6, x0, 0x50
        0x00000098: 0x00f00393, # ADDI x7, x0, 0x0F
        0x0000009C: 0x007361b3, # OR   x3, x6, x7
        0x000000A0: 0x0020a023, # SW   x2, 0(x1)
        0x000000A4: 0x0030a023, # SW   x3, 0(x1)

        # -------------------------------------------------------------
        # AND: x3 = 0x5A & 0x0F = 0x0A
        # -------------------------------------------------------------
        0x000000A8: 0x05a00413, # ADDI x8, x0, 0x5A
        0x000000AC: 0x00f00493, # ADDI x9, x0, 0x0F
        0x000000B0: 0x009471b3, # AND  x3, x8, x9
        0x000000B4: 0x0020a023, # SW   x2, 0(x1)
        0x000000B8: 0x0030a023, # SW   x3, 0(x1)

        # Trap forever
        0x000000BC: 0x00000063, # BEQ  x0, x0, 0
    }

    expected_sequence = [
        5,    # SUB
        8,    # SLL
        1,    # SLT
        1,    # SLTU
        0x5A, # XOR
        0x20, # SRL
        0xFC, # SRA, low output byte of 0xFFFFFFFC
        0x5F, # OR
        0x0A, # AND
    ]

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
                    dut._log.info(f"ALU R-type result detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing R-type ALU coverage program...")
    await wait_for_captured_count(
        dut, captured_sequence, len(expected_sequence),
        max_cycles=80_000,
        label="R-type ALU result writes"
    )

    dut._log.info(f"Captured R-type ALU sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"R-type ALU test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! All tested R-type ALU instructions produced expected results.")
