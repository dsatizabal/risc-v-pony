/*
 * SPI Flash LED Demo Core
 *
 * Standalone hardware smoke test for the RiscV Pony SPI fetch path.
 *
 * This module reuses spi_fetcher.v exactly like Pony does:
 *   - request a 32-bit fetch
 *   - wait for fetch_done
 *   - receive inst_data
 *
 * But here inst_data is treated as four raw bytes read from SPI Flash.
 * Each byte is shown on the Tang Nano LEDs with a delay between bytes.
 *
 * Because spi_fetcher.v assembles real little-endian flash bytes into a
 * CPU-facing word, the display order is:
 *
 *   inst_data[7:0]
 *   inst_data[15:8]
 *   inst_data[23:16]
 *   inst_data[31:24]
 *
 * If Flash contains bytes:
 *
 *   01 02 04 08
 *
 * the LEDs should show:
 *
 *   01, then 02, then 04, then 08
 */

`default_nettype none

module spi_flash_led_demo_core #(
    parameter ADDR_LIMIT = 24'h000040
) (
    input  wire       clk,
    input  wire       rst_n,

    output wire       spi_cs_n,
    output wire       spi_sck,
    output wire       spi_mosi,
    input  wire       spi_miso,

    output reg  [5:0] led_pattern
);

    localparam STATE_FETCH_REQ  = 3'd0;
    localparam STATE_WAIT_FETCH = 3'd1;
    localparam STATE_SHOW_BYTE0 = 3'd2;
    localparam STATE_SHOW_BYTE1 = 3'd3;
    localparam STATE_SHOW_BYTE2 = 3'd4;
    localparam STATE_SHOW_BYTE3 = 3'd5;
    localparam STATE_DELAY      = 3'd6;
    localparam STATE_NEXT       = 3'd7;

    reg [2:0]  state;
    reg [2:0]  return_state;

    reg        fetch_req;
    wire       fetch_done;
    wire [31:0] inst_data;

    reg [31:0] current_word;
    reg [31:0] flash_addr;
    reg [31:0] delay_counter;

    spi_fetcher fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_req(fetch_req),
        .pc_addr(flash_addr),
        .spi_cs_n(spi_cs_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .inst_data(inst_data),
        .fetch_done(fetch_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_FETCH_REQ;
            return_state  <= STATE_SHOW_BYTE0;
            fetch_req     <= 1'b0;
            current_word  <= 32'd0;
            flash_addr    <= 32'd0;
            delay_counter <= 32'd0;
            led_pattern   <= 6'b000001;
        end else begin
            case (state)
                STATE_FETCH_REQ: begin
                    fetch_req <= 1'b1;
                    state     <= STATE_WAIT_FETCH;
                end

                STATE_WAIT_FETCH: begin
                    fetch_req <= 1'b0;

                    if (fetch_done) begin
                        current_word <= inst_data;
                        state        <= STATE_SHOW_BYTE0;
                    end
                end

                STATE_SHOW_BYTE0: begin
                    led_pattern  <= current_word[5:0];
                    return_state <= STATE_SHOW_BYTE1;
                    state        <= STATE_DELAY;
                end

                STATE_SHOW_BYTE1: begin
                    led_pattern  <= current_word[13:8];
                    return_state <= STATE_SHOW_BYTE2;
                    state        <= STATE_DELAY;
                end

                STATE_SHOW_BYTE2: begin
                    led_pattern  <= current_word[21:16];
                    return_state <= STATE_SHOW_BYTE3;
                    state        <= STATE_DELAY;
                end

                STATE_SHOW_BYTE3: begin
                    led_pattern  <= current_word[29:24];
                    return_state <= STATE_NEXT;
                    state        <= STATE_DELAY;
                end

                STATE_DELAY: begin
                    if (delay_counter + 1'b1 >= 32'd1_000_000) begin
                        delay_counter <= 32'b0;
                        state         <= return_state;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                STATE_NEXT: begin
                    if (flash_addr >= ADDR_LIMIT - 32'd4) begin
                        flash_addr <= 32'd0;
                    end else begin
                        flash_addr <= flash_addr + 32'd4;
                    end

                    state <= STATE_FETCH_REQ;
                end

                default: begin
                    state <= STATE_FETCH_REQ;
                end
            endcase
        end
    end

endmodule
