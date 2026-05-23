# RiscV Pony VGA Video Engine

## 1. System Overview
This video engine is a custom-built, hardware-accelerated 2D graphics compositor designed for a bare-metal RV32E RISC-V architecture. It outputs a 60 Hz VGA signal using highly optimized memory-mapped I/O (MMIO), allowing the CPU to manipulate screen objects with minimal overhead.

* **Physical Output:** 640x480 at 60 Hz
* **Logical Resolution:** 320x240 (Hardware pixel-doubling applied)
* **Color Depth:** 6-bit RGB (64 colors)
* **Hardware Capacity:** 10 independent rendering engines (4 Sprites, 4 Rectangles, 2 Lines)

---

## 2. Memory Map (MMIO)
Control the VGA peripheral by writing to these fixed memory addresses.

| Address | Register Name | Description |
| :--- | :--- | :--- |
| `140` | `MMIO_VGA_CTRL` | Write `1` to enable the monitor, `0` to disable. |
| `148` | `MMIO_VGA_OBJ_INDEX` | Selects which object (0-9) you are configuring. |
| `152` | `MMIO_VGA_OBJ_WORD0` | Base configuration (Enable, X, Y) for the selected object. |
| `156` | `MMIO_VGA_OBJ_WORD1` | Extended config (Graphics, Width, Length) for the selected object. |
| `160` | `MMIO_VGA_BG_COLOR` | 6-bit background color. |
| `164` | `MMIO_VGA_OBJ_WORD2` | Additional graphics (Sprites only) for the selected object. |
| `168` | `MMIO_FRAMES_COUNTER` | Read-only. Increments every VBLANK (60 times per second). |
| `172` | `MMIO_LINE_COUNTER` | Read-only. The current logical Y scanline (0-240). |

---

## 3. Color Palette Format
Colors are passed as a 6-bit binary value: `RRGGBB`.
When shifting into a configuration word, calculate the integer value of the binary string.

| Binary (`RRGGBB`) | Hex Value | Color Result |
| :--- | :--- | :--- |
| `000000` | `0x00` | Black |
| `111111` | `0x3F` | White |
| `110000` | `0x30` | Pure Red |
| `001100` | `0x0C` | Pure Green |
| `000011` | `0x03` | Pure Blue |
| `111100` | `0x3C` | Yellow |

---

## 4. Hardware Objects API

To modify any object on the screen, you must first write its ID (0-9) to `MMIO_VGA_OBJ_INDEX`. After that, writes to `WORD0`, `WORD1`, and `WORD2` will apply to that specific object.

### Sprites (Indices 0 - 3)
Sprites are 8x8 pixel grids capable of independent X and Y scaling.

* **WORD0 (Configuration):**
  * **Bit 31:** Enable (1 = On, 0 = Off)
  * **Bits 30:25:** 6-bit Color
  * **Bits 24:15:** X Coordinate (0-319)
  * **Bits 14:5:** Y Coordinate (0-239)
  * **Bits 3:2:** Y-Scale (`00`=1x, `01`=2x, `10`=4x, `11`=8x)
  * **Bits 1:0:** X-Scale (`00`=1x, `01`=2x, `10`=4x, `11`=8x)
* **WORD1 (Top Graphics):** 32 bits representing the top 4 rows of the sprite (8 bits per row).
* **WORD2 (Bottom Graphics):** 32 bits representing the bottom 4 rows of the sprite.

### Rectangles (Indices 4 - 7)
Rectangles are solid blocks of color, highly efficient for UI, walls, and axis-aligned lines.

* **WORD0 (Configuration):**
  * **Bit 31:** Enable (1 = On, 0 = Off)
  * **Bits 24:15:** X Coordinate (0-319)
  * **Bits 14:5:** Y Coordinate (0-239)
* **WORD1 (Dimensions & Color):**
  * **Bits 31:22:** Width (0-319)
  * **Bits 21:13:** Height (0-239)
  * **Bits 12:7:** 6-bit Color

### Lines (Indices 8 - 9)
Lines are hardware-drawn at strict 45-degree angles.

* **WORD0 (Configuration):**
  * **Bit 31:** Enable (1 = On, 0 = Off)
  * **Bits 24:15:** Starting X Coordinate (0-319)
  * **Bits 14:5:** Starting Y Coordinate (0-239)
* **WORD1 (Length & Direction):**
  * **Bits 31:22:** Length in pixels
  * **Bit 21:** Direction (`0` = Right/Down `\`, `1` = Left/Down `/`)
  * **Bits 12:7:** 6-bit Color

---

## 5. Developer Advanced Techniques

* **VBLANK Synchronization:** Always wrap your main game logic in a loop that checks `MMIO_FRAMES_COUNTER`. Updating positions while this counter is stable ensures you do not draw torn frames.
* **Racing the Beam (Vertical Multiplexing):** You can draw more than 10 objects by tracking `MMIO_LINE_COUNTER`. Draw an object at Y=20, wait for the beam to reach Line 50, and instantly overwrite the same object engine to draw it again at Y=80.
* **Time-Division Multiplexing (Flickering):** If you need two objects on the exact same horizontal scanline but lack the hardware engines, draw one on Even frames and the other on Odd frames. At 60 Hz, the human eye will blend the 30 Hz flicker.
* **Axis-Aligned Bounding Box (AABB) Collision:** Because the hardware lacks a collision matrix to save silicon area, perform all hit-detection in software during the VBLANK period using simple `<` and `>` coordinate comparisons.
