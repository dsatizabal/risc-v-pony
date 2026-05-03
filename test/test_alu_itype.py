import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Sentinel value written to out_port before each ALU result so repeated
# or zero values still produce a detectable edge on the output port.
_SENTINEL = 0xFF

@cocotb.test()
async def test_alu_itype(dut):
    """Test: RV32E I-type ALU instructions"""

    # This program exercises the currently-supported I-type integer ALU
    # instructions and streams each result to MMIO_OUT.
    #
    # Expected visible result sequence:
    #   SLTI  = (-1 < 1) signed       = 1
    #   SLTIU = (1 < 0xFFFFFFFF)      = 1
    #   XORI  = 0x55 ^ 0x0F           = 0x5A
    #   ORI   = 0x50 | 0x0F           = 0x5F
    #   ANDI  = 0x5A & 0x0F           = 0x0A
    #   SLLI  = 1 << 3                = 8
    #   SRLI  = 0x80 >> 2             = 0x20
    #   SRAI  = -16 >> 2              = -4 -> low out_port byte = 0xFC
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
        0x00000000: 0x08000093, # ADDI  x1, x0, 128
        0x00000004: 0x0ff00113, # ADDI  x2, x0, 255

        # -------------------------------------------------------------
        # SLTI: x3 = (-1 < 1) signed = 1
        # -------------------------------------------------------------
        0x00000008: 0xfff00213, # ADDI  x4, x0, -1
        0x0000000C: 0x00122193, # SLTI  x3, x4, 1
        0x00000010: 0x0020a023, # SW    x2, 0(x1)
        0x00000014: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # SLTIU: x3 = (1 < 0xFFFFFFFF) unsigned = 1
        # -------------------------------------------------------------
        0x00000018: 0x00100293, # ADDI  x5, x0, 1
        0x0000001C: 0xfff2b193, # SLTIU x3, x5, -1
        0x00000020: 0x0020a023, # SW    x2, 0(x1)
        0x00000024: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # XORI: x3 = 0x55 ^ 0x0F = 0x5A
        # -------------------------------------------------------------
        0x00000028: 0x05500313, # ADDI  x6, x0, 0x55
        0x0000002C: 0x00f34193, # XORI  x3, x6, 0x0F
        0x00000030: 0x0020a023, # SW    x2, 0(x1)
        0x00000034: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # ORI: x3 = 0x50 | 0x0F = 0x5F
        # -------------------------------------------------------------
        0x00000038: 0x05000393, # ADDI  x7, x0, 0x50
        0x0000003C: 0x00f3e193, # ORI   x3, x7, 0x0F
        0x00000040: 0x0020a023, # SW    x2, 0(x1)
        0x00000044: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # ANDI: x3 = 0x5A & 0x0F = 0x0A
        # -------------------------------------------------------------
        0x00000048: 0x05a00413, # ADDI  x8, x0, 0x5A
        0x0000004C: 0x00f47193, # ANDI  x3, x8, 0x0F
        0x00000050: 0x0020a023, # SW    x2, 0(x1)
        0x00000054: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # SLLI: x3 = 1 << 3 = 8
        # -------------------------------------------------------------
        0x00000058: 0x00100493, # ADDI  x9, x0, 1
        0x0000005C: 0x00349193, # SLLI  x3, x9, 3
        0x00000060: 0x0020a023, # SW    x2, 0(x1)
        0x00000064: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # SRLI: x3 = 0x80 >> 2 = 0x20
        # -------------------------------------------------------------
        0x00000068: 0x08000513, # ADDI  x10, x0, 0x80
        0x0000006C: 0x00255193, # SRLI  x3, x10, 2
        0x00000070: 0x0020a023, # SW    x2, 0(x1)
        0x00000074: 0x0030a023, # SW    x3, 0(x1)

        # -------------------------------------------------------------
        # SRAI: x3 = -16 >> 2 = -4, visible low byte = 0xFC
        # -------------------------------------------------------------
        0x00000078: 0xff000593, # ADDI  x11, x0, -16
        0x0000007C: 0x4025d193, # SRAI  x3, x11, 2
        0x00000080: 0x0020a023, # SW    x2, 0(x1)
        0x00000084: 0x0030a023, # SW    x3, 0(x1)

        # Trap forever
        0x00000088: 0x00000063, # BEQ   x0, x0, 0
    }

    expected_sequence = [
        1,    # SLTI
        1,    # SLTIU
        0x5A, # XORI
        0x5F, # ORI
        0x0A, # ANDI
        8,    # SLLI
        0x20, # SRLI
        0xFC, # SRAI, low output byte of 0xFFFFFFFC
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
                    dut._log.info(f"ALU I-type result detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing I-type ALU coverage program...")
    await ClockCycles(dut.clk, 4500)

    dut._log.info(f"Captured I-type ALU sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"I-type ALU test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! All tested I-type ALU instructions produced expected results.")
