import cocotb
from cocotb.triggers import FallingEdge, RisingEdge


class FakeSPIFlash:
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

        Keep that API, but internally model a real byte-addressed SPI flash.
        RISC-V firmware is little-endian, so the instruction word 0x08000093
        is stored as bytes 93 00 00 08.
        """
        for address, word in memory_map.items():
            word &= 0xFFFFFFFF
            for offset, byte in enumerate(word.to_bytes(4, byteorder="little")):
                self.memory[address + offset] = byte

    def _load_bytes(self, data):
        """
        Load a normal firmware.bin image exactly as a real SPI flash would
        contain it: one byte at each increasing address.
        """
        for address, byte in enumerate(data):
            self.memory[address] = byte

    def _read_byte(self, address):
        if address in self.memory:
            return self.memory[address]

        # Default unmapped instruction is NOP: 0x00000013.
        # In little-endian flash byte order that is 13 00 00 00.
        nop_bytes = [0x13, 0x00, 0x00, 0x00]
        return nop_bytes[address & 0x3]

    async def _run(self):
        while True:
            await FallingEdge(self.dut.spi_cs_n)
            await RisingEdge(self.dut.clk)

            shift_in = 0

            # Receive 8-bit command + 24-bit byte address.
            for _ in range(32):
                await FallingEdge(self.dut.clk)

                mosi_val = self.dut.spi_mosi.value
                bit = 0 if str(mosi_val).lower() in ["x", "z", "u"] else int(mosi_val)
                shift_in = (shift_in << 1) | bit

            command = (shift_in >> 24) & 0xFF
            address = shift_in & 0xFFFFFF

            if command != 0x03:
                self.dut._log.warning(f"Unexpected SPI flash command 0x{command:02X}")

            # Return four bytes in increasing byte-address order, MSB first
            # within each byte, matching a real SPI flash read stream.
            for offset in range(4):
                byte = self._read_byte(address + offset)

                for bit_index in range(7, -1, -1):
                    self.dut.spi_miso.value = (byte >> bit_index) & 1
                    await FallingEdge(self.dut.clk)

            await RisingEdge(self.dut.spi_cs_n)
            self.dut.spi_miso.value = 0
