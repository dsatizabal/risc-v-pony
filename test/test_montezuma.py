import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

# RGB222 Color decoding
def color_from_vga_out(v):
    r = (((v >> 4) & 1) << 0) | (((v >> 0) & 1) << 1)
    g = (((v >> 5) & 1) << 0) | (((v >> 1) & 1) << 1)
    b = (((v >> 6) & 1) << 0) | (((v >> 2) & 1) << 1)
    return (r << 4) | (g << 2) | b

def rgb222_to_rgb888(color):
    return (((color >> 4) & 0x3) * 85, ((color >> 2) & 0x3) * 85, (color & 0x3) * 85)

# Frame Capturer
async def capture_single_frame(dut, pix_x, pix_y, active, filename, width=640, height=480):
    frame = bytearray(width * height * 3)
    seen = [[False] * width for _ in range(height)]
    count = 0

    dut._log.info(f"Capturing {filename}...")

    # Wait for frame start
    while True:
        await RisingEdge(dut.clk)
        if int(active.value) == 1 and int(pix_x.value) == 0 and int(pix_y.value) == 0:
            break

    # Record pixels
    while count < width * height:
        await RisingEdge(dut.clk)
        if int(active.value) != 1: continue

        x, y = int(pix_x.value), int(pix_y.value)
        if not (0 <= x < width and 0 <= y < height): continue

        raw = dut.out_port.value
        color = 0x00 if ('x' in raw.binstr.lower() or 'z' in raw.binstr.lower()) else color_from_vga_out(raw.integer & 0xFF)

        r, g, b = rgb222_to_rgb888(color)
        idx = (y * width + x) * 3
        frame[idx] = r; frame[idx + 1] = g; frame[idx + 2] = b

        if not seen[y][x]:
            seen[y][x] = True
            count += 1

    with open(filename, 'wb') as f:
        f.write(f"P6\n{width} {height}\n255\n".encode('ascii'))
        f.write(frame)
    dut._log.info(f"Saved {filename}!")

# Gamepad Driver
async def drive_gamepad_raw(dut, raw_word):
    def set_pins(data, clk, latch):
        val = int(dut.in_port.value) if 'x' not in dut.in_port.value.binstr.lower() else 0
        val = val & ~(0b1110000)
        dut.in_port.value = val | ((data & 1) << 6) | ((clk & 1) << 5) | ((latch & 1) << 4)

    set_pins(0, 0, 0)
    await ClockCycles(dut.clk, 8)
    for bit_index in range(11, -1, -1):
        bit = (raw_word >> bit_index) & 1
        set_pins(bit, 0, 0); await ClockCycles(dut.clk, 4)
        set_pins(bit, 1, 0); await ClockCycles(dut.clk, 4)
        set_pins(bit, 0, 0); await ClockCycles(dut.clk, 4)

    set_pins(0, 0, 1); await ClockCycles(dut.clk, 8)
    set_pins(0, 0, 0); await ClockCycles(dut.clk, 8)

# Signal finder
def get_signal_by_path(dut, path):
    obj = dut
    for part in path.split('.'):
        if not hasattr(obj, part): return None
        obj = getattr(obj, part)
    return obj

def find_first_signal(dut, candidates, label):
    for path in candidates:
        sig = get_signal_by_path(dut, path)
        if sig is not None:
            return sig
    raise AssertionError(f"Could not find {label}")

@cocotb.test()
async def test_montezuma(dut):
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())

    # Load the compiled binary!
    FakeSPIFlash(dut, bin_file="./firmware/montezuma/montezuma.bin")

    if hasattr(dut, 'in_port'): dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    pix_x = find_first_signal(dut, ['uut.processor.vga.hpos', 'uut.vga.hpos', 'processor.vga.vga_sync_gen.hpos', 'uut.processor.vga.vga_sync_gen.hpos'], 'VGA pix_x')
    pix_y = find_first_signal(dut, ['uut.processor.vga.vpos', 'uut.vga.vpos', 'processor.vga.vga_sync_gen.vpos', 'uut.processor.vga.vga_sync_gen.vpos'], 'VGA pix_y')
    active = find_first_signal(dut, ['uut.processor.vga.display_on', 'uut.vga.display_on', 'processor.vga.vga_sync_gen.display_on', 'uut.processor.vga.vga_sync_gen.display_on'], 'VGA active')

    # Give CPU time to boot, draw the static scene, and enter the polling loop
    await ClockCycles(dut.clk, 250_000)

    dut._log.info("Frame 1: Idle (No input)")
    await drive_gamepad_raw(dut, 0x000)
    await capture_single_frame(dut, pix_x, pix_y, active, "montezuma_0_idle.ppm")

    dut._log.info("Frame 2: Holding Right")
    await drive_gamepad_raw(dut, (1 << 4)) # Right button is bit 4 of the raw decoder
    await capture_single_frame(dut, pix_x, pix_y, active, "montezuma_1_right.ppm")

    dut._log.info("Frame 3: Holding Left")
    await drive_gamepad_raw(dut, (1 << 5)) # Left button is bit 5
    await capture_single_frame(dut, pix_x, pix_y, active, "montezuma_2_left.ppm")

    dut._log.info("SUCCESS: Montezuma vertical slice simulated with real software!")
