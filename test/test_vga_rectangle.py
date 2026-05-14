import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

# MMIO addresses
MMIO_OUT = 128
MMIO_VGA_CTRL = 140
MMIO_VGA_RECT_X = 148
MMIO_VGA_RECT_Y = 152
MMIO_VGA_RECT_W = 156
MMIO_VGA_RECT_H = 160
MMIO_VGA_RECT_COLOR = 164

# VGA colors: {R[1:0], G[1:0], B[1:0]}
COLOR_GREEN = 0x0C


def encode_addi(rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (0x0 << 12) | (rd << 7) | 0x13


def encode_sw(rs2, rs1, imm):
    imm &= 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0x2 << 12) | (imm_4_0 << 7) | 0x23


def encode_beq(rs1, rs2, imm):
    # imm is signed branch offset in bytes. For BEQ x0,x0,0 this is simple.
    imm &= 0x1FFF
    bit12 = (imm >> 12) & 1
    bit11 = (imm >> 11) & 1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF
    return (
        (bit12 << 31)
        | (bits10_5 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (0x0 << 12)
        | (bits4_1 << 8)
        | (bit11 << 7)
        | 0x63
    )


def make_store_program(pairs):
    """Generate a tiny RV32E program that stores immediate values to MMIO addresses."""
    pc = 0
    memory_map = {}

    for addr, value in pairs:
        memory_map[pc] = encode_addi(1, 0, addr)   # x1 = MMIO address
        pc += 4
        memory_map[pc] = encode_addi(2, 0, value)  # x2 = value
        pc += 4
        memory_map[pc] = encode_sw(2, 1, 0)        # sw x2, 0(x1)
        pc += 4

    memory_map[pc] = encode_beq(0, 0, 0)           # trap forever
    return memory_map


def get_signal_by_path(dut, path):
    obj = dut
    for part in path.split("."):
        if not hasattr(obj, part):
            return None
        obj = getattr(obj, part)
    return obj


def find_first_signal(dut, candidates):
    for path in candidates:
        sig = get_signal_by_path(dut, path)
        if sig is not None:
            dut._log.info(f"Using VGA signal path: {path}")
            return sig
    return None


async def wait_for_gpio_value(dut, expected, max_cycles=100000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        raw = dut.out_port.value
        if "x" in raw.binstr.lower() or "z" in raw.binstr.lower():
            continue
        if (raw.integer & 0xFF) == expected:
            return
    raise AssertionError(f"Timed out waiting for GPIO/out_port value 0x{expected:02X}")


async def wait_for_pixel(dut, pix_x_sig, pix_y_sig, active_sig, x, y, max_cycles=1000000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(active_sig.value) == 1 and int(pix_x_sig.value) == x and int(pix_y_sig.value) == y:
            return
    raise AssertionError(f"Timed out waiting for active pixel ({x}, {y})")


def color_from_vga_out(v):
    # vga_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
    r = (((v >> 4) & 1) << 0) | (((v >> 0) & 1) << 1)
    g = (((v >> 5) & 1) << 0) | (((v >> 1) & 1) << 1)
    b = (((v >> 6) & 1) << 0) | (((v >> 2) & 1) << 1)
    return (r << 4) | (g << 2) | b


@cocotb.test()
async def test_vga_rectangle_overlay(dut):
    """Enable VGA rectangle mode and verify a configured pixel is rendered."""

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    rect_x = 120
    rect_y = 80
    rect_w = 64
    rect_h = 48
    rect_color = COLOR_GREEN

    # First prove normal GPIO mode, then configure rectangle regs, then enable VGA+rectangle.
    memory_map = make_store_program([
        (MMIO_OUT, 0x15),
        (MMIO_VGA_RECT_X, rect_x),
        (MMIO_VGA_RECT_Y, rect_y),
        (MMIO_VGA_RECT_W, rect_w),
        (MMIO_VGA_RECT_H, rect_h),
        (MMIO_VGA_RECT_COLOR, rect_color),
        (MMIO_VGA_CTRL, 0x03),  # bit0 VGA enable, bit1 rectangle enable
    ])

    FakeSPIFlash(dut, memory_map=memory_map)

    # Default input pins low. The gamepad is irrelevant for this test.
    if hasattr(dut, "in_port"):
        dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    await wait_for_gpio_value(dut, 0x15)
    dut._log.info("GPIO mode verified before enabling VGA")

    pix_x = find_first_signal(dut, [
        "uut.processor.vga.pix_x",
        "uut.vga.pix_x",
        "processor.vga.pix_x",
        "vga.pix_x",
    ])
    pix_y = find_first_signal(dut, [
        "uut.processor.vga.pix_y",
        "uut.vga.pix_y",
        "processor.vga.pix_y",
        "vga.pix_y",
    ])
    active = find_first_signal(dut, [
        "uut.processor.vga.video_active",
        "uut.vga.video_active",
        "processor.vga.video_active",
        "vga.video_active",
    ])

    assert pix_x is not None, "Could not find VGA pix_x signal. Add its hierarchical path to the candidates."
    assert pix_y is not None, "Could not find VGA pix_y signal. Add its hierarchical path to the candidates."
    assert active is not None, "Could not find VGA video_active signal. Add its hierarchical path to the candidates."

    # Pick a point safely inside the rectangle.
    sample_x = rect_x + 8
    sample_y = rect_y + 8

    await wait_for_pixel(dut, pix_x, pix_y, active, sample_x, sample_y)

    out_raw = dut.out_port.value
    assert "x" not in out_raw.binstr.lower(), "out_port contains X at rectangle sample point"
    out_value = out_raw.integer & 0xFF
    sampled_color = color_from_vga_out(out_value)

    dut._log.info(
        f"Rectangle sample at ({sample_x}, {sample_y}): "
        f"vga_out=0x{out_value:02X}, decoded_color=0x{sampled_color:02X}"
    )

    assert sampled_color == rect_color, (
        f"Rectangle color mismatch: expected 0x{rect_color:02X}, got 0x{sampled_color:02X} "
        f"from vga_out=0x{out_value:02X}"
    )

    # Also sample a point just outside the rectangle. We do not require a specific
    # color-bar value here, but it should not equal the forced rectangle color at
    # this chosen location because x=rect_x-8 is in the red bar, not green.
    outside_x = rect_x - 8
    outside_y = rect_y + 8
    await wait_for_pixel(dut, pix_x, pix_y, active, outside_x, outside_y)

    out_raw = dut.out_port.value
    out_value = out_raw.integer & 0xFF
    outside_color = color_from_vga_out(out_value)

    dut._log.info(
        f"Outside sample at ({outside_x}, {outside_y}): "
        f"vga_out=0x{out_value:02X}, decoded_color=0x{outside_color:02X}"
    )

    assert outside_color != rect_color, (
        "Outside rectangle sample unexpectedly matched the rectangle color; "
        "check rectangle bounds or background color choice."
    )

    dut._log.info("SUCCESS: VGA rectangle overlay is visible at the expected pixel coordinates.")
