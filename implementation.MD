# RiscV Pony — Complete Implementation Reference

**Project:** RiscV Pony
**Author:** Diego Satizabal
**Target:** [Tiny Tapeout](https://tinytapeout.com) ASIC (Sky130 PDK), 2×2 tiles
**ISA:** RISC-V RV32E (32-bit, 16 integer registers)
**Top Module:** `tt_um_dsp_riscv_pony`
**Clock:** 50 MHz (design target)
**Simulator:** Icarus Verilog + cocotb

---

## 1. High-Level Architecture

The CPU is a **multi-cycle, in-order** design. Because program instructions are stored on an external SPI Flash chip (not in on-chip ROM), fetching one instruction takes ~65 clock cycles. The control unit therefore runs a 3-state FSM before executing any instruction:

```
FETCH → WAIT → EXECUTE → FETCH → ...
  │        │         │
  │     (≥64 cycles) │
  │                  │
  └──────────────────┘
   pulse fetch_req     pulse pc_en
```

| State       | Duration    | Action |
|-------------|-------------|--------|
| STATE_FETCH | 1 cycle     | Assert `fetch_req` to the SPI Fetcher |
| STATE_WAIT  | ≥64 cycles  | Wait for `fetch_done` from SPI Fetcher |
| STATE_EXECUTE | 1 cycle   | Decode, read registers, compute ALU, write-back, update PC |

---

## 2. Building Blocks

```
                ┌─────────────────────────────────────────────────────┐
                │                     core.v                          │
                │                                                     │
  clk,rst_n ───►│                                                     │
                │  ┌──────────┐   fetch_req / fetch_done              │
                │  │ pc_reg   ├──►┌─────────────┐                    │
                │  │          │◄──┤ spi_fetcher │◄─── spi_miso       │
                │  └────┬─────┘   └──────┬──────┘──── spi_cs_n/sck  │
                │       │pc              │inst_data   /spi_mosi      │
                │       │        ┌───────▼──────┐                    │
                │       │        │   decoder    │                    │
                │       │        └──────┬───────┘                    │
                │       │               │opcode,funct3,funct7,rs1    │
                │       │               │rs2,rd,imm                  │
                │       │        ┌──────▼───────┐                    │
                │       │        │ control_unit │                    │
                │       │        └──────┬───────┘                    │
                │       │               │alu_ctrl,reg_we,mem_we,     │
                │       │               │alu_src_b,pc_src,wb_sel,    │
                │       │               │mem_size,mem_unsigned        │
                │       │        ┌──────┼──────────────┐             │
                │       │        │  ┌───▼───┐  ┌─────┐ │            │
                │       │        │  │regfile│  │ ALU │ │            │
                │       │        │  └───────┘  └─────┘ │            │
                │       │        │      RAM    MMIO     │            │
                │       │        └─────────────────────┘            │
                │                                                     │
                │ out_port[7:0] ────────────────────────────────────►│
                │ in_port[7:0]  ◄────────────────────────────────────│
                └─────────────────────────────────────────────────────┘
```

### Module Inventory

| File | Module | Purpose |
|------|--------|---------|
| `program_counter.v` | `pc_reg` | 32-bit PC register with enable |
| `spi_fetcher.v` | `spi_fetcher` | Fetch instructions over SPI |
| `decoder.v` | `decoder` | Decode instruction fields & generate immediates |
| `control_unit.v` | `control_unit` | 3-state FSM + datapath control signals |
| `reg_file.v` | `regfile` | RV32E 16-register file |
| `alu.v` | `alu` | 32-bit combinational ALU |
| `ram.v` | `ram` | 128-byte internal SRAM |
| `core.v` | `core` | Top-level glue: wires all modules + MMIO logic |
| `project.v` | `tt_um_dsp_riscv_pony` | Tiny Tapeout wrapper |

---

## 3. Pin-Out (Tiny Tapeout Interface)

The `project.v` wrapper maps the generic Tiny Tapeout pins to the CPU's signals:

| TT Pin | Direction | CPU Signal | Description |
|--------|-----------|-----------|-------------|
| `ui_in[7:0]` | Input | `in_port[7:0]` | General-purpose 8-bit input port (MMIO read) |
| `uo_out[7:0]` | Output | `out_port[7:0]` | General-purpose 8-bit output port (MMIO write) |
| `uio_out[0]` | Output | `spi_cs_n` | SPI Chip Select (active low) |
| `uio_out[1]` | Output | `spi_sck` | SPI Serial Clock |
| `uio_out[2]` | Output | `spi_mosi` | SPI Master Out Slave In |
| `uio_in[3]` | Input | `spi_miso` | SPI Master In Slave Out |
| `clk` | Input | `clk` | System clock (50 MHz) |
| `rst_n` | Input | `rst_n` | Active-low synchronous reset |

`uio_oe` is hardwired to `8'b1111_0111` (bit 3 = input for MISO, all others outputs).

---

## 4. Memory Map

| Address Range | Size | Region | Description |
|---------------|------|--------|-------------|
| `0x000000` and up | 16 MB max | SPI Flash | Instruction memory (program code) |
| `0x000000 – 0x00007F` | 128 bytes | Internal RAM | Data memory (32 words × 32 bits) |
| `0x00080` (128) | 1 byte | MMIO OUT | Write `rs2[7:0]` to physical output pins |
| `0x00084` (132) | 1 byte | MMIO IN | Read physical input pins as `{24'b0, in_port}` |

> **Note:** The internal RAM and MMIO addresses are decoded by comparing the ALU result address against the literals `128` and `132` in `core.v`. The RAM naturally mirrors across its 128-byte window due to the `addr[6:2]` indexing.

---

## 5. Supported Instructions

### 5.1 R-Type (opcode `7'b0110011`)

Register-register arithmetic. Both source operands come from the register file.

| Instruction | funct3 | funct7[5] | ALU op | Operation |
|-------------|--------|-----------|--------|-----------|
| `ADD` | `000` | 0 | `0000` | `rd = rs1 + rs2` |
| `SUB` | `000` | 1 | `1000` | `rd = rs1 - rs2` |
| `SLL` | `001` | — | `0001` | `rd = rs1 << rs2[4:0]` |
| `SLT` | `010` | — | `0010` | `rd = (signed rs1 < signed rs2) ? 1 : 0` |
| `SLTU` | `011` | — | `0011` | `rd = (rs1 < rs2) ? 1 : 0` |
| `XOR` | `100` | — | `0100` | `rd = rs1 ^ rs2` |
| `SRL` | `101` | 0 | `0101` | `rd = rs1 >> rs2[4:0]` (logical) |
| `SRA` | `101` | 1 | `1101` | `rd = rs1 >>> rs2[4:0]` (arithmetic) |
| `OR` | `110` | — | `0110` | `rd = rs1 \| rs2` |
| `AND` | `111` | — | `0111` | `rd = rs1 & rs2` |

### 5.2 I-Type ALU (opcode `7'b0010011`)

Register-immediate arithmetic. Operand B comes from the sign-extended immediate.

| Instruction | funct3 | Note | Operation |
|-------------|--------|------|-----------|
| `ADDI` | `000` | — | `rd = rs1 + imm` |
| `SLLI` | `001` | — | `rd = rs1 << imm[4:0]` |
| `SLTI` | `010` | — | `rd = (signed rs1 < signed imm) ? 1 : 0` |
| `SLTIU` | `011` | — | `rd = (rs1 < imm) ? 1 : 0` |
| `XORI` | `100` | — | `rd = rs1 ^ imm` |
| `SRLI` | `101` | funct7[5]=0 | `rd = rs1 >> imm[4:0]` |
| `SRAI` | `101` | funct7[5]=1 | `rd = rs1 >>> imm[4:0]` |
| `ORI` | `110` | — | `rd = rs1 \| imm` |
| `ANDI` | `111` | — | `rd = rs1 & imm` |

### 5.3 Load (opcode `7'b0000011`)

Address computed as `rs1 + imm`. Data written back to `rd` via the aligned read path.

| Instruction | funct3 | mem_size | mem_unsigned | Operation |
|-------------|--------|----------|--------------|-----------|
| `LB` | `000` | `00` | 0 | Load byte, sign-extend |
| `LH` | `001` | `01` | 0 | Load halfword, sign-extend |
| `LW` | `010` | `10` | 0 | Load word (32 bits) |
| `LBU` | `100` | `00` | 1 | Load byte, zero-extend |
| `LHU` | `101` | `01` | 1 | Load halfword, zero-extend |

### 5.4 Store (opcode `7'b0100011`)

Address computed as `rs1 + imm`. Data from `rs2` is written to RAM with byte-lane masking.

| Instruction | funct3 | mem_size | Bytes written |
|-------------|--------|----------|---------------|
| `SB` | `000` | `00` | 1 byte at `addr[1:0]` lane |
| `SH` | `001` | `01` | 2 bytes (lower or upper halfword) |
| `SW` | `010` | `10` | All 4 bytes |

### 5.5 Branch (opcode `7'b1100011`)

Both `rs1` and `rs2` go through the ALU. `pc_src = 2'b01` selects `PC + imm` if the branch is taken; otherwise `PC + 4`.

| Instruction | funct3 | ALU op | Branch taken when |
|-------------|--------|--------|-------------------|
| `BEQ` | `000` | SUB (`1000`) | `zero == 1` |
| `BNE` | `001` | SUB (`1000`) | `zero == 0` |
| `BLT` | `100` | SLT (`0010`) | `alu_result[0] == 1` |
| `BGE` | `101` | SLT (`0010`) | `alu_result[0] == 0` |
| `BLTU` | `110` | SLTU (`0011`) | `alu_result[0] == 1` |
| `BGEU` | `111` | SLTU (`0011`) | `alu_result[0] == 0` |

### 5.6 Jump (JAL / JALR)

| Instruction | Opcode | `rd` written | PC next |
|-------------|--------|-------------|---------|
| `JAL` | `7'b1101111` | `PC + 4` (via `wb_sel = 3'b010`) | `PC + imm` (J-type) |
| `JALR` | `7'b1100111` | `PC + 4` (via `wb_sel = 3'b010`) | `{alu_result[31:1], 1'b0}` |

### 5.7 Upper Immediate (LUI / AUIPC)

| Instruction | Opcode | `rd` written | PC effect |
|-------------|--------|-------------|-----------|
| `LUI` | `7'b0110111` | `imm` directly (`wb_sel = 3'b011`) | `PC + 4` |
| `AUIPC` | `7'b0010111` | `PC + imm` (`wb_sel = 3'b100`) | `PC + 4` |

---

## 6. Module Deep-Dives

### 6.1 Program Counter — `pc_reg`

```
Ports:
  clk, rst_n          — clock and active-low reset
  pc_en               — only latch pc_next when high
  pc_next [31:0]      — new address (from core.v glue logic)
  pc      [31:0]      — current address (sent to spi_fetcher)
```

- Resets to `32'h00000000` on `!rst_n`.
- Updated only when the control unit pulses `pc_en` during STATE_EXECUTE, preventing runaway PC advances while waiting for SPI.
- The `+4` / `branch` / `JALR` address calculation lives in `core.v`, keeping this module minimal.

### 6.2 SPI Fetcher — `spi_fetcher`

```
Ports:
  clk, rst_n, fetch_req, pc_addr[31:0]
  spi_cs_n, spi_sck, spi_mosi (outputs)
  spi_miso (input)
  inst_data[31:0], fetch_done (outputs)
```

**3-state FSM:** `IDLE → SHIFT → DONE`

**Shift register (64 bits):**

```
[63:56]  [55:32]          [31:0]
 0x03    pc_addr[23:0]    ← incoming MISO data
 (READ   (24-bit address)   (32-bit instruction)
 command)
```

Each clock in `SHIFT`:
1. Drive `shift_reg[63]` onto `spi_mosi`.
2. Left-shift the register, sampling `spi_miso` into bit 0.
3. Decrement `bit_counter` (starts at 63, counts to 0 = 64 transfers).

On entry to `DONE`, `shift_reg[31:0]` holds the fetched instruction. `fetch_done` pulses for one cycle.

**SPI clock:** `spi_sck = (state == SHIFT) ? clk : 1'b0` — the SPI clock only runs during the shift phase.

> SPI Mode 0 (CPOL=0, CPHA=0). Compatible with the W25Q-series and most common SPI Flash devices. Read command `0x03` supports up to ~50 MHz.

### 6.3 Instruction Decoder — `decoder`

Purely combinational. Slices the 32-bit instruction into labeled wires.

```
Fixed-position fields (always the same bits in any instruction):
  opcode = inst[6:0]
  rd     = inst[11:7]
  funct3 = inst[14:12]
  rs1    = inst[19:15]   (5 bits; only [3:0] used in RV32E)
  rs2    = inst[24:20]   (5 bits; only [3:0] used in RV32E)
  funct7 = inst[31:25]
```

**Immediate reconstruction by format:**

| Format | Opcode(s) | Immediate assembly |
|--------|-----------|--------------------|
| I-Type | `0010011`, `0000011`, `1100111` | `{{20{inst[31]}}, inst[31:20]}` |
| S-Type | `0100011` | `{{20{inst[31]}}, inst[31:25], inst[11:7]}` |
| B-Type | `1100011` | `{{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0}` |
| U-Type | `0110111`, `0010111` | `{inst[31:12], 12'b0}` |
| J-Type | `1101111` | `{{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0}` |

The bit scrambling in B-Type and J-Type immediates is intentional in the RISC-V ISA spec: it reduces wire crossings across the physical die.

### 6.4 Control Unit — `control_unit`

```
Inputs:  clk, rst_n, opcode[6:0], funct3[2:0], funct7_bit5,
         zero, fetch_done, alu_result_0
Outputs: fetch_req, pc_en, pc_src[1:0],
         reg_we, alu_src_b, alu_ctrl[3:0],
         mem_we, wb_sel[2:0],
         mem_size[1:0], mem_unsigned
```

**`pc_src` encoding:**

| `pc_src` | PC next source |
|----------|----------------|
| `2'b00` | `PC + 4` (sequential) |
| `2'b01` | `PC + imm` (branch taken / JAL) |
| `2'b10` | `{alu_result[31:1], 1'b0}` (JALR) |

**`wb_sel` encoding (write-back multiplexer):**

| `wb_sel` | Data written to `rd` |
|----------|----------------------|
| `3'b000` | ALU result |
| `3'b001` | Memory read (aligned) |
| `3'b010` | `PC + 4` (return address for JAL/JALR) |
| `3'b011` | Immediate (LUI) |
| `3'b100` | `PC + imm` (AUIPC) |

**`mem_size` encoding:**

| `mem_size` | Access width |
|------------|--------------|
| `2'b00` | Byte (8-bit) |
| `2'b01` | Halfword (16-bit) |
| `2'b10` | Word (32-bit) |

`mem_size` and `mem_unsigned` are derived directly from `funct3`:
- `mem_size = funct3[1:0]`
- `mem_unsigned = funct3[2]` (1 for LBU/LHU, 0 for LB/LH/LW)

### 6.5 Register File — `regfile`

```
Ports:
  clk, we
  rs1_addr[3:0], rs2_addr[3:0]   — read addresses
  rd_addr[3:0]                    — write address
  rd_data[31:0]                   — data to write
  rs1_data[31:0], rs2_data[31:0] — read data outputs
```

- **16 registers** (RV32E). Physical storage is `reg [31:0] registers [1:15]` — register 0 is not stored.
- **x0 is hardwired to zero:** reads return `32'b0`; writes to address `0` are silently discarded.
- **Asynchronous reads**, **synchronous write** (on `posedge clk` when `we = 1`).
- No reset — general-purpose registers are undefined at power-on (standard CPU practice; compilers initialize before use).
- The instruction decoder outputs 5-bit register addresses per the RISC-V spec. `core.v` passes only `[3:0]` to this module, safely discarding the MSB.

### 6.6 ALU — `alu`

```
Ports:
  a[31:0], b[31:0]   — operands
  alu_ctrl[3:0]      — operation selector
  result[31:0]       — output
  zero               — 1 if result == 0
```

Purely combinational (`always @(*)`). The zero flag is a continuous assignment: `assign zero = (result == 32'b0)`.

| `alu_ctrl` | Operation | Notes |
|------------|-----------|-------|
| `4'b0000` | ADD | |
| `4'b1000` | SUB | Also used for BEQ/BNE branch comparison |
| `4'b0001` | SLL | Shift amount = `b[4:0]` |
| `4'b0010` | SLT | `$signed(a) < $signed(b)` |
| `4'b0011` | SLTU | Unsigned comparison |
| `4'b0100` | XOR | |
| `4'b0101` | SRL | Logical right shift |
| `4'b1101` | SRA | `$signed(a) >>> b[4:0]` |
| `4'b0110` | OR | |
| `4'b0111` | AND | |

The top bit of `alu_ctrl` acts as a SUB/SRA modifier, mirroring `funct7[5]` in the instruction encoding.

### 6.7 Data RAM — `ram`

```
Ports:
  clk
  we[3:0]           — 4-bit byte-lane write-enable mask
  addr[31:0]        — byte address (only [6:2] used for 32-word indexing)
  write_data[31:0]  — data to store
  read_data[31:0]   — data loaded
```

- 128 bytes = 32 × 32-bit words: `reg [31:0] memory [0:31]`
- **Word index** = `addr[6:2]` (divides byte address by 4).
- **Asynchronous read**, **synchronous write** per byte lane:

```verilog
if (we[0]) memory[addr[6:2]][7:0]   <= write_data[7:0];
if (we[1]) memory[addr[6:2]][15:8]  <= write_data[15:8];
if (we[2]) memory[addr[6:2]][23:16] <= write_data[23:16];
if (we[3]) memory[addr[6:2]][31:24] <= write_data[31:24];
```

### 6.8 Core Glue Logic — `core`

`core.v` instantiates all modules and implements the datapath connections that span multiple modules.

#### Write Aligner (Store Path)

Before the `ram` module, a combinational block in `core.v` computes `ram_we_mask` and `ram_write_data` based on `mem_size` and the two LSBs of the effective address (`alu_result[1:0]`):

| `mem_size` | `alu_result[1:0]` | `ram_we_mask` | Data replication |
|------------|-------------------|---------------|-----------------|
| `00` (SB) | `00` | `4'b0001` | `{4{rs2[7:0]}}` |
| `00` (SB) | `01` | `4'b0010` | `{4{rs2[7:0]}}` |
| `00` (SB) | `10` | `4'b0100` | `{4{rs2[7:0]}}` |
| `00` (SB) | `11` | `4'b1000` | `{4{rs2[7:0]}}` |
| `01` (SH) | `x0` | `4'b0011` | `{2{rs2[15:0]}}` |
| `01` (SH) | `x1` | `4'b1100` | `{2{rs2[15:0]}}` |
| `10` (SW) | any | `4'b1111` | full word |

MMIO writes (`alu_result == 128`) bypass the RAM: the byte is latched into `out_reg` on the clock edge.

#### Read Aligner (Load Path)

After reading from RAM (or MMIO IN), `aligned_read_data` is computed based on `mem_size`, `mem_unsigned`, and `alu_result[1:0]`:

- **LB/LBU:** Extract the correct byte from the 32-bit word, then sign- or zero-extend to 32 bits.
- **LH/LHU:** Extract lower or upper 16-bit halfword, then extend.
- **LW:** Pass the full 32-bit word unchanged.

MMIO IN reads: when `alu_result == 132`, `raw_read_data = {24'b0, in_port}` (zero-extended 8-bit physical input).

#### PC Next Multiplexer

```
pc_next = (pc_src == 2'b10) ? {alu_result[31:1], 1'b0}  // JALR (force LSB=0)
        : (pc_src == 2'b01) ? pc_current + imm           // Branch / JAL
        :                      pc_current + 4;            // Sequential
```

---

## 7. SPI Interface

### Protocol

- **Mode:** SPI Mode 0 (CPOL=0, CPHA=0) — data sampled on rising edge of `spi_sck`.
- **Transaction length:** 64 clock cycles per instruction fetch.
- **Frame layout:**

```
Cycle:   1─────8  9─────────────32  33─────────────64
         [ CMD ]  [   ADDRESS   ]   [    DATA IN   ]
           0x03    pc_addr[23:0]     instruction[31:0]
```

- **Chip Select:** `spi_cs_n` goes low at the start of STATE_SHIFT and returns high when the DONE state is entered.
- **Compatible devices:** Any SPI NOR Flash responding to the `0x03` Read command (e.g., W25Q32, AT25SF, GD25Q).

### Timing Diagram (simplified)

```
CS_N  ‾‾‾‾‾|___________________________________|‾‾
SCK   ________|‾|_|‾|_|‾|_|‾|_|‾|_|…(64 edges)
MOSI  ───────[ 0x03 | PC[23:0] | don't care  ]──
MISO  ─────────────────────────[ inst[31:0]  ]──
```

---

## 8. Datapath Signal Summary

| Signal | Width | Source | Destination | Meaning |
|--------|-------|--------|-------------|---------|
| `pc_current` | 32 | `pc_reg` | `spi_fetcher`, glue | Current program counter |
| `pc_next` | 32 | glue MUX | `pc_reg` | Next PC value |
| `pc_en` | 1 | `control_unit` | `pc_reg` | Latch `pc_next` |
| `pc_src` | 2 | `control_unit` | glue MUX | PC source select |
| `fetch_req` | 1 | `control_unit` | `spi_fetcher` | Start SPI fetch |
| `fetch_done` | 1 | `spi_fetcher` | `control_unit` | Instruction ready |
| `inst_data` | 32 | `spi_fetcher` | `decoder` | Raw 32-bit instruction |
| `opcode` | 7 | `decoder` | `control_unit` | Instruction category |
| `funct3` | 3 | `decoder` | `control_unit` | Sub-operation |
| `funct7` | 7 | `decoder` | `control_unit` | Extended op (bit 5 used) |
| `rs1_addr` | 5 | `decoder` | `regfile` (4-bit slice) | Source reg 1 |
| `rs2_addr` | 5 | `decoder` | `regfile` (4-bit slice) | Source reg 2 |
| `rd_addr` | 5 | `decoder` | `regfile` (4-bit slice) | Dest reg |
| `imm` | 32 | `decoder` | ALU mux, PC adder | Sign-extended immediate |
| `rs1_data` | 32 | `regfile` | ALU input A | Operand A |
| `rs2_data` | 32 | `regfile` | ALU mux (or store data) | Operand B / store data |
| `alu_operand_b` | 32 | MUX | ALU input B | `rs2_data` or `imm` |
| `alu_src_b` | 1 | `control_unit` | MUX | 0=reg, 1=immediate |
| `alu_ctrl` | 4 | `control_unit` | `alu` | ALU operation |
| `alu_result` | 32 | `alu` | RAM addr, MMIO decode, writeback | Computed address or value |
| `zero_flag` | 1 | `alu` | `control_unit` | Result == 0 (BEQ/BNE) |
| `reg_we` | 1 | `control_unit` | `regfile` | Write-enable register file |
| `wb_sel` | 3 | `control_unit` | writeback MUX | What to write back to `rd` |
| `rd_data` | 32 | writeback MUX | `regfile` | Data written to destination register |
| `mem_we` | 1 | `control_unit` | write aligner | Store instruction |
| `mem_size` | 2 | `control_unit` | write/read aligners | Access width |
| `mem_unsigned` | 1 | `control_unit` | read aligner | Sign vs. zero extend |
| `ram_we_mask` | 4 | write aligner | `ram` | Byte-lane write enable |
| `mem_read_data` | 32 | `ram` | read aligner | Raw word from RAM |
| `aligned_read_data` | 32 | read aligner | writeback MUX | Properly sized/extended load result |

---

## 9. Tests

Tests use **cocotb** (Python coroutines) with **Icarus Verilog** as the simulator. A `FakeSPIFlash` class (`fake_spi.py`) responds to SPI transactions from the DUT, serving instructions from a Python dictionary or a binary firmware file.

Each instruction fetch takes ~65 clock cycles, so tests budget `N_instructions × 65` cycles.

### Test Modules

| File | Test | What it verifies |
|------|------|-----------------|
| `test_core.py` | `test_simple_addition` | ADDI + ADD (R/I-Type basics) |
| `test_core.py` | `test_branch_loop` | BNE backward branch, accumulator loop |
| `test_ram.py` | `test_load_store` | SW + LW round-trip through internal RAM |
| `test_jump.py` | `test_jal_jalr` | Function call (JAL) and return (JALR) |
| `test_io.py` | `test_mmio` | LW from IN port (addr 132), SW to OUT port (addr 128) |
| `test_fibonacci.py` | `test_fibonacci` | 10-iteration Fibonacci sequence streamed to MMIO |
| `test_c_code.py` | `test_c_firmware` | Full compiled C binary loaded from `firmware/counter/firmware.bin` |
| `test_interactive.py` | (interactive) | Manual/interactive simulation runs |

### Running the Tests

```bash
cd test
make
# For gate-level simulation:
make GATES=yes
```

Results are written to `results.xml`.

### FakeSPIFlash Behavior

The `FakeSPIFlash` cocotb coroutine monitors `spi_cs_n`, `spi_sck`, and `spi_mosi`. When it detects a complete `0x03` read command followed by a 24-bit address, it drives the corresponding 32-bit instruction byte-by-byte onto `spi_miso`, LSB-first on each SCK rising edge.

---

## 10. Known Discrepancies Between Docs and Implementation

The following items in the per-module docs were outdated relative to the actual Verilog:

| Doc file | Outdated claim | Actual implementation |
|----------|---------------|----------------------|
| `control.MD` | `branch_taken` (1-bit) | `pc_src` is 2-bit, supports 3 PC sources |
| `control.MD` | Only BEQ described | BEQ, BNE, BLT, BGE, BLTU, BGEU all supported |
| `control.MD` | No mention of mem_we, wb_sel | Both present; wb_sel is 3-bit with 5 options |
| `control.MD` | No mention of JAL, JALR, LUI, AUIPC | All four implemented |
| `control.MD` | No byte/halfword operations | mem_size and mem_unsigned outputs added |
| `ram.MD` | `we` is 1-bit | `we` is a 4-bit byte-lane mask |
| `ram.MD` | Only LW/SW mentioned | LB, LH, SB, SH also supported via mask |
| `core.md` | No mention of I/O ports | `out_port` and `in_port` (8-bit MMIO) are core ports |
| `core.md` | Only 2 PC adders (PC+4, PC+imm) | Third source added for JALR (`{alu_result[31:1], 1'b0}`) |
| `core.md` | No mention of MMIO | MMIO at addresses 128 (OUT) and 132 (IN) |
| `core.md` | No mention of byte/halfword alignment | Write aligner and read aligner implemented in core.v |
| `decoder.MD` | Only I-Type immediate mentioned | S, B, U, J-Type immediate generation all implemented |
| `alu.MD` | Has `default_nettype none` at top | Not present in actual alu.v |
