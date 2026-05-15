import time
import rp2
from machine import Pin

# ------------------------------------------------------------
# QSPI PMOD pin mapping on TT dev board RP2040
# ------------------------------------------------------------
FLASH_CS = 21
SPI_MOSI = 22   # SD0 / IO0
SPI_MISO = 23   # SD1 / IO1
SPI_SCK  = 24

FLASH_WP   = 25 # SD2 / IO2 / WP#
FLASH_HOLD = 26 # SD3 / IO3 / HOLD#

RAM_A_CS = 27
RAM_B_CS = 28


# ------------------------------------------------------------
# Minimal SPI mode 0 PIO program
# CPOL = 0, CPHA = 0
# Output MOSI while SCK low, sample MISO while SCK high
# ------------------------------------------------------------
@rp2.asm_pio(
    out_shiftdir=rp2.PIO.SHIFT_LEFT,
    in_shiftdir=rp2.PIO.SHIFT_LEFT,
    autopull=True,
    pull_thresh=8,
    autopush=True,
    push_thresh=8,
    sideset_init=(rp2.PIO.OUT_LOW,),
    out_init=rp2.PIO.OUT_LOW
)
def spi_mode0():
    out(pins, 1) .side(0)   # SCK low, drive MOSI
    in_(pins, 1) .side(1)   # SCK high, sample MISO


class PIOSPI:
    def __init__(self, sm_id, pin_mosi, pin_miso, pin_sck, freq=1_000_000):
        self.sm = rp2.StateMachine(
            sm_id,
            spi_mode0,
            freq=2 * freq,
            sideset_base=Pin(pin_sck),
            out_base=Pin(pin_mosi),
            in_base=Pin(pin_miso)
        )
        self.sm.active(1)

    def write_read(self, tx):
        rx = bytearray(len(tx))

        # Pipeline behavior:
        # after putting byte N, previous received byte becomes available.
        for i, b in enumerate(tx):
            self.sm.put(b, 24)
            if i > 0:
                rx[i - 1] = self.sm.get()

        rx[-1] = self.sm.get()
        return rx

    def deinit(self):
        self.sm.active(0)


def hex_dump(data):
    print(" ".join("{:02X}".format(b) for b in data))


def read_flash_4_bytes(addr=0x000000):
    # Chip selects are active-low.
    flash_cs = Pin(FLASH_CS, Pin.OUT, value=1)
    ram_a_cs = Pin(RAM_A_CS, Pin.OUT, value=1)
    ram_b_cs = Pin(RAM_B_CS, Pin.OUT, value=1)

    # For single-bit SPI, WP# and HOLD# must be high.
    # These are IO2/IO3 in QSPI mode, but in normal SPI they act as WP#/HOLD#.
    flash_wp = Pin(FLASH_WP, Pin.IN, Pin.PULL_UP)
    flash_hold = Pin(FLASH_HOLD, Pin.IN, Pin.PULL_UP)

    spi = PIOSPI(
        sm_id=1,
        pin_mosi=SPI_MOSI,
        pin_miso=SPI_MISO,
        pin_sck=SPI_SCK,
        freq=1_000_000
    )

    # READ command 0x03 + 24-bit address + 4 dummy bytes to clock out data
    tx = bytearray([
        0x03,
        (addr >> 16) & 0xFF,
        (addr >> 8) & 0xFF,
        addr & 0xFF,
        0x00,
        0x00,
        0x00,
        0x00
    ])

    flash_cs.value(0)
    rx = spi.write_read(tx)
    flash_cs.value(1)

    spi.deinit()

    # rx[0:4] are garbage/command-phase response.
    # rx[4:8] are the actual Flash data bytes.
    data = rx[4:8]

    print("SPI READ 0x03 from address 0x{:06X}".format(addr))
    print("RX full:")
    hex_dump(rx)
    print("Data bytes:")
    hex_dump(data)

    return data


def read_flash_id():
    flash_cs = Pin(FLASH_CS, Pin.OUT, value=1)
    ram_a_cs = Pin(RAM_A_CS, Pin.OUT, value=1)
    ram_b_cs = Pin(RAM_B_CS, Pin.OUT, value=1)

    flash_wp = Pin(FLASH_WP, Pin.IN, Pin.PULL_UP)
    flash_hold = Pin(FLASH_HOLD, Pin.IN, Pin.PULL_UP)

    spi = PIOSPI(
        sm_id=1,
        pin_mosi=SPI_MOSI,
        pin_miso=SPI_MISO,
        pin_sck=SPI_SCK,
        freq=1_000_000
    )

    # 0x9F = JEDEC ID. Usually returns EF 40 18 or similar for W25Q128.
    tx = bytearray([0x9F, 0x00, 0x00, 0x00])

    flash_cs.value(0)
    rx = spi.write_read(tx)
    flash_cs.value(1)

    spi.deinit()

    print("JEDEC ID:")
    hex_dump(rx[1:4])

    return rx[1:4]


# ------------------------------------------------------------
# Run quick checks
# ------------------------------------------------------------
read_flash_id()
read_flash_4_bytes(0x000000)
