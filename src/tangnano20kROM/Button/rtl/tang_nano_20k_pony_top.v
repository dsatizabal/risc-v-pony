/*
 * Tang Nano 20K top wrapper for RiscV Pony ROM + button input bring-up.
 *
 * Hardware experiment:
 *   - 27 MHz board clock
 *   - internal power-on reset counter
 *   - Pony instruction fetch from FPGA ROM
 *   - Pony MMIO out_port[5:0] drives the six onboard LEDs
 *   - Pony MMIO in_port[1:0] reads the two onboard buttons
 *
 * No external SPI flash is used in this experiment.
 */

`default_nettype none

module tang_nano_20k_pony_top (
    input  wire       clk,
    input  wire [1:0] btn,
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

    /*
     * Tang Nano onboard buttons are normally pulled up and read as 0 when
     * pressed. Expose active-high button bits to Pony firmware:
     *
     *   in_port[0] = 1 when btn[0] is pressed
     *   in_port[1] = 1 when btn[1] is pressed
     */
    assign in_port = {6'b0, ~btn};

    core_rom processor (
        .clk(clk),
        .rst_n(rst_n),
        .out_port(out_port),
        .in_port(in_port)
    );

    // Tang Nano 20K onboard LEDs are active-low.
    assign led = ~out_port[5:0];

endmodule
