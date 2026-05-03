`default_nettype none

module control_unit (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_bit5,

    input  wire       zero,
    input  wire       fetch_done,
    input  wire       alu_result_0,

    output reg        fetch_req,
    output reg        pc_en,
    output reg  [1:0] pc_src,

    output reg        reg_we,
    output reg        alu_src_b,
    output reg  [3:0] alu_ctrl,

    output reg        mem_we,
    output reg  [2:0] wb_sel,

    output reg  [1:0] mem_size,    // 00 = Byte, 01 = Halfword, 10 = Word
    output reg        mem_unsigned // 1 = Zero extend, 0 = Sign extend
);

    localparam STATE_FETCH      = 2'b00;
    localparam STATE_WAIT       = 2'b01;
    localparam STATE_EXECUTE    = 2'b10;
    localparam STATE_HALT       = 2'b11;

    reg [1:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_FETCH;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state      = state;
        fetch_req       = 1'b0;
        pc_en           = 1'b0;
        pc_src          = 2'b00;
        reg_we          = 1'b0;
        alu_src_b       = 1'b0;
        alu_ctrl        = 4'b0000;
        mem_we          = 1'b0;
        wb_sel          = 3'b000;

        // Defaults for memory
        mem_size     = 2'b10; // Default to Word (32 bits)
        mem_unsigned = 1'b0;  // Default to Signed

        case (state)
            STATE_FETCH: begin
                fetch_req       = 1'b1;
                next_state      = STATE_WAIT;
            end

            STATE_WAIT: begin
                if (fetch_done) begin
                    next_state = STATE_EXECUTE;
                end
            end

            STATE_EXECUTE: begin
                next_state = STATE_FETCH;
                pc_en      = 1'b1;

                case (opcode)
                    // R-Type
                    7'b0110011: begin
                        reg_we      = 1'b1;
                        alu_src_b   = 1'b0;
                        case (funct3)
                            3'b000: alu_ctrl = (funct7_bit5) ? 4'b1000 : 4'b0000;   // SUB & ADD
                            3'b001: alu_ctrl = 4'b0001;                             // SLL
                            3'b010: alu_ctrl = 4'b0010;                             // SLT
                            3'b011: alu_ctrl = 4'b0011;                             // SLTU
                            3'b100: alu_ctrl = 4'b0100;                             // XOR
                            3'b101: alu_ctrl = (funct7_bit5) ? 4'b1101 : 4'b0101;   // SRL & SRA
                            3'b110: alu_ctrl = 4'b0110;                             // OR
                            3'b111: alu_ctrl = 4'b0111;                             // AND
                            default: alu_ctrl = 4'b0000;
                        endcase
                    end

                    // I-Type
                    7'b0010011: begin
                        reg_we      = 1'b1;
                        alu_src_b   = 1'b1;
                        case (funct3)
                            3'b000: alu_ctrl = 4'b0000;                             // ADDI
                            3'b001: alu_ctrl = 4'b0001;                             // SLLI
                            3'b010: alu_ctrl = 4'b0010;                             // SLTI
                            3'b011: alu_ctrl = 4'b0011;                             // SLTIU
                            3'b100: alu_ctrl = 4'b0100;                             // XORI
                            3'b101: alu_ctrl = (funct7_bit5) ? 4'b1101 : 4'b0101;   // SRLI & SRAI
                            3'b110: alu_ctrl = 4'b0110;                             // ORI
                            3'b111: alu_ctrl = 4'b0111;                             // ANDI
                            default: alu_ctrl = 4'b0000;
                        endcase
                    end

                    // B-Type (Branches)
                    7'b1100011: begin
                        reg_we      = 1'b0;
                        alu_src_b   = 1'b0;
                        case (funct3)
                            3'b000: begin // BEQ
                                alu_ctrl    = 4'b1000;
                                pc_src      = zero ? 2'b01 : 2'b00;
                            end
                            3'b001: begin // BNE
                                alu_ctrl    = 4'b1000;
                                pc_src      = !zero ? 2'b01 : 2'b00;
                            end
                            3'b100: begin // BLT
                                alu_ctrl    = 4'b0010;
                                pc_src      = alu_result_0 ? 2'b01 : 2'b00;
                            end
                            3'b101: begin // BGE
                                alu_ctrl    = 4'b0010;
                                pc_src      = !alu_result_0 ? 2'b01 : 2'b00;
                            end
                            3'b110: begin // BLTU
                                alu_ctrl    = 4'b0011;
                                pc_src      = alu_result_0 ? 2'b01 : 2'b00;
                            end
                            3'b111: begin // BGEU
                                alu_ctrl    = 4'b0011;
                                pc_src      = !alu_result_0 ? 2'b01 : 2'b00;
                            end
                            default: pc_src = 2'b00;
                        endcase
                    end

                    // ----------------------------------------
                    // Load (LW, LH, LB, LHU, LBU)
                    // ----------------------------------------
                    7'b0000011: begin
                        reg_we          = 1'b1;
                        alu_src_b       = 1'b1;
                        alu_ctrl        = 4'b0000;
                        wb_sel          = 3'b001;
                        mem_size        = funct3[1:0];  // 00=B, 01=H, 10=W
                        mem_unsigned    = funct3[2];    // 1=Unsigned (LBU/LHU), 0=Signed (LB/LH)
                    end

                    // ----------------------------------------
                    // Store (SW, SH, SB)
                    // ----------------------------------------
                    7'b0100011: begin
                        reg_we      = 1'b0;
                        alu_src_b   = 1'b1;
                        alu_ctrl    = 4'b0000;
                        mem_we      = 1'b1;
                        mem_size    = funct3[1:0];      // 00=B, 01=H, 10=W
                    end

                    // JAL
                    7'b1101111: begin
                        reg_we = 1'b1;
                        wb_sel = 3'b010;
                        pc_src = 2'b01;
                    end

                    // JALR
                    7'b1100111: begin
                        reg_we      = 1'b1;
                        wb_sel      = 3'b010;
                        alu_src_b   = 1'b1;
                        alu_ctrl    = 4'b0000;
                        pc_src      = 2'b10;
                    end

                    // LUI
                    7'b0110111: begin
                        reg_we = 1'b1;
                        wb_sel = 3'b011;
                    end

                    // AUIPC
                    7'b0010111: begin
                        reg_we = 1'b1;
                        wb_sel = 3'b100;
                    end

                    // FENCE
                    // In this simple single-hart, in-order Pony core there is
                    // no cache, store buffer, or out-of-order memory system.
                    // Treat FENCE as a legal NOP and simply advance PC.
                    7'b0001111: begin
                        reg_we  = 1'b0;
                        mem_we  = 1'b0;
                        pc_src  = 2'b00;
                    end

                    // SYSTEM
                    // Minimal embedded behavior:
                    //   ECALL  -> halt
                    //   EBREAK -> halt
                    //
                    // Both ECALL and EBREAK use opcode 1110011 and funct3 000.
                    // This intentionally does not implement CSRs/trap vectors.
                    7'b1110011: begin
                        reg_we  = 1'b0;
                        mem_we  = 1'b0;
                        pc_en   = 1'b0;
                        pc_src  = 2'b00;

                        if (funct3 == 3'b000) begin
                            next_state = STATE_HALT;
                        end
                    end

                    default: ;
                endcase
            end

            STATE_HALT: begin
                fetch_req   = 1'b0;
                pc_en       = 1'b0;
                reg_we      = 1'b0;
                mem_we      = 1'b0;
                next_state  = STATE_HALT;
            end
        endcase
    end
endmodule
