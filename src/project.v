/*
 * Copyright (c) 2026 Diego Satizabal
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_dsp_riscv_pony (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  core processor (
      .clk(clk),
      .rst_n(rst_n),
      .spi_cs_n(uio_out[0]),
      .spi_sck(uio_out[1]),
      .spi_mosi(uio_out[2]),
      .spi_miso(uio_in[3]),
      .out_port(uo_out),
      .in_port(ui_in)
  );

  assign uio_out[7:3] = 5'b0;
  assign uio_oe = 8'b0000_0111;

endmodule
