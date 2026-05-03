import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Sentinel value written to out_port before each branch result so repeated
# or zero values still produce a detectable edge on the output port.
_SENTINEL = 0xFF
_FAIL = 0xEE

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


def _build_branch_program():
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

    def emit_fail_marker():
        emit(_i_type(_FAIL, 0, 0b000, 3))       # ADDI x3, x0, _FAIL
        emit(_s_type(0, 3, 1, 0b010))           # SW x3, 0(x1)

    def emit_taken_case(name, marker, setup_words, rs1, rs2, funct3):
        for word in setup_words:
            emit(word)
        emit(_s_type(0, 2, 1, 0b010))           # SW x2, 0(x1) sentinel
        emit_branch(f"{name}_pass", rs1, rs2, funct3)
        emit_fail_marker()
        label(f"{name}_pass")
        emit(_i_type(marker, 0, 0b000, 3))      # ADDI x3, x0, marker
        emit(_s_type(0, 3, 1, 0b010))           # SW x3, 0(x1)

    def emit_not_taken_case(name, marker, setup_words, rs1, rs2, funct3):
        for word in setup_words:
            emit(word)
        emit(_s_type(0, 2, 1, 0b010))           # SW x2, 0(x1) sentinel
        emit_branch(f"{name}_fail", rs1, rs2, funct3)
        emit(_i_type(marker, 0, 0b000, 3))      # ADDI x3, x0, marker
        emit(_s_type(0, 3, 1, 0b010))           # SW x3, 0(x1)
        emit_branch(f"{name}_done", 0, 0, 0b000)
        label(f"{name}_fail")
        emit_fail_marker()
        label(f"{name}_done")

    # Common setup:
    #   x1 = MMIO_OUT address, 128
    #   x2 = sentinel, 255
    emit(_i_type(128, 0, 0b000, 1))             # ADDI x1, x0, 128
    emit(_i_type(255, 0, 0b000, 2))             # ADDI x2, x0, 255

    # Taken branch cases.
    emit_taken_case(
        "beq_taken",
        1,
        [
            _i_type(5, 0, 0b000, 4),            # ADDI x4, x0, 5
            _i_type(5, 0, 0b000, 5),            # ADDI x5, x0, 5
        ],
        4,
        5,
        0b000,                                  # BEQ
    )

    emit_taken_case(
        "bne_taken",
        2,
        [
            _i_type(5, 0, 0b000, 4),            # ADDI x4, x0, 5
            _i_type(6, 0, 0b000, 5),            # ADDI x5, x0, 6
        ],
        4,
        5,
        0b001,                                  # BNE
    )

    emit_taken_case(
        "blt_taken",
        3,
        [
            _i_type(-1, 0, 0b000, 4),           # ADDI x4, x0, -1
            _i_type(1, 0, 0b000, 5),            # ADDI x5, x0, 1
        ],
        4,
        5,
        0b100,                                  # BLT, signed
    )

    emit_taken_case(
        "bge_taken",
        4,
        [
            _i_type(-1, 0, 0b000, 4),           # ADDI x4, x0, -1
            _i_type(-2, 0, 0b000, 5),           # ADDI x5, x0, -2
        ],
        4,
        5,
        0b101,                                  # BGE, signed
    )

    emit_taken_case(
        "bltu_taken",
        5,
        [
            _i_type(1, 0, 0b000, 4),            # ADDI x4, x0, 1
            _i_type(-1, 0, 0b000, 5),           # ADDI x5, x0, -1
        ],
        4,
        5,
        0b110,                                  # BLTU, unsigned
    )

    emit_taken_case(
        "bgeu_taken",
        6,
        [
            _i_type(-1, 0, 0b000, 4),           # ADDI x4, x0, -1
            _i_type(1, 0, 0b000, 5),            # ADDI x5, x0, 1
        ],
        4,
        5,
        0b111,                                  # BGEU, unsigned
    )

    # Not-taken branch cases. These protect against implementations that
    # always branch once the opcode is recognized.
    emit_not_taken_case(
        "beq_not_taken",
        7,
        [
            _i_type(5, 0, 0b000, 4),            # ADDI x4, x0, 5
            _i_type(6, 0, 0b000, 5),            # ADDI x5, x0, 6
        ],
        4,
        5,
        0b000,                                  # BEQ
    )

    emit_not_taken_case(
        "bltu_not_taken",
        8,
        [
            _i_type(-1, 0, 0b000, 4),           # ADDI x4, x0, -1
            _i_type(1, 0, 0b000, 5),            # ADDI x5, x0, 1
        ],
        4,
        5,
        0b110,                                  # BLTU, unsigned
    )

    # Trap forever.
    label("trap")
    emit_branch("trap", 0, 0, 0b000)            # BEQ x0, x0, trap

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
async def test_branch_conditions(dut):
    """Test: RV32E branch condition coverage"""

    memory_map = _build_branch_program()

    expected_sequence = [
        1, # BEQ taken
        2, # BNE taken
        3, # BLT taken, signed
        4, # BGE taken, signed
        5, # BLTU taken, unsigned
        6, # BGEU taken, unsigned
        7, # BEQ not taken
        8, # BLTU not taken
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
                    dut._log.info(f"Branch result detected: 0x{curr:02X}")
                prev = curr

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing branch condition coverage program...")
    await ClockCycles(dut.clk, 8000)

    dut._log.info(f"Captured branch sequence: {captured_sequence}")

    assert _FAIL not in captured_sequence, \
        f"A branch case reached the failure marker: {captured_sequence}"

    assert captured_sequence == expected_sequence, \
        f"Branch condition test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! All tested branch conditions produced expected results.")
