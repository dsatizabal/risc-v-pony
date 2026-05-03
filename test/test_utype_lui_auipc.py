import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Sentinel value written to out_port before each U-type result so repeated
# or zero values still produce a detectable edge on the output port.
_SENTINEL = 0xFF

OP_LUI = 0x37
OP_AUIPC = 0x17
OP_IMM = 0x13
OP_STORE = 0x23
OP_BRANCH = 0x63


def _i_type(imm, rs1, funct3, rd, opcode=OP_IMM):
    imm &= 0xFFF
    return (
        (imm << 20) |
        (rs1 << 15) |
        (funct3 << 12) |
        (rd << 7) |
        opcode
    )


def _s_type(imm, rs2, rs1, funct3, opcode=OP_STORE):
    imm &= 0xFFF
    return (
        ((imm >> 5) << 25) |
        (rs2 << 20) |
        (rs1 << 15) |
        (funct3 << 12) |
        ((imm & 0x1F) << 7) |
        opcode
    )


def _b_type(imm, rs2, rs1, funct3, opcode=OP_BRANCH):
    imm &= 0x1FFF
    return (
        (((imm >> 12) & 0x1) << 31) |
        (((imm >> 5) & 0x3F) << 25) |
        (rs2 << 20) |
        (rs1 << 15) |
        (funct3 << 12) |
        (((imm >> 1) & 0xF) << 8) |
        (((imm >> 11) & 0x1) << 7) |
        opcode
    )


def _u_type(imm20, rd, opcode):
    return (
        ((imm20 & 0xFFFFF) << 12) |
        (rd << 7) |
        opcode
    )


def _build_utype_program():
    program = []
    labels = {}
    branch_fixups = []

    def pc():
        return len(program) * 4

    def label(name):
        labels[name] = pc()

    def emit(word):
        program.append(word)

    def emit_branch(label_name, rs1, rs2, funct3):
        branch_fixups.append((len(program), label_name, rs1, rs2, funct3))
        program.append(0)

    def emit_result(result_reg):
        emit(_s_type(0, 2, 1, 0b010))           # SW x2, 0(x1) sentinel
        emit(_s_type(0, result_reg, 1, 0b010))  # SW result, 0(x1)

    # Register plan:
    #   x1  = MMIO_OUT address, 128
    #   x2  = sentinel, 255
    #   x3  = result register
    #   x4+ = U-type results under test
    #
    # NOTE: This test only uses x0-x15 so it remains compatible with RV32E.

    # Common setup.
    emit(_i_type(128, 0, 0b000, 1))             # ADDI  x1, x0, 128
    emit(_i_type(255, 0, 0b000, 2))             # ADDI  x2, x0, 255

    # -------------------------------------------------------------
    # LUI: x4 = 0x12345000.
    # Add 0x678, then write the visible low byte.
    # Expected visible result: 0x78.
    # -------------------------------------------------------------
    emit(_u_type(0x12345, 4, OP_LUI))           # LUI   x4, 0x12345
    emit(_i_type(0x678, 4, 0b000, 3))           # ADDI  x3, x4, 0x678
    emit_result(3)

    # -------------------------------------------------------------
    # LUI with sign bit set in the upper immediate.
    # x4 = 0xFFFFF000, then add 0x7F.
    # Expected visible result: 0x7F.
    # -------------------------------------------------------------
    emit(_u_type(0xFFFFF, 4, OP_LUI))           # LUI   x4, 0xFFFFF
    emit(_i_type(0x07F, 4, 0b000, 3))           # ADDI  x3, x4, 0x07F
    emit_result(3)

    # -------------------------------------------------------------
    # AUIPC: this instruction is intentionally emitted at byte PC 0x28.
    # x5 = PC + 0x00001000 = 0x00001028.
    # Add 0x050 so the visible low byte becomes 0x78.
    # Expected visible result: 0x78.
    # -------------------------------------------------------------
    emit(_u_type(0x00001, 5, OP_AUIPC))         # AUIPC x5, 0x00001
    emit(_i_type(0x050, 5, 0b000, 3))           # ADDI  x3, x5, 0x050
    emit_result(3)

    # -------------------------------------------------------------
    # AUIPC with zero upper immediate.
    # This instruction is intentionally emitted at byte PC 0x38.
    # x6 = PC + 0 = 0x00000038.
    # Add 0x040 so the visible low byte becomes 0x78.
    # Expected visible result: 0x78.
    # -------------------------------------------------------------
    emit(_u_type(0x00000, 6, OP_AUIPC))         # AUIPC x6, 0x00000
    emit(_i_type(0x040, 6, 0b000, 3))           # ADDI  x3, x6, 0x040
    emit_result(3)

    # Trap forever.
    label("trap")
    emit_branch("trap", 0, 0, 0b000)            # BEQ   x0, x0, trap

    # Patch all branch immediates.
    for index, label_name, rs1, rs2, funct3 in branch_fixups:
        branch_pc = index * 4
        branch_target = labels[label_name]
        program[index] = _b_type(branch_target - branch_pc, rs2, rs1, funct3)

    return {
        address * 4: word
        for address, word in enumerate(program)
    }


@cocotb.test()
async def test_utype_lui_auipc(dut):
    """Test: RV32E U-type instructions LUI and AUIPC"""

    memory_map = _build_utype_program()

    expected_sequence = [
        0x78, # LUI 0x12345 + ADDI 0x678
        0x7F, # LUI 0xFFFFF + ADDI 0x07F
        0x78, # AUIPC at PC 0x28 + 0x1000 + ADDI 0x050
        0x78, # AUIPC at PC 0x38 + 0x0000 + ADDI 0x040
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
                    dut._log.info(f"U-type result detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing U-type LUI/AUIPC coverage program...")
    await ClockCycles(dut.clk, 3500)

    dut._log.info(f"Captured U-type sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"U-type test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! LUI and AUIPC produced expected results.")
