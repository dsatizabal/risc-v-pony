import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

_SENTINEL = 0xFF

@cocotb.test()
async def test_game_logic(dut):
    """Test: Run RiscV Pony game-logic C firmware"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    fake_flash = FakeSPIFlash(dut, bin_file="./firmware/pony_game_logic/firmware.bin")

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
                    dut._log.info(f"Game logic output detected: 0x{curr:02X}")
                prev = curr

    async def wait_for_outputs(count):
        while len(captured_sequence) < count:
            await RisingEdge(dut.clk)

    async def drive_gamepad():
        # Wait until the firmware emits:
        #   0x40 -> boot marker
        #   8    -> initial player x
        await wait_for_outputs(2)

        # Drive each input until the firmware consumes it and emits the
        # corresponding next player position. This is much more robust than
        # holding each input for a fixed cycle count because the compiled C
        # loop timing can change when optimization/code shape changes.
        #
        # Input sequence:
        #   RIGHT -> x 8  -> 9
        #   RIGHT -> x 9  -> 10
        #   LEFT  -> x 10 -> 9
        #   NONE  -> x 9  -> 9
        for index, value in enumerate([2, 2, 1, 0], start=3):
            dut.in_port.value = value
            await wait_for_outputs(index)

        dut.in_port.value = 0

    dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    cocotb.start_soon(monitor_mmio())
    cocotb.start_soon(drive_gamepad())

    dut._log.info("Booting RiscV Pony game-logic C firmware...")
    await ClockCycles(dut.clk, 45000)

    expected_sequence = [
        0x40, # boot marker
        8,    # initial x
        9,    # right
        10,   # right
        9,    # left
        9,    # none
        9,    # history[0]
        9,    # history[3]
        27,   # score = final x * 3
    ]

    dut._log.info(f"Captured game-logic sequence: {captured_sequence}")

    assert captured_sequence == expected_sequence, \
        f"Game logic failed! Expected {expected_sequence}, got {captured_sequence}"

    dut._log.info("SUCCESS! RiscV Pony executed the game-logic C firmware.")
