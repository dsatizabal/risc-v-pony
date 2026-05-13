/*
 * Tang Nano 20K Pony External SPI Flash Top
 * for TinyTapeout-style project.v interface.
 */

`default_nettype none

module riscv_pony_on_fpga_top (
    input  wire       clk,
    input  wire       rst_n,

    output wire [5:0] led,

    output wire       flash_cs_n,
    output wire       flash_mosi,
    input  wire       flash_miso,
    output wire       flash_sck,

    output wire       flash_wp_n,
    output wire       flash_hold_n,
    output wire       ram_a_cs_n,
    output wire       ram_b_cs_n
);

    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    /*
     * For first test, no external inputs.
     */
    assign ui_in = 8'h00;

    /*
     * TinyTapeout-style project.
     */
    tt_um_dsp_riscv_pony uut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (!rst_n)
    );

    /*
     * Output LEDs from uo_out.
     * Adjust this if your project exposes out_port somewhere else.
     */
    assign led = ~uo_out[5:0];

    /*
     * Feed external Flash MISO into uio[2].
     */
    assign uio_in[0] = 1'b1;        // CS input unused
    assign uio_in[1] = 1'b1;        // MOSI input unused
    assign uio_in[2] = 1'b1;        // SCK input unused
    assign uio_in[3] = flash_miso;  // MISO / SD1
    assign uio_in[4] = 1'b1;        // WP input high
    assign uio_in[5] = 1'b1;        // HOLD input high
    assign uio_in[6] = 1'b1;        // RAM A CS input high
    assign uio_in[7] = 1'b1;        // RAM B CS input high

    /*
     * Drive physical PMOD pins from uio_out.
     *
     * For single-bit SPI:
     *   uio[0] Flash CS  output
     *   uio[1] MOSI      output
     *   uio[2] MISO      input
     *   uio[3] SCK       output
     *
     * But for this FPGA wrapper, we directly tie WP/HOLD/RAM CS high.
     */
    assign flash_cs_n = uio_out[0];
    assign flash_sck  = uio_out[1];
    assign flash_mosi = uio_out[2];

    assign flash_wp_n   = 1'b1;
    assign flash_hold_n = 1'b1;
    assign ram_a_cs_n   = 1'b1;
    assign ram_b_cs_n   = 1'b1;

endmodule

`default_nettype wire
