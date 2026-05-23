import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from fake_spi import FakeSPIFlash

# Pony MMIO map used by the gamepad integration:
#   0x80 / 128 -> GPIO output register, visible as out_port
#   0x90 / 144 -> gamepad0 state register
MMIO_OUT = 128
MMIO_GAMEPAD = 144

# Output markers used by the tiny firmware below. These make it easy for the
# testbench to identify a complete low-byte/high-byte sample frame.
LOW_MARKER = 0xEE
HIGH_MARKER = 0xDD

# Core-visible gamepad_data bit layout, as currently packed in core.v:
#   bit 12 = present
#   bit 11 = select
#   bit 10 = start
#   bit 9  = left
#   bit 8  = right
#   bit 7  = down
#   bit 6  = up
#   bit 5  = L
#   bit 4  = R
#   bit 3  = Y
#   bit 2  = X
#   bit 1  = B
#   bit 0  = A
CORE_BUTTON_BITS = {
    "a": 0,
    "b": 1,
    "x": 2,
    "y": 3,
    "r": 4,
    "l": 5,
    "up": 6,
    "down": 7,
    "right": 8,
    "left": 9,
    "start": 10,
    "select": 11,
}
PRESENT_BIT = 12

# Raw 12-bit data_reg bit layout expected by gamepad_pmod_decoder:
#   assign {b, y, select, start, up, down, left, right, a, x, l, r} = data_reg;
# Therefore data_reg[11]=B, [10]=Y, [9]=Select, [8]=Start, [7]=Up,
# [6]=Down, [5]=Left, [4]=Right, [3]=A, [2]=X, [1]=L, [0]=R.
RAW_DECODER_BITS = {
    "b": 11,
    "y": 10,
    "select": 9,
    "start": 8,
    "up": 7,
    "down": 6,
    "left": 5,
    "right": 4,
    "a": 3,
    "x": 2,
    "l": 1,
    "r": 0,
}


def gamepad_state_for(buttons, present=True):
    """Return the 13-bit value expected at Pony's MMIO_GAMEPAD register."""
    value = (1 << PRESENT_BIT) if present else 0
    for button in buttons:
        value |= 1 << CORE_BUTTON_BITS[button]
    return value


def raw_pmod_word_for(buttons, present=True):
    """
    Return the raw 12-bit serial word that must be shifted into gamepad.v.

    For a connected controller with no buttons pressed, this is 0x000.
    For an absent controller, gamepad.v treats 0xFFF as not present.
    """
    if not present:
        return 0xFFF

    value = 0
    for button in buttons:
        value |= 1 << RAW_DECODER_BITS[button]
    return value


def set_gamepad_lines(dut, data, clk, latch):
    """Drive pmod_data=in_port[6], pmod_clk=in_port[5], pmod_latch=in_port[4]."""
    raw = dut.in_port.value.binstr.lower()
    base = 0 if any(ch in raw for ch in "xzuw-") else int(dut.in_port.value)

    base &= ~((1 << 6) | (1 << 5) | (1 << 4))
    base |= (int(data) & 1) << 6
    base |= (int(clk) & 1) << 5
    base |= (int(latch) & 1) << 4
    dut.in_port.value = base


async def drive_gamepad_raw_word(dut, raw_word):
    """
    Shift one 12-bit PMOD frame into the gamepad driver.

    The RTL synchronizes pmod_data/pmod_clk/pmod_latch into clk, so each
    signal level is held for multiple system-clock cycles.
    """
    set_gamepad_lines(dut, data=0, clk=0, latch=0)
    await ClockCycles(dut.clk, 8)

    for bit_index in range(11, -1, -1):
        bit = (raw_word >> bit_index) & 1

        set_gamepad_lines(dut, data=bit, clk=0, latch=0)
        await ClockCycles(dut.clk, 4)

        set_gamepad_lines(dut, data=bit, clk=1, latch=0)
        await ClockCycles(dut.clk, 4)

        set_gamepad_lines(dut, data=bit, clk=0, latch=0)
        await ClockCycles(dut.clk, 4)

    # The driver latches the completed shift register on pmod_latch rising.
    set_gamepad_lines(dut, data=0, clk=0, latch=1)
    await ClockCycles(dut.clk, 8)
    set_gamepad_lines(dut, data=0, clk=0, latch=0)
    await ClockCycles(dut.clk, 8)


async def drive_gamepad_buttons(dut, buttons, present=True):
    raw_word = raw_pmod_word_for(buttons, present=present)
    await drive_gamepad_raw_word(dut, raw_word)


