#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print("usage: bin_to_hex.py <input.bin> <output.hex>")
    sys.exit(1)

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

data = src.read_bytes()
words = []

for i in range(0, len(data), 4):
    chunk = data[i:i + 4]
    chunk = chunk.ljust(4, b"\x00")
    word = int.from_bytes(chunk, byteorder="little")
    words.append(f"{word:08x}")

dst.write_text("\n".join(words) + "\n", encoding="utf-8")
