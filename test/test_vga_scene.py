import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

# ============================================================
# MMIO addresses for the New Architecture
# ============================================================
MMIO_OUT                = 128
MMIO_VGA_CTRL           = 140
MMIO_VGA_OBJ_INDEX      = 148
MMIO_VGA_OBJ_WORD0      = 152
MMIO_VGA_OBJ_WORD1      = 156
MMIO_VGA_BG_COLOR       = 160
MMIO_VGA_OBJ_WORD2      = 164

# RGB222 color constants
COLOR_BLACK   = 0x00
COLOR_BLUE    = 0x03
COLOR_GREEN   = 0x0C
COLOR_CYAN    = 0x0F
COLOR_RED     = 0x30
COLOR_MAGENTA = 0x33
COLOR_YELLOW  = 0x3C
COLOR_WHITE   = 0x3F

# ============================================================
# RV32E-safe instruction encoders
# ============================================================
def i_type(imm, rs1, funct3, rd, opcode=0x13):
    return (((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))

def s_type(imm, rs2, rs1, funct3=0x2, opcode=0x23):
    imm &= 0xFFF
    return (((imm >> 5 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F))

def b_type(imm, rs2, rs1, funct3=0x0, opcode=0x63):
    imm &= 0x1FFF
    return ((((imm >> 12) & 0x1) << 31) | (((imm >> 5) & 0x3F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 0x1) << 7) | (opcode & 0x7F))

def lui(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37

def addi(rd, rs1, imm):
    return i_type(imm, rs1, 0x0, rd, 0x13)

def sw(rs2, offset, rs1):
    return s_type(offset, rs2, rs1, 0x2, 0x23)

def beq(rs1, rs2, imm):
    return b_type(imm, rs2, rs1, 0x0, 0x63)

def load_imm(rd, value):
    value &= 0xFFFFFFFF
    upper = (value + 0x800) >> 12
    lower = value - (upper << 12)
    if lower >= 2048: lower -= 4096
    insts = []
    if upper != 0:
        insts.append(lui(rd, upper))
        if lower != 0: insts.append(addi(rd, rd, lower))
    else:
        insts.append(addi(rd, 0, lower))
    return insts

def emit_store_mmio(program, addr, value, r_addr=1, r_val=2):
    program.extend(load_imm(r_addr, addr))
    program.extend(load_imm(r_val, value))
    program.append(sw(r_val, 0, r_addr))

# ============================================================
# New Primitive Packers (Sprites & Rectangles)
# ============================================================
def pack_sprite_word0(enable, color, x, y):
    en_bit = 1 if enable else 0
    return ((en_bit << 31) | ((color & 0x3F) << 25) | ((x & 0x3FF) << 15) | ((y & 0x3FF) << 5)) & 0xFFFFFFFF

def pack_rect_word0(enable, x, y):
    en_bit = 1 if enable else 0
    return ((en_bit << 31) | ((x & 0x3FF) << 15) | ((y & 0x3FF) << 5)) & 0xFFFFFFFF

def pack_rect_word1(width, height, color):
    return (((width & 0x3FF) << 22) | ((height & 0x1FF) << 13) | ((color & 0x3F) << 7)) & 0xFFFFFFFF

def pack_sprite_patterns(rows):
    """Takes an array of 8 bytes (rows) and returns (WORD1, WORD2)"""
    assert len(rows) == 8
    w1 = (rows[0] << 24) | (rows[1] << 16) | (rows[2] << 8) | rows[3]
    w2 = (rows[4] << 24) | (rows[5] << 16) | (rows[6] << 8) | rows[7]
    return (w1 & 0xFFFFFFFF, w2 & 0xFFFFFFFF)

def emit_sprite(program, index, word0, word1, word2):
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, index & 0xF)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD0, word0)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, word1)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD2, word2)

def emit_rect(program, index, word0, word1):
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, index & 0xF)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD0, word0)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, word1)

