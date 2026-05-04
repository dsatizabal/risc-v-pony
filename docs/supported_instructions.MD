# Risc V Pony: General architecture overview
 Next the full list of supported instructions by the Risc V Pony CPU

 ## Branch instructions

6 Instructions:

- BEQ: Branch Equal
- BNE: Branch Not Equal
- BLT: Branch Lower Than
- BGE: Branch Greater or Equal
- BLTU: Branch Lower Than (Unsigned)
- BGEU: Branch Greater or Equal (Unsigned)

 ## ALU-Immediate instructions

9 Instructions:

- ADDI: Add Immediate
- SLTI: Set Less Than Immediate
- SLTIU: Set Less Than Immediate (Unsigned)
- XORI: XOR Immediate
- ORI: OR Immediate
- ANDI: AND Immediate
- SLLI: Shift Left Logical Immediate
- SRLI: Shift Right Logical Immediate
- SRAI:  Shift Right Arithmetic Immediate

 ## ALU instructions

10 Instructions:

- ADD: Regs Addition
- SUB: Regs Substraction
- SLL: Shif Left Logical
- SLT: Set Less Than
- SLTU: Set Less Than (Unsigned)
- XOR: XOR
- SRL: Shift Right Logical
- SRA: Shift Right Arithmetic
- OR: OR
- AND: AND

 ## Load/Store instructions

8 Instructions:

- LB: Load Byte
- LH:Load Half
- LW: Load Word
- LBU: Load Byte (Unsigned)
- LHU: Load Half (Unsigned)
- SB: Store Byte
- SH: Store Half
- SW: Store Word

# Jump Instructions

2 Instructions:

- JAL: Jump and Link
- JALR: Jump and Link Register

# Registers Manipulation

2 Instructions:

- LUI: Load Unsigned Immediate
- AUIPC: Add Upper Immediate to PC

TODO: Add ECALL / EBREAK / FENCE
TODO: Validate instructions from the code like J and LI that don't show in the manual
