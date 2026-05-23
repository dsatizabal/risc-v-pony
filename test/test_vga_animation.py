import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

# ============================================================
# MMIO Addresses & Colors
# ============================================================
MMIO_OUT                = 128
MMIO_VGA_CTRL           = 140
MMIO_GAMEPAD            = 144
MMIO_VGA_OBJ_INDEX      = 148
MMIO_VGA_OBJ_WORD0      = 152
MMIO_VGA_OBJ_WORD1      = 156
MMIO_VGA_BG_COLOR       = 160
MMIO_VGA_OBJ_WORD2      = 164
MMIO_FRAMES_COUNTER     = 168

COLOR_BLACK = 0x00; COLOR_BLUE = 0x03; COLOR_GREEN = 0x0C; COLOR_CYAN = 0x0F
COLOR_RED = 0x30; COLOR_YELLOW  = 0x3C; COLOR_WHITE   = 0x3F

# ============================================================
# RV32E Assembler Helpers
# ============================================================
def i_type(imm, rs1, funct3, rd, opcode=0x13): return (((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))
def s_type(imm, rs2, rs1, funct3=0x2, opcode=0x23): return (((imm >> 5 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F))
def b_type(imm, rs2, rs1, funct3=0x0, opcode=0x63): return ((((imm >> 12) & 0x1) << 31) | (((imm >> 5) & 0x3F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 0x1) << 7) | (opcode & 0x7F))
def r_type(funct7, rs2, rs1, funct3, rd, opcode=0x33): return (((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))

def lui(rd, imm20): return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37
def addi(rd, rs1, imm): return i_type(imm, rs1, 0x0, rd, 0x13)
def andi(rd, rs1, imm): return i_type(imm, rs1, 0x7, rd, 0x13)
def slli(rd, rs1, shamt): return i_type(shamt, rs1, 0x1, rd, 0x13)
def or_(rd, rs1, rs2): return r_type(0, rs2, rs1, 0x6, rd, 0x33)
def lw(rd, offset, rs1): return i_type(offset, rs1, 0x2, rd, 0x03)
def sw(rs2, offset, rs1): return s_type(offset, rs2, rs1, 0x2, 0x23)
def beq(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0x0, 0x63)
def bne(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0x1, 0x63)

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

# Packers
def pack_sprite_word0(enable, color, x, y):
    en_bit = 1 if enable else 0
    return ((en_bit << 31) | ((color & 0x3F) << 25) | ((x & 0x3FF) << 15) | ((y & 0x3FF) << 5)) & 0xFFFFFFFF
def pack_rect_word0(enable, x, y):
    en_bit = 1 if enable else 0
    return ((en_bit << 31) | ((x & 0x3FF) << 15) | ((y & 0x3FF) << 5)) & 0xFFFFFFFF
def pack_rect_word1(width, height, color):
    return (((width & 0x3FF) << 22) | ((height & 0x1FF) << 13) | ((color & 0x3F) << 7)) & 0xFFFFFFFF

def pack_sprite_patterns(rows):
    w1 = (rows[0] << 24) | (rows[1] << 16) | (rows[2] << 8) | rows[3]
    w2 = (rows[4] << 24) | (rows[5] << 16) | (rows[6] << 8) | rows[7]
    return (w1 & 0xFFFFFFFF, w2 & 0xFFFFFFFF)

# ============================================================
# Firmware Generator (Updated for 320x240 Logical Space)
# ============================================================
def build_animation_firmware():
    program = []

    # 1. Setup Static Scene (Floor and Platform)
    emit_store_mmio(program, MMIO_VGA_BG_COLOR, COLOR_BLACK)

    # Rect 4: Floor (Logical Y = 200, Height = 40)
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, 6)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD0, pack_rect_word0(True, 0, 200))
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, pack_rect_word1(320, 40, COLOR_GREEN))

    # Rect 5: Platform (Logical X = 100, Y = 150)
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, 7)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD0, pack_rect_word0(True, 100, 150))
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, pack_rect_word1(60, 10, COLOR_CYAN))

    # 2. Setup Sprite Graphics
    alien_pattern = [0x24, 0x24, 0x7E, 0xDB, 0xFF, 0xBD, 0x81, 0x42]
    alien_w1, alien_w2 = pack_sprite_patterns(alien_pattern)
    emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, 0)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, alien_w1)
    emit_store_mmio(program, MMIO_VGA_OBJ_WORD2, alien_w2)

    # Enable VGA
    emit_store_mmio(program, MMIO_VGA_CTRL, 0x01)

    # 3. Game Loop Initialization
    # Register map:
    # x3 = Player X (starts at 100 to match platform)
    # x4 = Base WORD0 (Enable=1, Color=RED, Y=142) -> We will OR the X pos into this
    # x5 = MMIO_GAMEPAD (144)
    # x6 = MMIO_OBJ_INDEX (148)
    # x7 = MMIO_OBJ_WORD0 (152)
    # x8 = MMIO_FRAMES_COUNTER (168)

    base_word0 = pack_sprite_word0(True, COLOR_RED, 0, 142) # X is 0 here, Y is 142
    program.extend(load_imm(3, 100)) # Start X at 100
    program.extend(load_imm(4, base_word0))
    program.extend(load_imm(5, MMIO_GAMEPAD))
    program.extend(load_imm(6, MMIO_VGA_OBJ_INDEX))
    program.extend(load_imm(7, MMIO_VGA_OBJ_WORD0))
    program.extend(load_imm(8, MMIO_FRAMES_COUNTER))

    loop_start_idx = len(program)

    # --- LOOP ---
    # Update Sprite 0 WORD0
    program.extend([
        slli(9, 3, 15),       # x9 = X << 15
        or_(9, 9, 4),         # x9 = (X << 15) | base_word0
        sw(0, 0, 6),          # sw x0, 0(x6) -> Index = 0
        sw(9, 0, 7),          # sw x9, 0(x7) -> Word0 = new combined word

        # Read Gamepad
        lw(10, 0, 5),         # lw x10, 0(x5) -> read gamepad

        # Check RIGHT button (Bit 8 = 0x100)
        andi(11, 10, 0x100),
        beq(11, 0, 8),        # If 0, skip the addi (jump over it)
        addi(3, 3, 4),        # x3 = x3 + 4 (Move right 4 logical pixels)

        # Wait for VBLANK (poll frame counter until it changes)
        lw(12, 0, 8),         # lw x12, frame_counter
    ])
    wait_loop_idx = len(program)
    program.extend([
        lw(13, 0, 8),         # lw x13, frame_counter
        beq(12, 13, -4),      # If same, jump back to the read
    ])

    # Jump to start of loop
    offset = (loop_start_idx - len(program)) * 4
    program.append(beq(0, 0, offset))

    return {i * 4: inst & 0xFFFFFFFF for i, inst in enumerate(program)}

