/*
 * Pony simple VGA peripheral.
 *
 * This is intentionally autonomous for the first integration step:
 * the CPU only selects whether this peripheral owns uo_out through
 * io_mode[0]. Later we can add MMIO-controlled drawing registers.
 *
 * Output mapping matches the Tiny VGA PMOD example:
 *   uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
 */

`default_nettype none

module vga_peripheral (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enabled,
    output wire [7:0] vga_out
);

    wire hsync;
    wire vsync;
    wire display_on;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    reg [1:0] red;
    reg [1:0] green;
    reg [1:0] blue;

    hvsync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // Simple built-in test pattern:
    //   - black when disabled or outside active video
    //   - vertical color bars during active video
    // This is only to validate the VGA PMOD path; it is not the final renderer.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            red   <= 2'b00;
            green <= 2'b00;
            blue  <= 2'b00;
        end else begin
            if (!enabled || !display_on) begin
                red   <= 2'b00;
                green <= 2'b00;
                blue  <= 2'b00;
            end else begin
                case (pix_x[9:7])
                    3'd0: begin red <= 2'b11; green <= 2'b00; blue <= 2'b00; end
                    3'd1: begin red <= 2'b00; green <= 2'b11; blue <= 2'b00; end
                    3'd2: begin red <= 2'b00; green <= 2'b00; blue <= 2'b11; end
                    3'd3: begin red <= 2'b11; green <= 2'b11; blue <= 2'b00; end
                    3'd4: begin red <= 2'b11; green <= 2'b00; blue <= 2'b11; end
                    3'd5: begin red <= 2'b00; green <= 2'b11; blue <= 2'b11; end
                    3'd6: begin red <= 2'b11; green <= 2'b11; blue <= 2'b11; end
                    default: begin red <= 2'b01; green <= 2'b01; blue <= 2'b01; end
                endcase
            end
        end
    end

    assign vga_out = {hsync, blue[0], green[0], red[0], vsync, blue[1], green[1], red[1]};

endmodule

`default_nettype wire
