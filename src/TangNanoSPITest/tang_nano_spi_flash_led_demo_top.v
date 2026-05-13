/*
 * Tang Nano 20K SPI Flash LED Demo Top
 *
 * Purpose:
 *   Verify the external QSPI Pmod Flash wiring and the Pony spi_fetcher.v
 *   before connecting the Flash to the full Pony CPU.
 *
 * This uses the Flash in standard 1-bit SPI mode only:
 *
 *   flash_cs_n -> /CS
 *   flash_mosi -> DI / IO0
 *   flash_miso -> DO / IO1
 *   flash_sck  -> CLK
 *
 * The remaining QSPI/Pmod pins are driven high:
 *
 *   flash_wp_n   -> /WP / IO2 high
 *   flash_hold_n -> /HOLD / IO3 high
 *   ram_a_cs_n   -> RAM A disabled
 *   ram_b_cs_n   -> RAM B disabled
 */

`default_nettype none

module tang_nano_spi_flash_led_demo_top (
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

    reg slow_clk;
    reg [7:0] clk_div;


    always @(posedge clk) begin
        if (!rst_n) begin
            slow_clk <= 1'b0;
            clk_div <= 8'd0;
        end else begin
            if (clk_div + 1'b1 >= 13) begin
                clk_div <= 8'd0;
                slow_clk <= ~slow_clk;
            end else begin
                clk_div <= clk_div + 1'b1;
            end
        end
    end

    wire [5:0] led_pattern;

    spi_flash_led_demo_core #(
        .ADDR_LIMIT(24'h000040)
    ) demo (
        .clk(slow_clk),
        .rst_n(rst_n),

        .spi_cs_n(flash_cs_n),
        .spi_sck(flash_sck),
        .spi_mosi(flash_mosi),
        .spi_miso(flash_miso),

        .led_pattern(led_pattern)
    );

    // Tang Nano 20K onboard LEDs are active-low.
    assign led = ~led_pattern;

    // Standard 1-bit SPI mode helpers.
    assign flash_wp_n   = 1'b1;
    assign flash_hold_n = 1'b1;

    // Disable both PSRAM chips on the QSPI Pmod.
    assign ram_a_cs_n = 1'b1;
    assign ram_b_cs_n = 1'b1;

endmodule