# ============================================================
# Cocotb Test Logic
# ============================================================
def color_from_vga_out(v):
    r = (((v >> 4) & 1) << 0) | (((v >> 0) & 1) << 1)
    g = (((v >> 5) & 1) << 0) | (((v >> 1) & 1) << 1)
    b = (((v >> 6) & 1) << 0) | (((v >> 2) & 1) << 1)
    return (r << 4) | (g << 2) | b

def rgb222_to_rgb888(color):
    return (((color >> 4) & 0x3) * 85, ((color >> 2) & 0x3) * 85, (color & 0x3) * 85)

async def capture_single_frame(dut, pix_x, pix_y, active, filename, width=640, height=480):
    frame = bytearray(width * height * 3)
    seen = [[False] * width for _ in range(height)]
    count = 0

    dut._log.info(f"Capturing {filename}...")

    # Wait for the start of a new frame (x=0, y=0, active=1)
    while True:
        await RisingEdge(dut.clk)
        if int(active.value) == 1 and int(pix_x.value) == 0 and int(pix_y.value) == 0:
            break

    # Record pixels until frame is done
    while count < width * height:
        await RisingEdge(dut.clk)
        if int(active.value) != 1: continue

        x = int(pix_x.value)
        y = int(pix_y.value)
        if not (0 <= x < width and 0 <= y < height): continue

        raw = dut.out_port.value
        if 'x' in raw.binstr.lower() or 'z' in raw.binstr.lower():
            color = COLOR_BLACK
        else:
            color = color_from_vga_out(raw.integer & 0xFF)

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


async def drive_gamepad_raw(dut, raw_word):
    """Simulates the Gamepad PMOD serial protocol"""
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


def get_signal_by_path(dut, path):
    """Safely traverses the hardware hierarchy to find a signal."""
    obj = dut
    for part in path.split('.'):
        if not hasattr(obj, part):
            return None
        obj = getattr(obj, part)
    return obj

def find_first_signal(dut, candidates, label):
    """Tries a list of possible hierarchical paths and returns the first one that exists."""
    for path in candidates:
        sig = get_signal_by_path(dut, path)
        if sig is not None:
            dut._log.info(f"Using {label} signal path: {path}")
            return sig
    raise AssertionError(f"Could not find {label} - please check your Verilog hierarchy paths.")

@cocotb.test()
async def test_vga_animation_loop(dut):
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())

    memory_map = build_animation_firmware()
    FakeSPIFlash(dut, memory_map=memory_map)

    dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Updated signal paths to match the robust scene test
    pix_x = find_first_signal(dut, [
        'uut.processor.vga.hpos', 'uut.vga.hpos',
        'processor.vga.vga_sync_gen.hpos', 'uut.processor.vga.vga_sync_gen.hpos'
    ], 'VGA pix_x')

    pix_y = find_first_signal(dut, [
        'uut.processor.vga.vpos', 'uut.vga.vpos',
        'processor.vga.vga_sync_gen.vpos', 'uut.processor.vga.vga_sync_gen.vpos'
    ], 'VGA pix_y')

    active = find_first_signal(dut, [
        'uut.processor.vga.display_on', 'uut.vga.display_on',
        'processor.vga.vga_sync_gen.display_on', 'uut.processor.vga.vga_sync_gen.display_on'
    ], 'VGA active')

    # Give CPU time to boot, setup VGA, and enter the main loop
    await ClockCycles(dut.clk, 200_000)

    # Frame 1: Gamepad Idle (Alien stands still)
    await drive_gamepad_raw(dut, 0x000)
    await capture_single_frame(dut, pix_x, pix_y, active, "frame_0.ppm")

    # Frame 2: Hold "RIGHT" (Bit 4 of raw data for the right button)
    await drive_gamepad_raw(dut, (1 << 4))
    await capture_single_frame(dut, pix_x, pix_y, active, "frame_1.ppm")

    # Frame 3: Continue holding "RIGHT"
    await drive_gamepad_raw(dut, (1 << 4))
    await capture_single_frame(dut, pix_x, pix_y, active, "frame_2.ppm")

    dut._log.info("SUCCESS: Animation frames captured! Check frame_0.ppm through frame_2.ppm")
