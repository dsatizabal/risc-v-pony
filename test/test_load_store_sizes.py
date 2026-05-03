import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Sentinel value written to out_port before each Load/Store result so repeated
# or zero values still produce a detectable edge on the output port.
_SENTINEL = 0xFF

OP_LUI = 0x37
OP_IMM = 0x13
OP_LOAD = 0x03
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


def _u_type(imm20, rd, opcode=OP_LUI):
    return (
        ((imm20 & 0xFFFFF) << 12) |
        (rd << 7) |
        opcode
    )


def _emit_result(program, marker_reg, out_reg, result_reg):
    program.append(_s_type(0, marker_reg, out_reg, 0b010)) # SW sentinel, 0(out)
    program.append(_s_type(0, result_reg, out_reg, 0b010)) # SW result, 0(out)


def _build_load_store_program():
    program = []
    branch_fixups = []
    labels = {}

    def pc():
        return len(program) * 4

    def label(name):
        labels[name] = pc()

    def emit(word):
        program.append(word)

    def emit_branch(label_name, rs1, rs2, funct3):
        branch_fixups.append((len(program), label_name, rs1, rs2, funct3))
        program.append(0)

    # Register plan:
    #   x1  = MMIO_OUT address, 128
    #   x2  = sentinel, 255
    #   x3  = result register
    #   x4  = RAM base address, 16
    #   x5  = temporary store data
    #   x6  = temporary load data
    #
    # NOTE: This test only uses x0-x15 so it remains compatible with RV32E.

    # Common setup.
    emit(_i_type(128, 0, 0b000, 1))             # ADDI x1, x0, 128
    emit(_i_type(255, 0, 0b000, 2))             # ADDI x2, x0, 255
    emit(_i_type(16, 0, 0b000, 4))              # ADDI x4, x0, 16

    # -------------------------------------------------------------
    # SB + LB: store 0x80 at base+1, load signed byte.
    # Expected: LB sign-extends to negative, so SLTI x3, x6, 0 = 1.
    # -------------------------------------------------------------
    emit(_i_type(128, 0, 0b000, 5))             # ADDI x5, x0, 0x80
    emit(_s_type(1, 5, 4, 0b000))               # SB   x5, 1(x4)
    emit(_i_type(1, 4, 0b000, 6, OP_LOAD))      # LB   x6, 1(x4)
    emit(_i_type(0, 6, 0b010, 3))               # SLTI x3, x6, 0
    _emit_result(program, 2, 1, 3)

    # -------------------------------------------------------------
    # LBU: load the same byte as unsigned.
    # Expected: LBU zero-extends to positive, so SLTI x3, x6, 0 = 0.
    # -------------------------------------------------------------
    emit(_i_type(1, 4, 0b100, 6, OP_LOAD))      # LBU  x6, 1(x4)
    emit(_i_type(0, 6, 0b010, 3))               # SLTI x3, x6, 0
    _emit_result(program, 2, 1, 3)

    # -------------------------------------------------------------
    # SH + LH: store 0x8001 at base+2, load signed halfword.
    # Expected: LH sign-extends to negative, so SLTI x3, x6, 0 = 1.
    # -------------------------------------------------------------
    emit(_u_type(0x00008, 5))                   # LUI  x5, 0x00008
    emit(_i_type(1, 5, 0b000, 5))               # ADDI x5, x5, 1
    emit(_s_type(2, 5, 4, 0b001))               # SH   x5, 2(x4)
    emit(_i_type(2, 4, 0b001, 6, OP_LOAD))      # LH   x6, 2(x4)
    emit(_i_type(0, 6, 0b010, 3))               # SLTI x3, x6, 0
    _emit_result(program, 2, 1, 3)

    # -------------------------------------------------------------
    # LHU: load the same halfword as unsigned.
    # Expected: LHU zero-extends to positive, so SLTI x3, x6, 0 = 0.
    # -------------------------------------------------------------
    emit(_i_type(2, 4, 0b101, 6, OP_LOAD))      # LHU  x6, 2(x4)
    emit(_i_type(0, 6, 0b010, 3))               # SLTI x3, x6, 0
    _emit_result(program, 2, 1, 3)

    # -------------------------------------------------------------
    # SW + LW: store 0x12345678 at base+4 and load it back.
    # Expected visible low byte: 0x78.
    # -------------------------------------------------------------
    emit(_u_type(0x12345, 5))                   # LUI  x5, 0x12345
    emit(_i_type(0x678, 5, 0b000, 5))           # ADDI x5, x5, 0x678
    emit(_s_type(4, 5, 4, 0b010))               # SW   x5, 4(x4)
    emit(_i_type(4, 4, 0b010, 3, OP_LOAD))      # LW   x3, 4(x4)
    _emit_result(program, 2, 1, 3)

    # Trap forever.
    label("trap")
    emit_branch("trap", 0, 0, 0b000)            # BEQ  x0, x0, trap

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
async def test_load_store_sizes(dut):
    """Test: RV32E load/store sizes and sign extension"""

    memory_map = _build_load_store_program()

    expected_sequence = [
        1,    # LB sign-extension produced a negative value
        0,    # LBU zero-extension produced a non-negative value
        1,    # LH sign-extension produced a negative value
        0,    # LHU zero-extension produced a non-negative value
        0x78, # LW after SW, visible low byte of 0x12345678
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
                    dut._log.info(f"Load/Store result detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing load/store size and sign-extension program...")
    await ClockCycles(dut.clk, 6000)

    dut._log.info(f"Captured Load/Store sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"Load/Store size test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! Load/store sizes and sign-extension behavior are correct.")
