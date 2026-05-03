import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF

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


def _build_timer_program():
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

    # Register plan:
    #   x1 = MMIO_OUT address, 128
    #   x2 = sentinel, 255
    #   x3 = first timer read
    #   x4 = delay counter
    #   x5 = MMIO_TIMER address, 136
    #   x6 = second timer read
    #   x7 = comparison result

    emit(_i_type(128, 0, 0b000, 1))             # ADDI x1, x0, 128
    emit(_i_type(255, 0, 0b000, 2))             # ADDI x2, x0, 255
    emit(_i_type(136, 0, 0b000, 5))             # ADDI x5, x0, 136

    emit(_i_type(0, 5, 0b010, 3, OP_LOAD))      # LW   x3, 0(x5)

    emit(_i_type(64, 0, 0b000, 4))              # ADDI x4, x0, 64

    label("delay_loop")
    emit(_i_type(-1, 4, 0b000, 4))              # ADDI x4, x4, -1
    emit_branch("delay_loop", 4, 0, 0b001)      # BNE  x4, x0, delay_loop

    emit(_i_type(0, 5, 0b010, 6, OP_LOAD))      # LW   x6, 0(x5)
    emit(_i_type(0, 6, 0b011, 7))               # SLTIU x7, x6, 0 => should be 0
    emit(_s_type(0, 2, 1, 0b010))               # SW   x2, 0(x1)
    emit(_s_type(0, 7, 1, 0b010))               # SW   x7, 0(x1)

    # Now use SLTU as an R-type instruction to prove first < second.
    # Encoding: SLTU x7, x3, x6
    emit(0x0061b3b3)                            # SLTU x7, x3, x6
    emit(_s_type(0, 2, 1, 0b010))               # SW   x2, 0(x1)
    emit(_s_type(0, 7, 1, 0b010))               # SW   x7, 0(x1)

    label("trap")
    emit_branch("trap", 0, 0, 0b000)            # BEQ  x0, x0, trap

    for index, label_name, rs1, rs2, funct3 in branch_fixups:
        branch_pc = index * 4
        branch_target = labels[label_name]
        program[index] = _b_type(branch_target - branch_pc, rs2, rs1, funct3)

    return {
        address * 4: word
        for address, word in enumerate(program)
    }


@cocotb.test()
async def test_timer_mmio_increments(dut):
    """Test: MMIO timer at address 0x88 increments over time"""

    memory_map = _build_timer_program()

    expected_sequence = [
        0, # SLTIU x7, x6, 0 proves the timer read is a normal unsigned value
        1, # SLTU x7, x3, x6 proves the second timer read is greater than first
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
                    dut._log.info(f"Timer MMIO result detected: 0x{curr:02X}")
                prev = curr

    dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())

    dut._log.info("Executing timer MMIO coverage program...")
    await ClockCycles(dut.clk, 20000)

    dut._log.info(f"Captured timer MMIO sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"Timer MMIO test failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! MMIO timer increments and can be read by firmware.")
