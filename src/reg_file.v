`default_nettype none

module regfile (
    input  wire        clk,       // Clock signal
    input  wire        we,        // Write Enable signal
    input  wire [3:0]  rs1_addr,  // Address for Read Port 1
    input  wire [3:0]  rs2_addr,  // Address for Read Port 2
    input  wire [3:0]  rd_addr,   // Address for Write Port
    input  wire [31:0] rd_data,   // Data to be written
    output wire [31:0] rs1_data,  // Data read from Port 1
    output wire [31:0] rs2_data   // Data read from Port 2
);
    reg [31:0] registers [1:15];

    assign rs1_data = (rs1_addr == 4'b0000) ? 32'b0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 4'b0000) ? 32'b0 : registers[rs2_addr];

    always @(posedge clk) begin
        if (we) begin
            if (rd_addr != 4'b0000) begin
                registers[rd_addr] <= rd_data;
            end
        end
    end

endmodule
