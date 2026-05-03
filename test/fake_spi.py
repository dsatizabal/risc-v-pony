import cocotb
from cocotb.triggers import FallingEdge, RisingEdge

class FakeSPIFlash:
    def __init__(self, dut, memory_map=None, bin_file=None):
        self.dut = dut
        self.memory = memory_map if memory_map is not None else {}
        self.dut.spi_miso.value = 0

        if bin_file:
            dut._log.info(f"Loading firmware from disk: {bin_file}")
            with open(bin_file, "rb") as f:
                code = f.read()
            for i in range(0, len(code), 4):
                word = int.from_bytes(code[i:i+4], byteorder='little')
                self.memory[i] = word

        cocotb.start_soon(self._run())

    async def _run(self):
        while True:
            await FallingEdge(self.dut.spi_cs_n)
            await RisingEdge(self.dut.clk)

            shift_in = 0
            for _ in range(32):
                await FallingEdge(self.dut.clk)
                # --- FIX: Handle 'x' on MOSI gracefully ---
                mosi_val = self.dut.spi_mosi.value
                bit = 0 if str(mosi_val) in ['x', 'z', 'u'] else int(mosi_val)
                shift_in = (shift_in << 1) | bit

            address = shift_in & 0xFFFFFF

            # --- FIX: Return a NOP (0x00000013) if address is out of bounds ---
            # This prevents the CPU from executing 0x00000000 (which is an instruction)
            # or 'x' which crashes the sim.
            instruction = self.memory.get(address, 0x00000013)

            for i in range(32):
                bit_val = (instruction >> (31 - i)) & 1
                self.dut.spi_miso.value = bit_val
                await FallingEdge(self.dut.clk)

            await RisingEdge(self.dut.spi_cs_n)
            self.dut.spi_miso.value = 0
