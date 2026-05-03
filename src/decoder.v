`default_nettype none

module decoder (
    input  wire [31:0] inst,       // The raw 32-bit instruction from memory

    // Standard fields extracted directly
    output wire [6:0]  opcode,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [4:0]  rs1,        // 5 bits from instruction (we'll only use 4 for RV32E)
    output wire [4:0]  rs2,
    output wire [4:0]  rd,

    // The reconstructed 32-bit Immediate value
    output reg  [31:0] imm
);

    // 1. Direct wire assignments for the standard fields
    // RISC-V makes this easy; these are always in the exact same place!
    assign opcode = inst[6:0];
    assign rd     = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1    = inst[19:15];
    assign rs2    = inst[24:20];
    assign funct7 = inst[31:25];

    // 2. Immediate Generation Logic
    always @(*) begin
        case (opcode)
            // I-Type:
            // All the following instructions have opcode = 0010011: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
            // All the following instructions have opcode = 0000011: LB, LH, LW, LBU, LHU
            // Opcode 1100111 = JALR
            7'b0010011, 7'b0000011, 7'b1100111: begin
                // Top 12 bits of instruction, sign-extended to 32 bits
                imm = {{20{inst[31]}}, inst[31:20]}; // shamt???
            end

            // S-Type:
            // All the following instructions have opcode = 0100011: SB, SH, SW
            7'b0100011: begin
                // The immediate is split between the top 7 bits and bottom 5 bits
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            // B-Type:
            // All the following instructions have opcode = b1100011: BEQ, BNE, BLT, BGE, BLTU, BGEU
            7'b1100011: begin
                // Scrambled heavily. Note the implied 0 at the very end!
                imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            end

            // U-Type:
            // Opcode 0110111 = LUI
            // Opcode 0010111 = AUIPC
            7'b0110111, 7'b0010111: begin
                // 20 bits placed at the top, lower 12 bits filled with 0
                imm = {inst[31:12], 12'b0};
            end

            // J-Type:
            // Opcode 1101111 = JAL
            7'b1101111: begin
                // Scrambled 20-bit immediate. Implied 0 at the end.
                imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            end

            // Default fallback (R-Type or invalid opcode)
            default: begin
                imm = 32'b0;
            end
        endcase
    end

endmodule
