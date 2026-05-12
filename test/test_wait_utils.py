from cocotb.triggers import RisingEdge


async def wait_for_captured_count(dut, captured, expected_count, max_cycles=50000, label="MMIO writes"):
    """
    Wait until a monitor-populated list has at least expected_count entries.

    This is intentionally better than fixed short ClockCycles() waits now that
    Pony fetches instructions through a realistic SPI mode-0 transaction.
    """
    for _ in range(max_cycles):
        if len(captured) >= expected_count:
            return
        await RisingEdge(dut.clk)

    raise AssertionError(
        f"Timed out waiting for {expected_count} {label}; "
        f"got {len(captured)}: {captured}"
    )


async def wait_until_signal_value(dut, signal, expected, max_cycles=50000, label="signal"):
    """
    Wait until a cocotb signal becomes expected, ignoring X/Z/U values.
    """
    for _ in range(max_cycles):
        raw = signal.value
        if 'x' not in raw.binstr.lower() and 'z' not in raw.binstr.lower() and 'u' not in raw.binstr.lower():
            if raw.integer == expected:
                return
        await RisingEdge(dut.clk)

    raw = signal.value
    raise AssertionError(
        f"Timed out waiting for {label} == {expected}; final value was {raw}"
    )