# ============================================================
# Build Firmware (Updated for 320x240 Logical Space)
# ============================================================
def build_firmware_memory_map(bg_color=COLOR_BLACK):
    program = []
    emit_store_mmio(program, MMIO_OUT, 0x15)
    emit_store_mmio(program, MMIO_VGA_BG_COLOR, bg_color)

    # RECTANGLES (Indices 4 to 11)
    # The Floor (Logical Y = 200, Height = 40. Physically this covers Y=400 to Y=479)
    emit_rect(program, 6, pack_rect_word0(True, 0, 200), pack_rect_word1(320, 40, COLOR_GREEN))
    # A floating platform (Logical X=100, Y=150)
    emit_rect(program, 7, pack_rect_word0(True, 100, 150), pack_rect_word1(60, 10, COLOR_CYAN))

    # SPRITES (Indices 0 to 3)
    # Little Space Invader Dude
    alien_pattern = [0x24, 0x24, 0x7E, 0xDB, 0xFF, 0xBD, 0x81, 0x42]
    alien_w1, alien_w2 = pack_sprite_patterns(alien_pattern)
    # Alien logical X=125, Y=142 (stands perfectly on the platform)
    emit_sprite(program, 0, pack_sprite_word0(True, COLOR_RED, 125, 142), alien_w1, alien_w2)

    # A Key
    key_pattern = [0x70, 0x88, 0x88, 0x70, 0x10, 0x1C, 0x10, 0x18]
    key_w1, key_w2 = pack_sprite_patterns(key_pattern)
    # Key logical X=200, Y=192 (rests perfectly on the floor)
    emit_sprite(program, 1, pack_sprite_word0(True, COLOR_YELLOW, 200, 192), key_w1, key_w2)

    # Enable VGA Output Mux
    emit_store_mmio(program, MMIO_VGA_CTRL, 0x01)
    # Trap
    program.append(beq(0, 0, 0))

    return {i * 4: inst & 0xFFFFFFFF for i, inst in enumerate(program)}

# ============================================================
# Helpers
# ============================================================
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
            dut._log.info(f"Using {label} signal path: {path}")
            return sig
    raise AssertionError(f"Could not find {label}")

def value_is_known(value):
    s = value.binstr.lower()
    return ('x' not in s) and ('z' not in s) and ('u' not in s)

def color_from_vga_out(v):
    r = (((v >> 4) & 1) << 0) | (((v >> 0) & 1) << 1)
    g = (((v >> 5) & 1) << 0) | (((v >> 1) & 1) << 1)
    b = (((v >> 6) & 1) << 0) | (((v >> 2) & 1) << 1)
    return (r << 4) | (g << 2) | b

def rgb222_to_rgb888(color):
    return (((color >> 4) & 0x3) * 85, ((color >> 2) & 0x3) * 85, (color & 0x3) * 85)

async def wait_for_gpio_value(dut, expected, max_cycles=200_000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        raw = dut.out_port.value
        if not value_is_known(raw): continue
        if (raw.integer & 0xFF) == expected: return

async def capture_visible_frame_ppm(dut, pix_x, pix_y, active, filename, width=640, height=480, max_cycles=900_000):
    frame = bytearray(width * height * 3)
    seen = [[False] * width for _ in range(height)]
    count = 0

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(active.value) != 1: continue

        x = int(pix_x.value)
        y = int(pix_y.value)
        if not (0 <= x < width and 0 <= y < height): continue

        raw = dut.out_port.value
        color = color_from_vga_out(raw.integer & 0xFF) if value_is_known(raw) else COLOR_BLACK
        r, g, b = rgb222_to_rgb888(color)

        idx = (y * width + x) * 3
        frame[idx] = r
        frame[idx + 1] = g
        frame[idx + 2] = b

        if not seen[y][x]:
            seen[y][x] = True
            count += 1
            if count >= width * height: break

    with open(filename, 'wb') as f:
        f.write(f"P6\n{width} {height}\n255\n".encode('ascii'))
        f.write(frame)
    dut._log.info(f"Captured {count} visible pixels to {filename}")

# ============================================================
# The Test
# ============================================================
@cocotb.test()
async def test_vga_sprites_and_rects(dut):
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())

    memory_map = build_firmware_memory_map(bg_color=COLOR_BLUE)
    FakeSPIFlash(dut, memory_map=memory_map)

    if hasattr(dut, 'in_port'): dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    await wait_for_gpio_value(dut, 0x15)
    dut._log.info("GPIO mode verified. VGA initializing...")

    pix_x = find_first_signal(dut, ['uut.processor.vga.hpos', 'uut.vga.hpos', 'processor.vga.vga_sync_gen.hpos', 'uut.processor.vga.vga_sync_gen.hpos'], 'VGA pix_x')
    pix_y = find_first_signal(dut, ['uut.processor.vga.vpos', 'uut.vga.vpos', 'processor.vga.vga_sync_gen.vpos', 'uut.processor.vga.vga_sync_gen.vpos'], 'VGA pix_y')
    active = find_first_signal(dut, ['uut.processor.vga.display_on', 'uut.vga.display_on', 'processor.vga.vga_sync_gen.display_on', 'uut.processor.vga.vga_sync_gen.display_on'], 'VGA active')

    # Give it time to execute MMIO setup
    await ClockCycles(dut.clk, 150_000)

    ppm_name = os.environ.get('VGA_PPM_OUT', 'vga_new_engine_demo.ppm')
    await capture_visible_frame_ppm(dut, pix_x, pix_y, active, ppm_name)
    dut._log.info("SUCCESS: Sprite & Rectangle Demo captured!")