module alu (
    input  wire [31:0] a,          // Operand A
    input  wire [31:0] b,          // Operand B
    input  wire [3:0]  alu_ctrl,   // Operation selector
    output reg  [31:0] result,     // Calculation result
    output wire        zero        // Zero flag (1 if result is 0)
);

    assign zero = (result == 32'b0);

    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a + b;                                    // ADD
            4'b1000: result = a - b;                                    // SUB
            4'b0001: result = a << b[4:0];                              // SLL (Shift Left Logical)
            4'b0010: result = $signed(a) < $signed(b) ? 32'd1 : 32'd0;  // SLT (Signed Compare)
            4'b0011: result = a < b ? 32'd1 : 32'd0;                    // SLTU (Unsigned Compare)
            4'b0100: result = a ^ b;                                    // XOR
            4'b0101: result = a >> b[4:0];                              // SRL (Shift Right Logical)
            4'b1101: result = $signed(a) >>> b[4:0];                    // SRA (Shift Right Arithmetic)
            4'b0110: result = a | b;                                    // OR
            4'b0111: result = a & b;                                    // AND
            default: result = 32'b0;                                    // Default fallback
        endcase
    end

endmodule
