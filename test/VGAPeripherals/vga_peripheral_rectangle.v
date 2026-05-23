/*
 * Pony VGA Peripheral - color bars + one MMIO-controlled filled rectangle
 *
 * Color encoding used by software-facing registers:
 *   color[5:4] = red[1:0]
 *   color[3:2] = green[1:0]
 *   color[1:0] = blue[1:0]
 *
 * Tiny VGA PMOD output packing follows the Uri Shaked TT VGA example:
 *   vga_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
 */

`default_nettype none

module vga_peripheral (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enabled,

    input  wire       rect_enable,
    input  wire [9:0] rect_x,
    input  wire [9:0] rect_y,
    input  wire [9:0] rect_w,
    input  wire [9:0] rect_h,
    input  wire [5:0] rect_color,

    output wire [7:0] vga_out
);

    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    reg [1:0] red;
    reg [1:0] green;
    reg [1:0] blue;

    hvsync_generator vga_sync_gen (
        .clk        (clk),
        .reset      (~rst_n),
        .hsync      (hsync),
        .vsync      (vsync),
        .display_on (video_active),
        .hpos       (pix_x),
        .vpos       (pix_y)
    );

    wire [10:0] rect_x_end = {1'b0, rect_x} + {1'b0, rect_w};
    wire [10:0] rect_y_end = {1'b0, rect_y} + {1'b0, rect_h};

    wire rect_nonzero = (rect_w != 10'd0) && (rect_h != 10'd0);

    wire in_rect = rect_enable && rect_nonzero &&
                   ({1'b0, pix_x} >= {1'b0, rect_x}) &&
                   ({1'b0, pix_x} <  rect_x_end) &&
                   ({1'b0, pix_y} >= {1'b0, rect_y}) &&
                   ({1'b0, pix_y} <  rect_y_end);

    // Simple background color bars. This keeps the old VGA smoke-test useful
    // even before software configures a rectangle.
    reg [5:0] bg_color;
    always @* begin
        if (pix_x < 10'd128) begin
            bg_color = 6'b11_00_00; // red
        end else if (pix_x < 10'd256) begin
            bg_color = 6'b00_11_00; // green
        end else if (pix_x < 10'd384) begin
            bg_color = 6'b00_00_11; // blue
        end else if (pix_x < 10'd512) begin
            bg_color = 6'b11_11_00; // yellow
        end else begin
            bg_color = 6'b11_00_11; // magenta
        end
    end

    wire [5:0] selected_color = in_rect ? rect_color : bg_color;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            red   <= 2'b00;
            green <= 2'b00;
            blue  <= 2'b00;
        end else begin
            if (enabled && video_active) begin
                red   <= selected_color[5:4];
                green <= selected_color[3:2];
                blue  <= selected_color[1:0];
            end else begin
                red   <= 2'b00;
                green <= 2'b00;
                blue  <= 2'b00;
            end
        end
    end

    assign vga_out = {hsync, blue[0], green[0], red[0], vsync, blue[1], green[1], red[1]};

endmodule

`default_nettype wire
