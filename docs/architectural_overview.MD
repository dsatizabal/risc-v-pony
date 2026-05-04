# Risc V Pony: General architecture overview

The RiscV Pony supports the basics embbeded instructions set RV32E. It is composed by the following components implemented in Verilog:

- Arithmetic and Logic Unit (ALU)
- Control Unit
- Core
- Decoder
- Program Counter
- RAM bank
- Registers File
- SPI Fetcher (External ROM memory)
- Timer (added)

Let's explore one by one the components.

## The ALU

The [ALU](../src/alu.v) is a simple combinantional curcuit, it takes 2 32-bits operand, a 4-bits control or operation indicator and outputs a 32-bit result and a single-bit zero flag.

The following operations are supported:

- Addition (alu_ctrl = 0000)
- Substraction (alu_ctrl = 1000)
- Shift Left Logical (alu_ctrl = 0001)
- Signed Compare (alu_ctrl = 0010)
- Unsigned Compare  (alu_ctrl = 0011)
- XOR  (alu_ctrl = 0100)
- Shift Right Logical  (alu_ctrl = 0101)
- Shift Right Arithmetic  (alu_ctrl = 1101)
- OR  (alu_ctrl = 0110)
- AND  (alu_ctrl = 0111)

## The Program Counter

The [PC](../src/program_counter.v) isn't a simple register to hold current instruction address, it does that but is made up in a synchronous block that takes the next value that the PC can hold, that allows flexibility to load it with a jump address or simply the next aligned address comprised by the current address plus 4.

On reset it sets the PC to the reset vector 0x00000000. The next PC value gets written to PC once the pc_en signal is driven high for a clock cycle.

We have no validation of unalagined addresses here, as we're not supporting comppressed addresses (C extension) and we're aiming to always generate machine code using a compiler with flags targetting RV32E only we can rest assured we won't get any unallignments, if you want to write hex yourself you're on your own.

## The SPI Fetcher

TODO: Add documentation

## The Registers File

The [Regs File](../src/reg_file.v) is the set of 16 32-bits-wide registers required for the RV32E, here's the key difference with an RV32I which requires twice as many of those regs.

It operates like this: we can read 2 regs at the same time and the read is an async (combinational) operation, just set rs1 and rs2 addresses and get the value in the corresponding rs1 and rs2 data.

The write operation is synchronous, so, when we is driven high, on a clock rising edge the value of _rd_data_ will be written in the register specified by _rd_addr_.

Notice the exception that the register 0 must be always read as zero by Risc V design and cannot be written.

## The internal RAM block

The [Internal RAM](../src/ram.v) is a simple 32x32-bits scratchpad memory block, it operates in a similar fashion to the regs file except that here the address 0 is ussable and we have a special write mode to support the different store instructions.

The read operation is also async here, meaning that once the address is set the output reads immediately (well, it takes some time you must know it) the value of that address in the output.

The write operation is write-enabled by a mask indicating what byte of the 32-bits data is written to the address. So, a _SB_ instruction will have only the _we[0]_ bit set to 1.

TODO: Clarify why the address bits 6-2 are used.

## The Decoder

The [decoder](../src/decoder.v) is one of the pilars for instructions execution, this is a fully combinational block that takes the 32-bits instruction and fills all possible fields contained within it, that is, not all instructions have func7 or rs2, but we read the bits where those values are expected to be and place in registers for its use during the execution phase.

The immediate extraction is by far the most complicated process as that value can vary in bit count and sometimes scrambled in different (though predictable) bit positions, so, according to the opcode the immediate values gets extracted and the sign extended according to what's required.

The values extracted in the decoder are used according to the instruction later in the ALU, the Regs File, the RAM, the PC and the Control Unit.

## The Control Unit

The [Control Unit](../src/control_unit.v)'s of course the backbone of the CPU, here's where the execution happens.

The Control Unit is a semi-synchronous block, that meaning it is a combinational block that takes a clock to change the current status when necessary.

On reset the state machine within the Control Unit is set to _FETCHING_, that requests to the SPI Fetcher to read 4 bytes from the ROM, the Control Unit gets to a _WAITING_ state as the fetcher may take some 32 clock cycles to fetch a workd.

Once the instruction is in the core, the next state is _EXECUTING_, in this state the Control Unit uses the opcode again to determine which signals to activate for the other blocks to act accordingly, for example, for an instruction of type ADDI the following happens:

- The Control Unit sets the _alu_ctrl_ signal according to the value decoded for funct3, in this case 0000
- The signal _reg_we_ is driven high indicating a write operation to the Regs File
- The _alu_src_b_ is driven high to indicate the ALU to get the operand 2 from the calculated immediate value (that's the I of ADDI)
- Then on the next clock rising edge the Reg File being enabled to write writes the ALU result (see _wb_sel_ is not set to any particular value for this operation thus takes ALU as default value source for _rd_data_) into the address given by the _rd_addr_ that comes from the decoder
- The Contro Unit State machine also moves to the _FETCH_ state again and the cycle continues

## The Core

The [core](../src/core.v) is the centerpiece of the CPU but has a less protagonic paper than that of the Control Unit, here just the scaffolding of all the required blocks takes place, also, some control signals exsit, for example to indicate according to the _wb_sel_ what value gets written to a particular register in the file, or where the ALU takes the second operand from according to the _alu_src_b_ signal coming from the Control Unit.

Two important functions that happens at core level are:

- Data alignment for when instructions like LB/LW or SB/SW are performed, in this case we must alling the data to the 32 bits to be written into memory if required
- Selection of the next value that PC will take, this depending if the instruction is a jump / branch or we're just going to the next instructions (PC = PC + 4)

## The Timer

TODO: Add documentation

TODO: Add documentation for ECALL / EBREAK / FENCE