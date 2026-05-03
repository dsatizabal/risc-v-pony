/*
 * Tang Nano 20K top wrapper for RiscV Pony ROM bring-up.
 *
 * First hardware experiment:
 *   - 27 MHz board clock
 *   - internal power-on reset counter
 *   - Pony instruction fetch from FPGA ROM
 *   - Pony MMIO out_port[5:0] drives the six onboard LEDs
 *
 * No external SPI flash is used in this first experiment.
 */

`default_nettype none

module tang_nano_20k_pony_top (
    input  wire       clk,
    output wire [5:0] led
);

    reg [7:0] reset_counter = 8'd0;

    wire rst_n;
    assign rst_n = &reset_counter;

    always @(posedge clk) begin
        if (!rst_n) begin
            reset_counter <= reset_counter + 8'd1;
        end
    end

    wire [7:0] out_port;
    wire [7:0] in_port;

    assign in_port = 8'h00;

    core_rom processor (
        .clk(clk),
        .rst_n(rst_n),
        .out_port(out_port),
        .in_port(in_port)
    );

    // Tang Nano 20K onboard LEDs are active-low.
    assign led = ~out_port[5:0];

endmodule
