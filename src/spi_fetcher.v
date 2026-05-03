`default_nettype none

module spi_fetcher (
    input  wire        clk,         // System clock
    input  wire        rst_n,       // Active-low reset
    input  wire        fetch_req,   // Control unit request
    input  wire [31:0] pc_addr,     // The 32-bit Program Counter address

    // Physical SPI Pins going to the outside world
    output reg         spi_cs_n,    // Chip Select (Active Low)
    output wire        spi_sck,     // Serial Clock
    output reg         spi_mosi,    // Master Out, Slave In
    input  wire        spi_miso,    // Master In, Slave Out

    // Data returning to the processor
    output reg  [31:0] inst_data,   // The assembled 32-bit instruction
    output reg         fetch_done   // Read cycle terminated
);

    // State machine definitions
    localparam IDLE  = 2'b00;
    localparam SHIFT = 2'b01;
    localparam DONE  = 2'b10;

    reg [1:0]  state, next_state;
    reg [6:0]  bit_counter;         // Counts from 63 down to 0
    reg [63:0] shift_reg;           // Holds the outgoing command+address and incoming data

    // Continuous assignment for the SPI Clock.
    // We only toggle the SPI clock when we are actively shifting data.
    assign spi_sck = (state == SHIFT) ? clk : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            bit_counter <= 7'd0;
            shift_reg   <= 64'd0;
            spi_cs_n    <= 1'b1;
            inst_data   <= 32'd0;
            fetch_done  <= 1'b0;
            spi_mosi    <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    fetch_done <= 1'b0;
                    spi_cs_n   <= 1'b1;

                    if (fetch_req) begin
                        state       <= SHIFT;
                        spi_cs_n    <= 1'b0;
                        bit_counter <= 7'd63; // 64 total bits to transfer

                        // Load the shift register:
                        // [63:56] = 8-bit Read Command (0x03)
                        // [55:32] = 24-bit Address (Bottom 24 bits of PC)
                        // [31:0]  = 32-bit empty space for the incoming instruction
                        shift_reg   <= {8'h03, pc_addr[23:0], 32'h00000000};
                    end
                end

                SHIFT: begin
                    // Output the Most Significant Bit (MSB) to MOSI
                    spi_mosi        <= shift_reg[63];

                    // Shift left by 1, and sample the incoming MISO bit at the bottom
                    shift_reg       <= {shift_reg[62:0], spi_miso};

                    if (bit_counter == 7'd0) begin
                        state       <= DONE;
                    end else begin
                        bit_counter <= bit_counter - 1'b1;
                    end
                end

                DONE: begin
                    // The bottom 32 bits of the shift register now hold our instruction
                    inst_data       <= shift_reg[31:0];
                    fetch_done      <= 1'b1;
                    spi_cs_n        <= 1'b1;
                    state           <= IDLE;
                end

                default: state      <= IDLE;
            endcase
        end
    end

endmodule
