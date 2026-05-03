import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from fake_spi import FakeSPIFlash

def draw_7seg(val):
    """Decodes a byte into clean ASCII 7-segment art"""
    a = "_" if (val & 0x01) else " "
    b = "|" if (val & 0x02) else " "
    c = "|" if (val & 0x04) else " "
    d = "_" if (val & 0x08) else " "
    e = "|" if (val & 0x10) else " "
    f = "|" if (val & 0x20) else " "
    g = "_" if (val & 0x40) else " "

    # Standard 7-segment visual layout
    print(f"\n  {a}  ")
    print(f" {f}{g}{b} ")
    print(f" {e}{d}{c} \n")

@cocotb.test()
async def test_interactive_menu(dut):
    """Test: Live Interactive 7-Segment Menu"""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Load our new 7-Segment C Firmware
    fake_flash = FakeSPIFlash(dut, bin_file="./firmware/7-segments/firmware.bin")

    dut.in_port.value = 0 # Button unpressed

    # System Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # -----------------------------------------------------------------
    # FIX 1: Give the CPU plenty of time to boot the C runtime and
    # fetch the first instruction over the slow SPI bus!
    # -----------------------------------------------------------------
    await ClockCycles(dut.clk, 3000)

    print("\n" + "="*40)
    print(" 🚀 RISC-V INTERACTIVE SIMULATION 🚀")
    print("="*40)

    while True:
        # 1. Read the physical output from the CPU
        current_out = dut.out_port.value.integer

        # 2. Draw what the CPU is outputting
        draw_7seg(current_out)

        # 3. Block the simulation and ask the human what to do!
        user_input = input("Press [ENTER] to press the button, or type 'q' to quit: ")

        if user_input.lower() == 'q':
            print("Shutting down the CPU... Great work today!")
            break

        # -----------------------------------------------------------------
        # FIX 2: Hold the button HIGH for 1000 clock cycles so the C
        # while(1) loop is guaranteed to catch the edge transition!
        # -----------------------------------------------------------------
        dut.in_port.value = 1
        await ClockCycles(dut.clk, 1000)

        # Release the button and wait another 1000 cycles for the CPU
        # to process the logic and update the physical output pins.
        dut.in_port.value = 0
        await ClockCycles(dut.clk, 1000)
