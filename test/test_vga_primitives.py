import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

from fake_spi import FakeSPIFlash


# ============================================================
# MMIO addresses
# ============================================================

MMIO_OUT = 128
MMIO_VGA_CTRL = 140
MMIO_VGA_OBJ_INDEX = 148
MMIO_VGA_OBJ_WORD0 = 152
MMIO_VGA_OBJ_WORD1 = 156
MMIO_VGA_BG_COLOR = 160


# ============================================================
# VGA primitive constants
# ============================================================

OBJ_RECT = 0b00
OBJ_OCTAGON = 0b01
OBJ_LINE = 0b10

# RGB222 color constants: {R[1:0], G[1:0], B[1:0]}
COLOR_BLACK = 0x00
COLOR_BLUE = 0x03
COLOR_GREEN = 0x0C
COLOR_CYAN = 0x0F
COLOR_RED = 0x30
COLOR_MAGENTA = 0x33
COLOR_YELLOW = 0x3C
COLOR_WHITE = 0x3F


# ============================================================
# RV32E-safe instruction encoders
# ============================================================

def r_type(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return (
        ((funct7 & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def i_type(imm, rs1, funct3, rd, opcode=0x13):
    return (
        ((imm & 0xFFF) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def s_type(imm, rs2, rs1, funct3=0x2, opcode=0x23):
    imm &= 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F

    return (
        (imm_11_5 << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | (imm_4_0 << 7)
        | (opcode & 0x7F)
    )


def b_type(imm, rs2, rs1, funct3=0x0, opcode=0x63):
    imm &= 0x1FFF

    imm_12 = (imm >> 12) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    imm_11 = (imm >> 11) & 0x1

    return (
        (imm_12 << 31)
        | (imm_10_5 << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | (imm_4_1 << 8)
        | (imm_11 << 7)
        | (opcode & 0x7F)
    )


def lui(rd, imm20):
    assert 0 <= rd <= 15, "RV32E-safe tests must use x0..x15 only"
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37


def addi(rd, rs1, imm):
    assert 0 <= rd <= 15, "RV32E-safe tests must use x0..x15 only"
    assert 0 <= rs1 <= 15, "RV32E-safe tests must use x0..x15 only"
    return i_type(imm, rs1, 0x0, rd, 0x13)


def sw(rs2, offset, rs1):
    assert 0 <= rs1 <= 15, "RV32E-safe tests must use x0..x15 only"
    assert 0 <= rs2 <= 15, "RV32E-safe tests must use x0..x15 only"
    return s_type(offset, rs2, rs1, 0x2, 0x23)


def beq(rs1, rs2, imm):
    assert 0 <= rs1 <= 15, "RV32E-safe tests must use x0..x15 only"
    assert 0 <= rs2 <= 15, "RV32E-safe tests must use x0..x15 only"
    return b_type(imm, rs2, rs1, 0x0, 0x63)


def load_imm(rd, value):
    """
    Load a full 32-bit constant into rd using LUI + ADDI.

    This handles the ADDI sign-extension case correctly.

    Example:
      value = 0x4106E600

      upper = (value + 0x800) >> 12
      lower = value - (upper << 12)

    The lower part is then encoded as a signed 12-bit immediate.
    """
    assert 0 <= rd <= 15, "RV32E-safe tests must use x0..x15 only"

    value &= 0xFFFFFFFF

    upper = (value + 0x800) >> 12
    lower = value - (upper << 12)

    if lower >= 2048:
        lower -= 4096

    if lower < -2048 or lower > 2047:
        raise ValueError(f"Bad ADDI lower immediate: {lower}")

    insts = []

    if upper != 0:
        insts.append(lui(rd, upper))
        if lower != 0:
            insts.append(addi(rd, rd, lower))
    else:
        insts.append(addi(rd, 0, lower))

    return insts


def emit_store_mmio(program, addr, value, r_addr=1, r_val=2):
    """
    Store a 32-bit value to an MMIO address.

    Uses only x1 and x2 by default, so it is RV32E-safe.
    """
    assert 0 <= r_addr <= 15
    assert 0 <= r_val <= 15

    program.extend(load_imm(r_addr, addr))
    program.extend(load_imm(r_val, value))
    program.append(sw(r_val, 0, r_addr))


# ============================================================
# Primitive packers
# ============================================================

def pack_word0(obj_type, x, y, param0=0, enable=True):
    """
    Common WORD0 format:

      [31:30] primitive type
      [29]    enable
      [28:19] x0 / center_x
      [18:10] y0 / center_y
      [9:0]   radius for octagon, x1 for line, unused for rect
    """
    return (
        ((obj_type & 0x3) << 30)
        | ((1 if enable else 0) << 29)
        | ((x & 0x3FF) << 19)
        | ((y & 0x1FF) << 10)
        | (param0 & 0x3FF)
    ) & 0xFFFFFFFF


def pack_rect_word0(x, y, enable=True):
    return pack_word0(OBJ_RECT, x, y, 0, enable)


def pack_rect_word1(width, height, color):
    """
    Rectangle WORD1:

      [31:22] width
      [21:13] height
      [12:7]  RGB222 color
      [6:0]   reserved
    """
    return (
        ((width & 0x3FF) << 22)
        | ((height & 0x1FF) << 13)
        | ((color & 0x3F) << 7)
    ) & 0xFFFFFFFF


def pack_oct_word0(cx, cy, radius, enable=True):
    return pack_word0(OBJ_OCTAGON, cx, cy, radius, enable)


def pack_oct_word1(color):
    return ((color & 0x3F) << 7) & 0xFFFFFFFF


def pack_line_word0(x0, y0, x1, enable=True):
    return pack_word0(OBJ_LINE, x0, y0, x1, enable)


def pack_line_word1(y1, color):
    """
    Line WORD1:

      [31:23] y1
      [12:7]  RGB222 color
      [6:0]   reserved
    """
    return (
        ((y1 & 0x1FF) << 23)
        | ((color & 0x3F) << 7)
    ) & 0xFFFFFFFF


def emit_object(program, index, word0, word1):
    """
    Program one VGA object slot through MMIO.

    Software-visible sequence:

      0x94 -> object index
      0x98 -> object WORD0
      0x9C -> object WORD1 and commit
    """
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, index & 0xF)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD0, word0)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, word1)


def build_firmware_memory_map(objects, bg_color=COLOR_BLACK):
    program = []

    # Prove GPIO mode before VGA owns out_port.
    emit_store_mmio(program, MMIO_OUT, 0x15)

    # Black background.
    emit_store_mmio(program, MMIO_VGA_BG_COLOR, bg_color)

    # Program object table.
    for index, word0, word1, label in objects:
        emit_object(program, index, word0, word1)

    # Enable VGA mode after all objects are programmed.
    emit_store_mmio(program, MMIO_VGA_CTRL, 0x01)

    # Trap forever.
    program.append(beq(0, 0, 0))

    return {
        i * 4: inst & 0xFFFFFFFF
        for i, inst in enumerate(program)
    }


# ============================================================
# Cocotb signal helpers
# ============================================================

def get_signal_by_path(dut, path):
    obj = dut
    for part in path.split('.'):
        if not hasattr(obj, part):
            return None
        obj = getattr(obj, part)
    return obj


def find_first_signal(dut, candidates, label):
    for path in candidates:
        sig = get_signal_by_path(dut, path)
        if sig is not None:
            dut._log.info(f"Using {label} signal path: {path}")
            return sig

    raise AssertionError(
        f"Could not find {label}; add its hierarchical path to the candidate list"
    )


def find_optional_signal(dut, candidates, label):
    for path in candidates:
        sig = get_signal_by_path(dut, path)
        if sig is not None:
            dut._log.info(f"Using optional {label} signal path: {path}")
            return sig

    dut._log.warning(f"Could not find optional {label}; using fallback")
    return None


def value_is_known(value):
    s = value.binstr.lower()
    return ('x' not in s) and ('z' not in s) and ('u' not in s)


def color_from_vga_out(v):
    """
    vga_out packing:

      {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}

    Reconstruct RGB222 as:

      {R[1:0], G[1:0], B[1:0]}
    """
    r = (((v >> 4) & 1) << 0) | (((v >> 0) & 1) << 1)
    g = (((v >> 5) & 1) << 0) | (((v >> 1) & 1) << 1)
    b = (((v >> 6) & 1) << 0) | (((v >> 2) & 1) << 1)

    return (r << 4) | (g << 2) | b


def rgb222_to_rgb888(color):
    r2 = (color >> 4) & 0x3
    g2 = (color >> 2) & 0x3
    b2 = color & 0x3

    return (r2 * 85, g2 * 85, b2 * 85)


# ============================================================
# Wait / sample helpers
# ============================================================

async def wait_for_gpio_value(dut, expected, max_cycles=200_000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

        raw = dut.out_port.value
        if not value_is_known(raw):
            continue

        if (raw.integer & 0xFF) == expected:
            return

    raise AssertionError(
        f"Timed out waiting for GPIO/out_port value 0x{expected:02X}"
    )


async def wait_for_vga_ctrl_enabled(dut, max_cycles=800_000):
    """
    Wait until core has executed the final MMIO write that enables VGA mode.

    This avoids sampling out_port while it is still in GPIO mode.
    """
    ctrl = find_optional_signal(
        dut,
        [
            'uut.processor.vga_ctrl_reg',
            'processor.vga_ctrl_reg',
        ],
        'VGA control register',
    )

    if ctrl is not None:
        for _ in range(max_cycles):
            await RisingEdge(dut.clk)

            raw = ctrl.value
            if value_is_known(raw) and ((raw.integer & 0x01) != 0):
                dut._log.info(
                    f"VGA mode enabled: vga_ctrl_reg=0x{raw.integer & 0xFF:02X}"
                )
                return

        raise AssertionError("Timed out waiting for VGA_CTRL bit 0 to become 1")

    # Fallback if hierarchy changes.
    await ClockCycles(dut.clk, 180_000)


async def wait_for_pixel_and_sample(
    dut,
    pix_x,
    pix_y,
    active,
    x,
    y,
    max_cycles=1_200_000,
):
    """
    Wait for a specific active pixel coordinate and sample out_port.

    The VGA RGB output in vga_peripheral is registered. Sampling at the exact
    coordinate normally still works for large objects, but this helper returns
    only known values.
    """
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

        if int(active.value) != 1:
            continue

        if int(pix_x.value) != x:
            continue

        if int(pix_y.value) != y:
            continue

        raw = dut.out_port.value
        if value_is_known(raw):
            return raw.integer & 0xFF

    raise AssertionError(f"Timed out waiting for known active pixel ({x}, {y})")


async def capture_visible_frame_ppm(
    dut,
    pix_x,
    pix_y,
    active,
    filename,
    width=640,
    height=480,
    max_cycles=900_000,
):
    frame = bytearray(width * height * 3)
    seen = [[False] * width for _ in range(height)]
    count = 0

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

        if int(active.value) != 1:
            continue

        x = int(pix_x.value)
        y = int(pix_y.value)

        if not (0 <= x < width and 0 <= y < height):
            continue

        raw = dut.out_port.value
        if value_is_known(raw):
            color = color_from_vga_out(raw.integer & 0xFF)
        else:
            color = COLOR_BLACK

        r, g, b = rgb222_to_rgb888(color)

        idx = (y * width + x) * 3
        frame[idx] = r
        frame[idx + 1] = g
        frame[idx + 2] = b

        if not seen[y][x]:
            seen[y][x] = True
            count += 1

            if count >= width * height:
                break

    with open(filename, 'wb') as f:
        f.write(f"P6\n{width} {height}\n255\n".encode('ascii'))
        f.write(frame)

    dut._log.info(f"Captured {count} visible pixels to {filename}")

    assert count > (width * height * 9) // 10, (
        f"Captured too few visible pixels: {count}"
    )


def log_scene(dut, objects):
    dut._log.info("VGA primitive scene:")
    for index, word0, word1, label in objects:
        dut._log.info(
            f"  obj{index:02d}: {label:<38} "
            f"WORD0=0x{word0:08X} WORD1=0x{word1:08X}"
        )


# ============================================================
# Test
# ============================================================

@cocotb.test()
async def test_vga_black_bg_primitive_demo_and_capture(dut):
    """
    Program a black-background primitive scene through MMIO,
    verify overlap/priority at selected pixels, and capture a PPM.
    """

    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())

    # Higher object index has higher priority.
    objects = [
        (
            0,
            pack_rect_word0(80, 100),
            pack_rect_word1(260, 55, COLOR_GREEN),
            "green rectangle",
        ),
        (
            1,
            pack_oct_word0(320, 145, 125),
            pack_oct_word1(COLOR_YELLOW),
            "yellow octagon over green",
        ),
        (
            2,
            pack_oct_word0(420, 315, 90),
            pack_oct_word1(COLOR_RED),
            "red octagon",
        ),
        (
            3,
            pack_line_word0(80, 340, 340),
            pack_line_word1(340, COLOR_WHITE),
            "white horizontal line",
        ),
        (
            4,
            pack_line_word0(205, 260, 205),
            pack_line_word1(435, COLOR_WHITE),
            "white vertical line",
        ),
        (
            5,
            pack_line_word0(520, 65, 520),
            pack_line_word1(410, COLOR_CYAN),
            "cyan vertical line",
        ),
        (
            6,
            pack_rect_word0(430, 360),
            pack_rect_word1(180, 80, COLOR_WHITE),
            "white lower-right rectangle",
        ),
        (
            7,
            pack_line_word0(340, 430, 610),
            pack_line_word1(430, COLOR_RED),
            "red line over white rectangle",
        ),
    ]

    log_scene(dut, objects)

    memory_map = build_firmware_memory_map(objects, bg_color=COLOR_BLACK)

    FakeSPIFlash(dut, memory_map=memory_map)

    if hasattr(dut, 'in_port'):
        dut.in_port.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    await wait_for_gpio_value(dut, 0x15)
    dut._log.info("GPIO mode verified before enabling VGA primitive mode")

    pix_x = find_first_signal(
        dut,
        [
            'uut.processor.vga.pix_x',
            'uut.vga.pix_x',
            'processor.vga.pix_x',
            'vga.pix_x',
        ],
        'VGA pix_x',
    )

    pix_y = find_first_signal(
        dut,
        [
            'uut.processor.vga.pix_y',
            'uut.vga.pix_y',
            'processor.vga.pix_y',
            'vga.pix_y',
        ],
        'VGA pix_y',
    )

    active = find_first_signal(
        dut,
        [
            'uut.processor.vga.display_on',
            'uut.processor.vga.video_active',
            'uut.vga.display_on',
            'uut.vga.video_active',
            'processor.vga.display_on',
            'processor.vga.video_active',
            'vga.display_on',
            'vga.video_active',
        ],
        'VGA active/display_on',
    )

    await wait_for_vga_ctrl_enabled(dut)

    # Give the registered VGA output a small settle window after mode enable.
    await ClockCycles(dut.clk, 40)

    sample_points = [
        (10, 10, COLOR_BLACK, "black background"),
        (100, 120, COLOR_GREEN, "green rectangle-only area"),
        (320, 145, COLOR_YELLOW, "yellow over green overlap / higher priority"),
        (420, 315, COLOR_RED, "red octagon center"),
        (205, 340, COLOR_WHITE, "white line crossing"),
        (520, 180, COLOR_CYAN, "cyan vertical line"),
        (500, 390, COLOR_WHITE, "white lower-right rectangle"),
        (500, 430, COLOR_RED, "red line over white rectangle / higher priority"),
    ]

    for x, y, expected, label in sample_points:
        vga_value = await wait_for_pixel_and_sample(
            dut,
            pix_x,
            pix_y,
            active,
            x,
            y,
        )

        color = color_from_vga_out(vga_value)

        dut._log.info(
            f"{label}: pixel=({x},{y}) "
            f"vga_out=0x{vga_value:02X} color=0x{color:02X}"
        )

        assert color == expected, (
            f"{label}: expected color 0x{expected:02X}, got 0x{color:02X}"
        )

    ppm_name = os.environ.get(
        'VGA_PPM_OUT',
        'vga_primitives_black_demo.ppm',
    )

    await capture_visible_frame_ppm(
        dut,
        pix_x,
        pix_y,
        active,
        ppm_name,
    )

    dut._log.info("SUCCESS: black-background VGA primitive demo rendered and captured.")
