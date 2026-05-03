`default_nettype none

module program_counter (
    input  wire        clk,        // System clock
    input  wire        rst_n,      // Active-low reset
    input  wire        pc_en,      // PC Enable: Only update when high, gets enabled from Control Unit
    input  wire [31:0] pc_next,    // The next address to go to

    // The current execution address, this is the actual PC reg and gets its value according to the external sources
    // Default source: PC + 4, Branch: PC + Instruction IMM, ALU result
    output reg  [31:0] pc
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h00000000;
        end else if (pc_en) begin
            pc <= pc_next;
        end
    end

endmodule
