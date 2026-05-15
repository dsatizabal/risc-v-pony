#!/usr/bin/env python3
from pathlib import Path

pattern_block = bytes([
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x3F, 0x00,
    0x15, 0x2A, 0x15, 0x2A, 0x01, 0x03, 0x07, 0x0F,
])

pattern = pattern_block * 4

Path("spi_led_pattern.bin").write_bytes(pattern)
Path("spi_led_pattern.txt").write_text(
    " ".join(f"{b:02X}" for b in pattern) + "\n",
    encoding="utf-8",
)
