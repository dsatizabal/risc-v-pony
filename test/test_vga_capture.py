"""
Pony VGA capture/smoke tests.

Drop this file into the Cocotb test directory and add MODULE=test_vga_capture,
or include test_vga_capture in your Makefile MODULE list.

This test intentionally has two levels:
  1) Public-output smoke test: enable VGA mode through MMIO and verify sync activity
     on the normal out_port / uo_out bus.
  2) Optional frame capture: if the VGA peripheral exposes internal active-video
     and pixel-coordinate signals, capture one active frame into a PPM image.

The PPM file is written to ./vga_capture.ppm by default and can be opened by many
image viewers or converted with ImageMagick/GIMP/Pillow.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

from fake_spi import FakeSPIFlash


MMIO_OUT = 128
MMIO_VGA_CTRL = 140

# Tiny VGA PMOD packing used by the Pony VGA peripheral/sample:
#   out[7] = hsync
#   out[6] = B[0]
#   out[5] = G[0]
#   out[4] = R[0]
#   out[3] = vsync
#   out[2] = B[1]
#   out[1] = G[1]
#   out[0] = R[1]

def vga_bits_to_rgb888(v):
    """Decode Tiny VGA PMOD 2-bit-per-channel packed bus into RGB888."""
    r2 = ((v >> 0) & 0x1) << 1 | ((v >> 4) & 0x1)
    g2 = ((v >> 1) & 0x1) << 1 | ((v >> 5) & 0x1)
    b2 = ((v >> 2) & 0x1) << 1 | ((v >> 6) & 0x1)
    # Scale 0..3 to 0..255.
    return (r2 * 85, g2 * 85, b2 * 85)


def safe_integer(signal):
    s = signal.value.binstr.lower()
    if any(ch in s for ch in "xzuw-"):
        return None
    return signal.value.integer


def getattr_path(root, path):
    obj = root
    for part in path.split("."):
        obj = getattr(obj, part)
    return obj


def resolve_first_path(dut, candidates):
    for path in candidates:
        try:
            return path, getattr_path(dut, path)
        except Exception:
            pass
    return None, None


async def wait_for_out_value(dut, expected, max_cycles=50_000):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        v = safe_integer(dut.out_port)
        if v is not None and (v & 0xFF) == expected:
            return
    raise AssertionError(f"Timed out waiting for out_port == 0x{expected:02X}")


async def wait_for_vga_sync_activity(dut, max_cycles=200_000):
    """Verify that hsync/vsync bits on out_port become active after VGA mode."""
    prev = None
    hsync_edges = 0
    vsync_edges = 0
    distinct_values = set()

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        v = safe_integer(dut.out_port)
        if v is None:
            continue

        v &= 0xFF
        distinct_values.add(v)

        hsync = (v >> 7) & 1
        vsync = (v >> 3) & 1

        if prev is not None:
            prev_hsync = (prev >> 7) & 1
            prev_vsync = (prev >> 3) & 1
            if hsync != prev_hsync:
                hsync_edges += 1
            if vsync != prev_vsync:
                vsync_edges += 1

        prev = v

        # VSYNC may be slow depending where we start; HSYNC should toggle quickly.
        if hsync_edges >= 4 and len(distinct_values) >= 4:
            return hsync_edges, vsync_edges, distinct_values

    raise AssertionError(
        f"No convincing VGA activity: hsync_edges={hsync_edges}, "
        f"vsync_edges={vsync_edges}, distinct_values={sorted(distinct_values)[:16]}"
    )


def write_ppm(path, frame):
    height = len(frame)
    width = len(frame[0]) if height else 0
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        for row in frame:
            for r, g, b in row:
                f.write(bytes((r, g, b)))


async def capture_frame_with_internal_coords(dut, out_path="vga_capture.ppm", width=640, height=480,
                                             max_cycles=1_000_000):
    """
    Capture a frame using internal VGA scan coordinates if available.

    This is much more robust than reconstructing timing purely from hsync/vsync.
    Update candidates below if your instance names differ.
    """
    active_path, video_active = resolve_first_path(dut, [
        "uut.processor.vga.video_active",
        "uut.processor.vga.display_on",
        "uut.processor.vga.vga_video_active",
        "uut.processor.vga.vga_sync_gen.display_on",
    ])
    x_path, pix_x = resolve_first_path(dut, [
        "uut.processor.vga.pix_x",
        "uut.processor.vga.hpos",
        "uut.processor.vga.vga_sync_gen.hpos",
    ])
    y_path, pix_y = resolve_first_path(dut, [
        "uut.processor.vga.pix_y",
        "uut.processor.vga.vpos",
        "uut.processor.vga.vga_sync_gen.vpos",
    ])

    if video_active is None or pix_x is None or pix_y is None:
        dut._log.warning(
            "Could not find internal VGA coordinate signals; skipping frame capture. "
            "Set/add candidate paths in capture_frame_with_internal_coords()."
        )
        return False

    dut._log.info(f"Using VGA signals: active={active_path}, x={x_path}, y={y_path}")

    frame = [[(0, 0, 0) for _ in range(width)] for _ in range(height)]
    seen_pixels = 0
    seen_first_pixel = False
    returned_to_origin = False

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

        a = safe_integer(video_active)
        x = safe_integer(pix_x)
        y = safe_integer(pix_y)
        bus = safe_integer(dut.out_port)

        if a is None or x is None or y is None or bus is None:
            continue

        if a and x < width and y < height:
            if x == 0 and y == 0:
                if seen_first_pixel:
                    returned_to_origin = True
                    break
                seen_first_pixel = True

            frame[y][x] = vga_bits_to_rgb888(bus & 0xFF)
            seen_pixels += 1

    if not returned_to_origin and seen_pixels == 0:
        raise AssertionError("Internal VGA signals found, but no active pixels were captured")

    write_ppm(out_path, frame)
    dut._log.info(f"Captured {seen_pixels} active pixel samples to {out_path}")
    return True


@cocotb.test()
async def test_vga_mode_smoke_and_optional_frame_capture(dut):
    """Enable VGA through MMIO, verify sync activity, and optionally capture a frame."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Program:
    #   x1 = MMIO_OUT
    #   x2 = 0x15
    #   sw x2, 0(x1)       ; prove normal GPIO output path
    #   x2 = 0x2A
    #   sw x2, 0(x1)       ; prove normal GPIO output path again
    #   x1 = MMIO_VGA_CTRL
    #   x2 = 1
    #   sw x2, 0(x1)       ; VGA owns out_port
    #   trap forever
    memory_map = {
        0x00000000: 0x08000093,  # ADDI x1, x0, 128
        0x00000004: 0x01500113,  # ADDI x2, x0, 0x15
        0x00000008: 0x0020A023,  # SW   x2, 0(x1)
        0x0000000C: 0x02A00113,  # ADDI x2, x0, 0x2A
        0x00000010: 0x0020A023,  # SW   x2, 0(x1)
        0x00000014: 0x08C00093,  # ADDI x1, x0, 140
        0x00000018: 0x00100113,  # ADDI x2, x0, 1
        0x0000001C: 0x0020A023,  # SW   x2, 0(x1)
        0x00000020: 0x00000063,  # BEQ  x0, x0, 0
    }

    FakeSPIFlash(dut, memory_map=memory_map)

    dut.in_port.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    dut._log.info("Checking normal GPIO/out_port path before VGA mode")
    await wait_for_out_value(dut, 0x15)
    await wait_for_out_value(dut, 0x2A)

    dut._log.info("Waiting for VGA sync/color activity after enabling VGA mode")
    h_edges, v_edges, values = await wait_for_vga_sync_activity(dut)
    dut._log.info(
        f"VGA activity detected: hsync_edges={h_edges}, vsync_edges={v_edges}, "
        f"distinct_output_values={len(values)}"
    )

    capture_path = os.environ.get("VGA_CAPTURE_PATH", "vga_capture.ppm")
    captured = await capture_frame_with_internal_coords(dut, out_path=capture_path)
    if captured:
        dut._log.info(f"Open {capture_path} to inspect the simulated VGA frame")
