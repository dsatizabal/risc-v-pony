`default_nettype none
`timescale 1ns/1ps

module tb;
    // Clock and Reset
    reg clk;
    reg rst_n;

    // SPI Pins
    wire spi_cs_n;
    wire spi_sck;
    wire spi_mosi;
    reg  spi_miso;

    // The Outer World Interface
    wire    [7:0] out_port;
    reg     [7:0] in_port;

    // Capture the bidirectional IO bus from the DUT
    wire [7:0] uio_out_wire;

    // Unpack SPI output signals from the DUT's uio_out bus
    // uio_out[0] = spi_cs_n, [1] = spi_sck, [2] = spi_mosi  (matches project.v)
    assign spi_cs_n = uio_out_wire[0];
    assign spi_sck  = uio_out_wire[1];
    assign spi_mosi = uio_out_wire[2];

`ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
`endif

    tt_um_dsp_riscv_pony uut (
      // Include power ports for the Gate Level test:
    `ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
    `endif

        .ui_in(in_port),
        .uo_out(out_port),
        // spi_miso drives uio_in[3] (matches project.v .spi_miso(uio_in[3]))
        .uio_in({4'b0000, spi_miso, 3'b000}),
        .uio_out(uio_out_wire),
        .uio_oe(),
        .ena(1'b1),
        .clk(clk),
        .rst_n(rst_n)
    );

    // Dump waves for debugging
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end
endmodule
