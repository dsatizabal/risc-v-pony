/*
 * RiscV Pony ROM fetcher
 *
 * This module is a temporary FPGA bring-up replacement for spi_fetcher.v.
 * It fetches one 32-bit instruction from a word-addressed ROM initialized
 * with firmware.hex.
 *
 * Addressing:
 *   pc_addr[ROM_ADDR_WIDTH+1:2] selects a 32-bit instruction word.
 *
 * firmware.hex format:
 *   one 32-bit instruction word per line, already assembled as the CPU
 *   expects it, for example:
 *
 *     08000093
 *     00100113
 *
 * This intentionally avoids the real SPI flash byte-order question for
 * the first Tang Nano hardware experiment.
 */

`default_nettype none

module rom_fetcher #(
    parameter ROM_ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fetch_req,
    input  wire [31:0] pc_addr,
    output reg  [31:0] inst_data,
    output reg         fetch_done
);

    localparam ROM_DEPTH = (1 << ROM_ADDR_WIDTH);

    reg [31:0] rom [0:ROM_DEPTH-1];

    wire [ROM_ADDR_WIDTH-1:0] word_addr;
    assign word_addr = pc_addr[ROM_ADDR_WIDTH+1:2];

    initial begin
        $readmemh("firmware.hex", rom);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_data  <= 32'h00000013; // ADDI x0, x0, 0
            fetch_done <= 1'b0;
        end else begin
            fetch_done <= 1'b0;

            if (fetch_req) begin
                inst_data  <= rom[word_addr];
                fetch_done <= 1'b1;
            end
        end
    end

endmodule