async def wait_for_gamepad_output_frame(dut, expected_state, max_cycles=120_000):
    """
    Wait for the test firmware to output:

        low_byte, LOW_MARKER, high_byte, HIGH_MARKER

    where low/high are derived from the 13-bit gamepad state read at MMIO 144.
    """
    expected_low = expected_state & 0xFF
    expected_high = (expected_state >> 8) & 0xFF
    expected = [expected_low, LOW_MARKER, expected_high, HIGH_MARKER]

    stage = 0
    transitions = []

    raw = dut.out_port.value.binstr.lower()
    prev = None if any(ch in raw for ch in "xzuw-") else (int(dut.out_port.value) & 0xFF)

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

        raw = dut.out_port.value.binstr.lower()
        if any(ch in raw for ch in "xzuw-"):
            continue

        curr = int(dut.out_port.value) & 0xFF
        if prev is None:
            prev = curr
            continue

        if curr == prev:
            continue

        prev = curr
        transitions.append(curr)
        if len(transitions) > 32:
            transitions.pop(0)

        if curr == expected[stage]:
            stage += 1
            if stage == len(expected):
                return transitions
        else:
            # Restart matching if this transition could be the first byte of a new frame.
            stage = 1 if curr == expected[0] else 0

    raise AssertionError(
        f"Timed out waiting for gamepad frame {expected}; "
        f"last transitions={transitions}"
    )


# Firmware loaded into FakeSPIFlash:
#
#   li   x1, MMIO_GAMEPAD
#   li   x2, MMIO_OUT
# loop:
#   lw   x3, 0(x1)        # x3 = gamepad_state
#   andi x4, x3, 0x0ff    # low byte
#   sw   x4, 0(x2)
#   li   x5, 0xee
#   sw   x5, 0(x2)
#   srli x4, x3, 8        # high byte, contains present/start/select/etc.
#   sw   x4, 0(x2)
#   li   x5, 0xdd
#   sw   x5, 0(x2)
#   j    loop
GAMEPAD_MMIO_READER_PROGRAM = {
    0x00000000: 0x09000093,  # ADDI x1, x0, 144
    0x00000004: 0x08000113,  # ADDI x2, x0, 128
    0x00000008: 0x0000A183,  # LW   x3, 0(x1)
    0x0000000C: 0x0FF1F213,  # ANDI x4, x3, 255
    0x00000010: 0x00412023,  # SW   x4, 0(x2)
    0x00000014: 0x0EE00293,  # ADDI x5, x0, 0xEE
    0x00000018: 0x00512023,  # SW   x5, 0(x2)
    0x0000001C: 0x0081D213,  # SRLI x4, x3, 8
    0x00000020: 0x00412023,  # SW   x4, 0(x2)
    0x00000024: 0x0DD00293,  # ADDI x5, x0, 0xDD
    0x00000028: 0x00512023,  # SW   x5, 0(x2)
    0x0000002C: 0xFDDFF06F,  # JAL  x0, -36 -> 0x08
}


@cocotb.test()
async def test_gamepad_mmio_single_buttons_and_combo(dut):
    """Verify Pony can read gamepad button states through MMIO address 144."""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    FakeSPIFlash(dut, GAMEPAD_MMIO_READER_PROGRAM)

    dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1

    # First present/no-button frame. This checks the presence bit path.
    await drive_gamepad_buttons(dut, [])
    expected_state = gamepad_state_for([])
    transitions = await wait_for_gamepad_output_frame(dut, expected_state)
    dut._log.info(f"Gamepad no-button frame OK: state=0x{expected_state:04X}, transitions={transitions}")

    for button in ["a", "b", "x", "y", "r", "l", "up", "down", "right", "left", "start", "select"]:
        await drive_gamepad_buttons(dut, [button])
        expected_state = gamepad_state_for([button])
        transitions = await wait_for_gamepad_output_frame(dut, expected_state)
        dut._log.info(
            f"Gamepad button {button.upper()} OK: "
            f"state=0x{expected_state:04X}, transitions={transitions}"
        )

    combo = ["a", "b", "start", "up", "left", "r"]
    await drive_gamepad_buttons(dut, combo)
    expected_state = gamepad_state_for(combo)
    transitions = await wait_for_gamepad_output_frame(dut, expected_state)
    dut._log.info(f"Gamepad combo {combo} OK: state=0x{expected_state:04X}, transitions={transitions}")

    dut._log.info("SUCCESS: Pony read all tested gamepad states through MMIO.")
