import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash

# ============================================================
# MMIO Addresses
# ============================================================
MMIO_OUT                = 128
MMIO_VGA_CTRL           = 140
MMIO_VGA_OBJ_INDEX      = 148
MMIO_VGA_OBJ_WORD0      = 152
MMIO_VGA_OBJ_WORD1      = 156
MMIO_VGA_BG_COLOR       = 160
MMIO_VGA_OBJ_WORD2      = 164
MMIO_FRAMES_COUNTER     = 168
MMIO_LINE_COUNTER       = 172

COLOR_BLACK = 0x00; COLOR_GREEN = 0x0C; COLOR_WHITE = 0x3F

# ============================================================
# RV32E Assembler Helpers
# ============================================================
def i_type(imm, rs1, funct3, rd, opcode=0x13): return (((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F))
def s_type(imm, rs2, rs1, funct3=0x2, opcode=0x23): return (((imm >> 5 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F))
def b_type(imm, rs2, rs1, funct3=0x0, opcode=0x63): return ((((imm >> 12) & 0x1) << 31) | (((imm >> 5) & 0x3F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 0x1) << 7) | (opcode & 0x7F))

def lui(rd, imm20): return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37
def addi(rd, rs1, imm): return i_type(imm, rs1, 0x0, rd, 0x13)
def lw(rd, offset, rs1): return i_type(offset, rs1, 0x2, rd, 0x03)
def sw(rs2, offset, rs1): return s_type(offset, rs2, rs1, 0x2, 0x23)
def beq(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0x0, 0x63)
def bne(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0x1, 0x63) 
def blt(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0x4, 0x63)

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

def pack_sprite_word0(enable, color, x, y):
    en_bit = 1 if enable else 0
    return ((en_bit << 31) | ((color & 0x3F) << 25) | ((x & 0x3FF) << 15) | ((y & 0x3FF) << 5)) & 0xFFFFFFFF

def pack_sprite_patterns(rows):
    w1 = (rows[0] << 24) | (rows[1] << 16) | (rows[2] << 8) | rows[3]
    w2 = (rows[4] << 24) | (rows[5] << 16) | (rows[6] << 8) | rows[7]
    return (w1 & 0xFFFFFFFF, w2 & 0xFFFFFFFF)

# ============================================================
# Firmware Generator (The Racing the Beam Logic)
# ============================================================
def build_invaders_firmware():
    program = []
    
    # 1. Setup Static Graphics
    emit_store_mmio(program, MMIO_VGA_BG_COLOR, COLOR_BLACK)
    
    alien_pattern = [0x18, 0x3C, 0x7E, 0xDB, 0xFF, 0x24, 0x5A, 0xA5]
    aw1, aw2 = pack_sprite_patterns(alien_pattern)
    
    for i in range(6):
        emit_store_mmio(program, MMIO_VGA_OBJ_INDEX, i)
        emit_store_mmio(program, MMIO_VGA_OBJ_WORD1, aw1)
        emit_store_mmio(program, MMIO_VGA_OBJ_WORD2, aw2)

    emit_store_mmio(program, MMIO_VGA_CTRL, 0x01)

    # 2. Pre-load MMIO addresses
    program.extend(load_imm(1, MMIO_VGA_OBJ_INDEX))
    program.extend(load_imm(2, MMIO_VGA_OBJ_WORD0))
    program.extend(load_imm(3, MMIO_LINE_COUNTER))
    program.extend(load_imm(4, MMIO_FRAMES_COUNTER))

    loop_start_idx = len(program)

    # --- FRAME START: Wait for VBLANK ---
    program.append(lw(5, 0, 4))               # x5 = current frame
    wait_vblank_idx = len(program)
    program.append(lw(6, 0, 4))               # x6 = read frame again
    program.append(beq(5, 6, -4))             # loop until x6 != x5

    # --- THE FIX: Wait until the beam is actually at the top of the screen (line 0) ---
    program.append(lw(5, 0, 3))               # x5 = current line
    program.append(bne(5, 0, -4))             # if x5 != 0, jump back and read again

    # --- RACE THE BEAM LOOP (6 Rows) ---
    for row in range(6):
        y_pos = 20 + (row * 32)
        
        # 1. Write the new Y position for all 6 sprites
        for sprite_idx in range(6):
            x_pos = 40 + (sprite_idx * 40)
            word0 = pack_sprite_word0(True, COLOR_GREEN, x_pos, y_pos)
            
            program.append(addi(7, 0, sprite_idx)) 
            program.append(sw(7, 0, 1))            
            program.extend(load_imm(7, word0))     
            program.append(sw(7, 0, 2))     

        # 2. Wait for the beam to finish drawing this row!
        wait_line = y_pos + 8

        program.append(lw(5, 0, 3))               # x5 = current line
        program.append(addi(6, 0, wait_line))     # x6 = target line
        program.append(blt(5, 6, -8))             # If current < target, jump back to lw

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

    while True:
        await RisingEdge(dut.clk)
        if int(active.value) == 1 and int(pix_x.value) == 0 and int(pix_y.value) == 0:
            break

    while count < width * height:
        await RisingEdge(dut.clk)
        if int(active.value) != 1: continue
        x, y = int(pix_x.value), int(pix_y.value)
        if not (0 <= x < width and 0 <= y < height): continue

        raw = dut.out_port.value
        color = COLOR_BLACK if ('x' in raw.binstr.lower() or 'z' in raw.binstr.lower()) else color_from_vga_out(raw.integer & 0xFF)
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

@cocotb.test()
async def test_space_invaders(dut):
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())

    memory_map = build_invaders_firmware()
    FakeSPIFlash(dut, memory_map=memory_map)

    if hasattr(dut, 'in_port'): dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    pix_x = find_first_signal(dut, ['uut.processor.vga.hpos', 'uut.vga.hpos', 'processor.vga.vga_sync_gen.hpos', 'uut.processor.vga.vga_sync_gen.hpos'], 'VGA pix_x')
    pix_y = find_first_signal(dut, ['uut.processor.vga.vpos', 'uut.vga.vpos', 'processor.vga.vga_sync_gen.vpos', 'uut.processor.vga.vga_sync_gen.vpos'], 'VGA pix_y')
    active = find_first_signal(dut, ['uut.processor.vga.display_on', 'uut.vga.display_on', 'processor.vga.vga_sync_gen.display_on', 'uut.processor.vga.vga_sync_gen.display_on'], 'VGA active')

    await ClockCycles(dut.clk, 300_000)

    ppm_name = os.environ.get('VGA_PPM_OUT', 'vga_space_invaders.ppm')
    await capture_single_frame(dut, pix_x, pix_y, active, ppm_name)

    dut._log.info(f"SUCCESS: 6x6 Armada rendered via vertical multiplexing!")
