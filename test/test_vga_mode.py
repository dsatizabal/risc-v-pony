import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from fake_spi import FakeSPIFlash


MMIO_OUT = 128
MMIO_VGA_CTRL = 140


def _out_sig(dut):
    """Support both tb.v styles: direct out_port or TT-style uo_out."""
    try:
        return dut.out_port
    except AttributeError:
        return dut.uo_out


def _safe_int(value):
    s = value.binstr.lower()
    if any(ch in s for ch in ("x", "z", "u", "w", "-")):
        return None
    return value.integer


async def wait_for_out_value(dut, expected, max_cycles=100_000):
    sig = _out_sig(dut)
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        value = _safe_int(sig.value)
        if value is None:
            continue
        value &= 0xFF
        if value == expected:
            dut._log.info(f"Observed output 0x{expected:02X} after {cycle} cycles")
            return
    raise AssertionError(f"Timed out waiting for output 0x{expected:02X}")


async def collect_vga_samples_after_gpio(dut, previous_gpio_value, min_cycles=3_000, max_cycles=300_000):
    """
    After firmware enables VGA mode, out_port should stop being a stable GPIO byte
    and should become the VGA PMOD bus:

        bit 7 = hsync
        bit 6 = B[0]
        bit 5 = G[0]
        bit 4 = R[0]
        bit 3 = vsync
        bit 2 = B[1]
        bit 1 = G[1]
        bit 0 = R[1]

    We do not require a real monitor here. We only require that hsync toggles and
    that the output is no longer just the previous GPIO pattern.
    """
    sig = _out_sig(dut)
    samples = []
    hsync_values = set()
    vsync_values = set()

    started = False

    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        value = _safe_int(sig.value)
        if value is None:
            continue

        value &= 0xFF

        # VGA mode may initially produce the same byte by coincidence. Start
        # sampling once it differs, but also start eventually so we don't wait
        # forever on a coincidence.
        if not started:
            if value != previous_gpio_value or cycle > 20_000:
                started = True
                dut._log.info(
                    f"VGA sampling started at cycle {cycle}, first output=0x{value:02X}"
                )
            else:
                continue

        samples.append(value)
        hsync_values.add((value >> 7) & 1)
        vsync_values.add((value >> 3) & 1)

        if len(samples) >= min_cycles and len(hsync_values) >= 2:
            dut._log.info(
                f"VGA output active: hsync toggled, unique samples={len(set(samples))}, "
                f"vsync_values={sorted(vsync_values)}"
            )
            return samples

    raise AssertionError(
        "Timed out waiting for VGA hsync activity. "
        f"samples={len(samples)}, unique={len(set(samples)) if samples else 0}, "
        f"hsync_values={sorted(hsync_values)}, vsync_values={sorted(vsync_values)}"
    )


@cocotb.test()
async def test_vga_mode_mux_from_cpu(dut):
    """
    Test Pony VGA mode selection through MMIO.

    Firmware behavior:
      1. Write 0x15 to MMIO_OUT 0x80. Verify normal GPIO/output mode.
      2. Write 0x2A to MMIO_OUT 0x80. Verify normal GPIO/output mode again.
      3. Write 1 to VGA_CTRL 0x8C. This should mux out_port to the VGA PMOD bus.
      4. Trap forever while VGA remains enabled.

    Test expectation:
      - Before VGA mode, out_port follows software GPIO writes.
      - After VGA mode, out_port shows VGA activity, especially hsync toggling.
    """

    memory_map = {
        0x00000000: 0x08000093,  # ADDI x1, x0, 128      ; MMIO_OUT
        0x00000004: 0x01500113,  # ADDI x2, x0, 0x15
        0x00000008: 0x0020A023,  # SW   x2, 0(x1)        ; out = 0x15
        0x0000000C: 0x02A00113,  # ADDI x2, x0, 0x2A
        0x00000010: 0x0020A023,  # SW   x2, 0(x1)        ; out = 0x2A
        0x00000014: 0x08C00193,  # ADDI x3, x0, 140      ; VGA_CTRL
        0x00000018: 0x00100113,  # ADDI x2, x0, 1
        0x0000001C: 0x0021A023,  # SW   x2, 0(x3)        ; enable VGA output mux
        0x00000020: 0x00000063,  # BEQ  x0, x0, 0        ; trap forever
    }

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    FakeSPIFlash(dut, memory_map=memory_map)

    try:
        dut.in_port.value = 0
    except AttributeError:
        # Some TT-style benches expose ui_in instead.
        dut.ui_in.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    dut._log.info("Checking normal GPIO output before VGA mode")
    await wait_for_out_value(dut, 0x15, max_cycles=80_000)
    await wait_for_out_value(dut, 0x2A, max_cycles=80_000)

    dut._log.info("Checking VGA output after writing MMIO_VGA_CTRL=1")
    samples = await collect_vga_samples_after_gpio(
        dut,
        previous_gpio_value=0x2A,
        min_cycles=3_000,
        max_cycles=300_000,
    )

    assert len(set(samples)) >= 2, "VGA output did not vary after enabling VGA mode"

    dut._log.info("SUCCESS: MMIO-controlled VGA mux produced active VGA output.")
