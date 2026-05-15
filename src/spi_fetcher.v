`default_nettype none

module spi_fetcher #(
    parameter [7:0] CS_SETUP_CYCLES = 8'd1,
    parameter [7:0] CS_HOLD_CYCLES  = 8'd1
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        fetch_req,
    input  wire [31:0] pc_addr,

    output reg         spi_cs_n,
    output reg         spi_sck,
    output reg         spi_mosi,
    input  wire        spi_miso,

    output reg  [31:0] inst_data,
    output reg         fetch_done
);

    localparam [3:0]
        STATE_IDLE       = 4'd0,
        STATE_CS_SETUP   = 4'd1,
        STATE_LOW_PHASE  = 4'd2,
        STATE_HIGH_PHASE = 4'd3,
        STATE_CS_HOLD    = 4'd4,
        STATE_DONE       = 4'd5;

    reg [3:0]  state;
    reg [7:0]  delay_counter;

    reg [5:0]  bit_counter;
    reg [63:0] tx_shift;
    reg [31:0] rx_shift;

    wire [31:0] rx_shift_next;
    assign rx_shift_next = {rx_shift[30:0], spi_miso};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            delay_counter <= 8'd0;
            bit_counter   <= 6'd0;

            tx_shift      <= 64'd0;
            rx_shift      <= 32'd0;

            spi_cs_n      <= 1'b1;
            spi_sck       <= 1'b0;
            spi_mosi      <= 1'b0;

            inst_data     <= 32'd0;
            fetch_done    <= 1'b0;
        end else begin
            case (state)

                STATE_IDLE: begin
                    spi_cs_n      <= 1'b1;
                    spi_sck       <= 1'b0;
                    spi_mosi      <= 1'b0;
                    fetch_done    <= 1'b0;
                    delay_counter <= 8'd0;

                    if (fetch_req) begin
                        tx_shift    <= {8'h03, pc_addr[23:0], 32'h00000000};
                        rx_shift    <= 32'd0;
                        bit_counter <= 6'd63;

                        spi_cs_n    <= 1'b0;
                        spi_sck     <= 1'b0;
                        spi_mosi    <= 1'b0;

                        state       <= STATE_CS_SETUP;
                    end
                end

                /*
                 * Give the Flash a clean CS-low setup time before the
                 * first clock edge.
                 */
                STATE_CS_SETUP: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    if (delay_counter >= CS_SETUP_CYCLES) begin
                        delay_counter <= 8'd0;
                        state         <= STATE_LOW_PHASE;
                    end else begin
                        delay_counter <= delay_counter + 8'd1;
                    end
                end

                STATE_LOW_PHASE: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b0;
                    spi_mosi <= tx_shift[63];

                    state    <= STATE_HIGH_PHASE;
                end

                STATE_HIGH_PHASE: begin
                    spi_cs_n <= 1'b0;
                    spi_sck  <= 1'b1;
                    spi_mosi <= tx_shift[63];

                    tx_shift <= {tx_shift[62:0], 1'b0};

                    if (bit_counter <= 6'd31) begin
                        rx_shift <= rx_shift_next;
                    end

                    if (bit_counter == 6'd0) begin
                        delay_counter <= 8'd0;
                        state         <= STATE_CS_HOLD;
                    end else begin
                        bit_counter <= bit_counter - 6'd1;
                        state       <= STATE_LOW_PHASE;
                    end
                end

                STATE_CS_HOLD: begin
                    spi_sck  <= 1'b0;
                    spi_mosi <= 1'b0;

                    if (delay_counter >= CS_HOLD_CYCLES) begin
                        delay_counter <= 8'd0;
                        spi_cs_n      <= 1'b1;
                        state         <= STATE_DONE;
                    end else begin
                        spi_cs_n      <= 1'b0;
                        delay_counter <= delay_counter + 8'd1;
                    end
                end

                STATE_DONE: begin
                    spi_cs_n   <= 1'b1;
                    spi_sck    <= 1'b0;
                    spi_mosi   <= 1'b0;

                    inst_data <= {
                        rx_shift[7:0],
                        rx_shift[15:8],
                        rx_shift[23:16],
                        rx_shift[31:24]
                    };

                    fetch_done <= 1'b1;
                    state      <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end

            endcase
        end
    end

endmodule
