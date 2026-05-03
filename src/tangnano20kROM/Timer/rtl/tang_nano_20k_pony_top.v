/*
 * Tang Nano 20K top wrapper for RiscV Pony ROM + timer demo.
 *
 * Hardware experiment:
 *   - 27 MHz board clock
 *   - internal power-on reset counter
 *   - Pony instruction fetch from FPGA ROM
 *   - Pony MMIO timer at 0x88
 *   - firmware uses timer, not a software delay loop, to pace LEDs
 *   - btn[0] changes LED chase direction
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

    // Tang Nano onboard buttons are active-low. Expose active-high to Pony.
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
