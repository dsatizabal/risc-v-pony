/*
 * JEDEC ID Reader for SPI Flash
 *
 * Purpose:
 *   Minimal Tang Nano / FPGA-side SPI test.
 *
 *   Sends command 0x9F over standard 1-bit SPI mode 0 and reads
 *   three JEDEC ID bytes from the external Flash.
 *
 * Expected for your PMOD Flash:
 *
 *   EF 70 18
 *
 * Display format:
 *
 *   led_pattern[3:0] = current hex nibble
 *   led_pattern[5:4] = byte marker
 *
 * Display sequence:
 *
 *   separator
 *   ID byte 0 high nibble
 *   ID byte 0 low  nibble
 *   ID byte 1 high nibble
 *   ID byte 1 low  nibble
 *   ID byte 2 high nibble
 *   ID byte 2 low  nibble
 *   blank separator
 *
 * Notes:
 *   - Uses SPI mode 0:
 *       SCK idle low
 *       MOSI changes while SCK is low
 *       MISO sampled while SCK is high
 *
 *   - This module does NOT use QSPI.
 *   - The QE bit may be enabled in the Flash, but command 0x9F is still
 *     a normal 1-bit SPI command.
 */

`default_nettype none

module jedec_id_reader #(
    parameter [31:0] DISPLAY_DELAY_CYCLES = 32'd1_000_000,
    parameter [7:0]  CS_SETUP_CYCLES      = 8'd16,
    parameter [7:0]  CS_HOLD_CYCLES       = 8'd16
) (
    input  wire       clk,
    input  wire       rst_n,

    output reg        spi_cs_n,
    output reg        spi_sck,
    output reg        spi_mosi,
    input  wire       spi_miso,

    output reg [5:0]  led_pattern
);

    localparam [7:0] CMD_JEDEC_ID = 8'h9F;

    localparam [3:0]
        STATE_RESET_WAIT     = 4'd0,
        STATE_CS_ASSERT      = 4'd1,
        STATE_SEND_CMD_LOW   = 4'd2,
        STATE_SEND_CMD_HIGH  = 4'd3,
        STATE_READ_LOW       = 4'd4,
        STATE_READ_HIGH      = 4'd5,
        STATE_CS_HOLD        = 4'd6,
        STATE_LATCH_RESULT   = 4'd7,
        STATE_DISPLAY        = 4'd8;

    reg [3:0]  state;

    reg [7:0]  small_counter;
    reg [2:0]  cmd_bit_index;
    reg [4:0]  read_bit_index;

    reg [23:0] rx_shift;
    reg [23:0] jedec_id;

    reg [31:0] display_counter;
    reg [2:0]  display_step;

    wire [23:0] rx_shift_next;
    assign rx_shift_next = {rx_shift[22:0], spi_miso};

    function [3:0] selected_nibble;
        input [2:0]  step;
        input [23:0] id_value;
        begin
            case (step)
                3'd1: selected_nibble = id_value[23:20]; // byte 0 high
                3'd2: selected_nibble = id_value[19:16]; // byte 0 low
                3'd3: selected_nibble = id_value[15:12]; // byte 1 high
                3'd4: selected_nibble = id_value[11:8];  // byte 1 low
                3'd5: selected_nibble = id_value[7:4];   // byte 2 high
                3'd6: selected_nibble = id_value[3:0];   // byte 2 low
                default: selected_nibble = 4'h0;
            endcase
        end
    endfunction

    function [1:0] selected_marker;
        input [2:0] step;
        begin
            case (step)
                3'd1,
                3'd2: selected_marker = 2'b00; // byte 0

                3'd3,
                3'd4: selected_marker = 2'b01; // byte 1

                3'd5,
                3'd6: selected_marker = 2'b10; // byte 2

                default: selected_marker = 2'b11; // separator
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= STATE_RESET_WAIT;

            spi_cs_n        <= 1'b1;
            spi_sck         <= 1'b0;
            spi_mosi        <= 1'b0;

            small_counter   <= 8'd0;
            cmd_bit_index   <= 3'd0;
            read_bit_index  <= 5'd0;

            rx_shift        <= 24'd0;
            jedec_id        <= 24'd0;

            display_counter <= 32'd0;
            display_step    <= 3'd0;
            led_pattern     <= 6'b000000;
        end else begin
            case (state)

                // Give the external Flash a short quiet period after reset.
                STATE_RESET_WAIT: begin
                    spi_cs_n  <= 1'b1;
                    spi_sck   <= 1'b0;
                    spi_mosi  <= 1'b0;

                    led_pattern <= 6'b000001; // small "alive" marker

                    if (small_counter >= CS_SETUP_CYCLES) begin
                        small_counter <= 8'd0;
                        state         <= STATE_CS_ASSERT;
                    end else begin
                        small_counter <= small_counter + 8'd1;
                    end
                end

                // Assert CS and wait a few cycles before starting SCK.
                STATE_CS_ASSERT: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    if (small_counter >= CS_SETUP_CYCLES) begin
                        small_counter  <= 8'd0;
                        cmd_bit_index  <= 3'd0;
                        read_bit_index <= 5'd0;
                        rx_shift       <= 24'd0;
                        state          <= STATE_SEND_CMD_LOW;
                    end else begin
                        small_counter <= small_counter + 8'd1;
                    end
                end

                // SPI mode 0:
                // SCK low phase: prepare MOSI bit.
                STATE_SEND_CMD_LOW: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b0;
                    spi_mosi <= CMD_JEDEC_ID[7 - cmd_bit_index];

                    state <= STATE_SEND_CMD_HIGH;
                end

                // SCK high phase: Flash samples MOSI.
                STATE_SEND_CMD_HIGH: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b1;
                    spi_mosi <= CMD_JEDEC_ID[7 - cmd_bit_index];

                    if (cmd_bit_index == 3'd7) begin
                        cmd_bit_index <= 3'd0;
                        state         <= STATE_READ_LOW;
                    end else begin
                        cmd_bit_index <= cmd_bit_index + 3'd1;
                        state         <= STATE_SEND_CMD_LOW;
                    end
                end

                // Read phase low: keep MOSI low/don't-care.
                // Flash prepares next MISO bit after clock edge transitions.
                STATE_READ_LOW: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    state <= STATE_READ_HIGH;
                end

                // Read phase high: sample MISO.
                STATE_READ_HIGH: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b1;
                    spi_mosi <= 1'b0;

                    rx_shift <= rx_shift_next;

                    if (read_bit_index == 5'd23) begin
                        read_bit_index <= 5'd0;
                        small_counter  <= 8'd0;
                        jedec_id       <= rx_shift_next;
                        state          <= STATE_CS_HOLD;
                    end else begin
                        read_bit_index <= read_bit_index + 5'd1;
                        state          <= STATE_READ_LOW;
                    end
                end

                // End transaction cleanly.
                STATE_CS_HOLD: begin
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    if (small_counter >= CS_HOLD_CYCLES) begin
                        small_counter <= 8'd0;
                        spi_cs_n      <= 1'b1;
                        state         <= STATE_LATCH_RESULT;
                    end else begin
                        spi_cs_n      <= 1'b0;
                        small_counter <= small_counter + 8'd1;
                    end
                end

                STATE_LATCH_RESULT: begin
                    spi_cs_n        <= 1'b1;
                    spi_sck         <= 1'b0;
                    spi_mosi        <= 1'b0;

                    display_counter <= 32'd0;
                    display_step    <= 3'd0;
                    led_pattern     <= 6'b111111; // separator: all LEDs on

                    state           <= STATE_DISPLAY;
                end

                STATE_DISPLAY: begin
                    spi_cs_n <= 1'b1;
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    case (display_step)
                        3'd0: begin
                            // Start separator: all LEDs on
                            led_pattern <= 6'b111111;
                        end

                        3'd1,
                        3'd2,
                        3'd3,
                        3'd4,
                        3'd5,
                        3'd6: begin
                            led_pattern <= {
                                selected_marker(display_step),
                                selected_nibble(display_step, jedec_id)
                            };
                        end

                        3'd7: begin
                            // End separator: all LEDs off
                            led_pattern <= 6'b000000;
                        end

                        default: begin
                            led_pattern <= 6'b000000;
                        end
                    endcase

                    if (display_counter >= DISPLAY_DELAY_CYCLES) begin
                        display_counter <= 32'd0;
                        display_step    <= display_step + 3'd1;
                    end else begin
                        display_counter <= display_counter + 32'd1;
                    end
                end

                default: begin
                    state <= STATE_RESET_WAIT;
                end

            endcase
        end
    end

endmodule