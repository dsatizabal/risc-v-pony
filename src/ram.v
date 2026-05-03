`default_nettype none

module ram (
    input  wire        clk,
    input  wire [3:0]  we,         // UPDATED: Now a 4-bit Write Enable Mask!
    input  wire [31:0] addr,       // Memory Address
    input  wire [31:0] write_data, // Data to save
    output wire [31:0] read_data   // Data loaded
);
    reg [31:0] memory [0:31];

    assign read_data = memory[addr[6:2]];

    // Synchronous Write Logic with Byte-Lane Masking
    always @(posedge clk) begin
        // Instead of writing all 32 bits at once, we independently check
        // each of the 4 Write Enable bits to see which bytes get updated.
        if (we[0]) memory[addr[6:2]][7:0]   <= write_data[7:0];
        if (we[1]) memory[addr[6:2]][15:8]  <= write_data[15:8];
        if (we[2]) memory[addr[6:2]][23:16] <= write_data[23:16];
        if (we[3]) memory[addr[6:2]][31:24] <= write_data[31:24];
    end

endmodule