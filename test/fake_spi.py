import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, First


class FakeSPIFlash:
    """
    Realistic single-bit SPI Flash model for Pony.

    Supports:
      - READ 0x03
      - 24-bit byte address
      - 4 returned bytes per transaction

    SPI mode 0:
      - SCK idle low
      - Master drives MOSI while SCK is low
      - Flash samples MOSI on SCK rising edge
      - Flash updates MISO after SCK falling edge
      - Master samples MISO on SCK rising edge

    Existing Pony tests may still pass memory_map as 32-bit instruction words.
    Internally, this model stores bytes like a real little-endian firmware image.
    """

    def __init__(self, dut, memory_map=None, bin_file=None):
        self.dut = dut
        self.memory = {}
        self.dut.spi_miso.value = 0

        if memory_map is not None:
            self._load_word_map(memory_map)

        if bin_file:
            dut._log.info(f"Loading firmware from disk: {bin_file}")
            with open(bin_file, "rb") as f:
                self._load_bytes(f.read())

        cocotb.start_soon(self._run())

    def _load_word_map(self, memory_map):
        """
        Existing Pony tests pass a memory_map in this form:

            {
                0x00000000: 0x08000093,
                0x00000004: 0x00100113,
            }

        Real SPI Flash is byte-addressed.

        A RISC-V instruction word 0x08000093 is stored in firmware as:

            93 00 00 08
        """
        for address, word in memory_map.items():
            word &= 0xFFFFFFFF
            for offset, byte in enumerate(word.to_bytes(4, byteorder="little")):
                self.memory[address + offset] = byte

    def _load_bytes(self, data):
        """
        Load a normal firmware.bin image exactly as real SPI Flash would contain it.
        """
        for address, byte in enumerate(data):
            self.memory[address] = byte

    def _read_byte(self, address):
        if address in self.memory:
            return self.memory[address]

        # Default unmapped instruction is NOP: 0x00000013.
        # Little-endian byte order: 13 00 00 00.
        nop_bytes = [0x13, 0x00, 0x00, 0x00]
        return nop_bytes[address & 0x3]

    @staticmethod
    def _safe_bit(value):
        s = str(value).lower()
        if s in ("x", "z", "u", "w", "-"):
            return 0
        return int(value)

    async def _wait_sck_rising_while_selected(self):
        """
        Wait for either SCK rising or CS rising.

        Returns:
          True  -> got SCK rising while CS was still low
          False -> CS rose first, transaction aborted
        """
        result = await First(
            RisingEdge(self.dut.spi_sck),
            RisingEdge(self.dut.spi_cs_n)
        )

        if self.dut.spi_cs_n.value == 1:
            return False

        return True

    async def _wait_sck_falling_while_selected(self):
        """
        Wait for either SCK falling or CS rising.

        Returns:
          True  -> got SCK falling while CS was still low
          False -> CS rose first, transaction aborted
        """
        result = await First(
            FallingEdge(self.dut.spi_sck),
            RisingEdge(self.dut.spi_cs_n)
        )

        if self.dut.spi_cs_n.value == 1:
            return False

        return True

    async def _read_mosi_bit(self):
        ok = await self._wait_sck_rising_while_selected()
        if not ok:
            return None

        return self._safe_bit(self.dut.spi_mosi.value)

    async def _run(self):
        while True:
            # Wait for Flash select.
            await FallingEdge(self.dut.spi_cs_n)
            self.dut.spi_miso.value = 0

            shift_in = 0
            aborted = False

            # Receive command + 24-bit address.
            # Flash samples MOSI on SCK rising edge in SPI mode 0.
            for _ in range(32):
                bit = await self._read_mosi_bit()

                if bit is None:
                    aborted = True
                    break

                shift_in = (shift_in << 1) | bit

            if aborted:
                self.dut.spi_miso.value = 0
                continue

            command = (shift_in >> 24) & 0xFF
            address = shift_in & 0xFFFFFF

            if command != 0x03:
                self.dut._log.warning(
                    f"Unexpected SPI flash command 0x{command:02X}, address 0x{address:06X}"
                )

                # Keep the model sane: wait until CS is released, then idle.
                await RisingEdge(self.dut.spi_cs_n)
                self.dut.spi_miso.value = 0
                continue

            self.dut._log.debug(f"SPI READ 0x03 addr=0x{address:06X}")

            # Return four bytes in increasing byte-address order.
            # For each returned bit:
            #   - update MISO after SCK falling edge
            #   - master samples it on the following SCK rising edge
            for offset in range(4):
                byte = self._read_byte(address + offset)

                for bit_index in range(7, -1, -1):
                    ok = await self._wait_sck_falling_while_selected()
                    if not ok:
                        aborted = True
                        break

                    self.dut.spi_miso.value = (byte >> bit_index) & 1

                    ok = await self._wait_sck_rising_while_selected()
                    if not ok:
                        aborted = True
                        break

                if aborted:
                    break

            # Wait until transaction ends, unless it already ended.
            if self.dut.spi_cs_n.value == 0:
                await RisingEdge(self.dut.spi_cs_n)

            self.dut.spi_miso.value = 0
