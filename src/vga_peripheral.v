/*
 * Pony VGA peripheral with register-controlled primitive object table.
 *
 * This version fixes an important simulation/synthesis robustness issue:
 * the renderer functions now receive pix_x/pix_y as explicit inputs.
 *
 * Some Verilog simulators do not reliably include signals referenced only
 * inside functions in an always @* sensitivity list. In the previous version,
 * render_color could remain stuck at the background color even though object
 * memory had been programmed correctly. Passing px/py explicitly forces the
 * renderer combinational block to reevaluate as the beam moves.
 *
 * Supported primitive types:
 *   00 = rectangle
 *   01 = octagon / cheap circle approximation
 *   10 = limited line: horizontal, vertical, +45, -45 degrees
 *   11 = unused / inactive
 *
 * Object WORD0:
 *   [31:30] primitive type
 *   [29]    enable
 *   [28:19] x0 / center_x
 *   [18:10] y0 / center_y
 *   [9:0]   radius for octagon, x1 for line, unused for rect
 *
 * WORD1 rectangle:
 *   [31:22] width
 *   [21:13] height
 *   [12:7]  color RGB222
 *
 * WORD1 octagon:
 *   [12:7]  color RGB222
 *
 * WORD1 line:
 *   [31:23] y1
 *   [12:7]  color RGB222
 *
 * Priority:
 *   Higher object index wins.
 *
 * Output mapping:
 *   vga_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
 */

`default_nettype none

module vga_peripheral #(
    parameter integer NUM_OBJECTS = 12
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enabled,

    input  wire [5:0]  bg_color,

    input  wire [3:0]  obj_index,
    input  wire [31:0] obj_word0,
    input  wire [31:0] obj_word1,
    input  wire        obj_write,
    output reg         obj_write_ack,

    output wire [7:0]  vga_out
);

    localparam [1:0] OBJ_RECT    = 2'b00;
    localparam [1:0] OBJ_OCTAGON = 2'b01;
    localparam [1:0] OBJ_LINE    = 2'b10;

    localparam [10:0] LINE_TOLERANCE = 11'd1;

    wire hsync;
    wire vsync;
    wire display_on;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    reg [1:0] red;
    reg [1:0] green;
    reg [1:0] blue;

    reg [31:0] obj_word0_mem [0:NUM_OBJECTS-1];
    reg [31:0] obj_word1_mem [0:NUM_OBJECTS-1];

    integer reset_i;

    hvsync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            obj_write_ack <= 1'b0;

            for (reset_i = 0; reset_i < NUM_OBJECTS; reset_i = reset_i + 1) begin
                obj_word0_mem[reset_i] <= 32'd0;
                obj_word1_mem[reset_i] <= 32'd0;
            end
        end else begin
            obj_write_ack <= 1'b0;

            if (obj_write) begin
                if (obj_index < NUM_OBJECTS[3:0] || NUM_OBJECTS >= 16) begin
                    obj_word0_mem[obj_index] <= obj_word0;
                    obj_word1_mem[obj_index] <= obj_word1;
                    obj_write_ack            <= 1'b1;
                end
            end
        end
    end

    function [9:0] min10;
        input [9:0] a;
        input [9:0] b;
        begin
            min10 = (a < b) ? a : b;
        end
    endfunction

    function [9:0] max10;
        input [9:0] a;
        input [9:0] b;
        begin
            max10 = (a > b) ? a : b;
        end
    endfunction

    function [9:0] absdiff10;
        input [9:0] a;
        input [9:0] b;
        begin
            absdiff10 = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    function [10:0] absdiff11_from10;
        input [9:0] a;
        input [9:0] b;
        begin
            absdiff11_from10 = (a >= b) ? {1'b0, (a - b)} : {1'b0, (b - a)};
        end
    endfunction

    function [10:0] absdiff11;
        input [10:0] a;
        input [10:0] b;
        begin
            absdiff11 = (a >= b) ? (a - b) : (b - a);
        end
    endfunction

    function rect_hit;
        input [9:0]  px;
        input [9:0]  py;
        input        en;
        input [9:0]  x;
        input [8:0]  y;
        input [9:0]  w;
        input [8:0]  h;
        reg   [9:0]  y10;
        reg   [9:0]  h10;
        begin
            y10 = {1'b0, y};
            h10 = {1'b0, h};

            rect_hit = en &&
                       (w != 10'd0) &&
                       (h != 9'd0) &&
                       (px >= x) &&
                       (px <  (x + w)) &&
                       (py >= y10) &&
                       (py <  (y10 + h10));
        end
    endfunction

    function octagon_hit;
        input [9:0]  px;
        input [9:0]  py;
        input        en;
        input [9:0]  cx;
        input [8:0]  cy;
        input [9:0]  radius;
        reg   [9:0]  cy10;
        reg   [9:0]  dx;
        reg   [9:0]  dy;
        reg   [9:0]  dmax;
        reg   [9:0]  dmin;
        reg   [10:0] cutoff;
        begin
            cy10 = {1'b0, cy};

            dx = absdiff10(px, cx);
            dy = absdiff10(py, cy10);

            dmax = max10(dx, dy);
            dmin = min10(dx, dy);

            cutoff = {1'b0, radius} + {2'b00, radius[9:1]};

            octagon_hit = en &&
                          (radius != 10'd0) &&
                          (dmax <= radius) &&
                          (({1'b0, dx} + {1'b0, dy}) <= cutoff);
        end
    endfunction

    function line_hit;
        input [9:0]  px;
        input [9:0]  py;
        input        en;
        input [9:0]  x0;
        input [8:0]  y0;
        input [9:0]  x1;
        input [8:0]  y1;

        reg [9:0]  y0_10;
        reg [9:0]  y1_10;
        reg [9:0]  xmin;
        reg [9:0]  xmax;
        reg [9:0]  ymin;
        reg [9:0]  ymax;

        reg [10:0] px11;
        reg [10:0] py11;
        reg [10:0] xmin11;
        reg [10:0] xmax11;
        reg [10:0] ymin11;
        reg [10:0] ymax11;
        reg [10:0] x0_11;
        reg [10:0] y0_11;

        reg        in_box;
        reg [10:0] dx_from_start;
        reg [10:0] dy_from_start;
        reg [10:0] diag_error;

        reg        is_horizontal;
        reg        is_vertical;
        reg        is_diagonal_45;
        begin
            y0_10 = {1'b0, y0};
            y1_10 = {1'b0, y1};

            xmin = min10(x0, x1);
            xmax = max10(x0, x1);
            ymin = min10(y0_10, y1_10);
            ymax = max10(y0_10, y1_10);

            px11    = {1'b0, px};
            py11    = {1'b0, py};
            xmin11  = {1'b0, xmin};
            xmax11  = {1'b0, xmax};
            ymin11  = {1'b0, ymin};
            ymax11  = {1'b0, ymax};
            x0_11   = {1'b0, x0};
            y0_11   = {1'b0, y0_10};

            in_box = ((px11 + LINE_TOLERANCE) >= xmin11) &&
                     (px11 <= (xmax11 + LINE_TOLERANCE)) &&
                     ((py11 + LINE_TOLERANCE) >= ymin11) &&
                     (py11 <= (ymax11 + LINE_TOLERANCE));

            dx_from_start = absdiff11_from10(px, x0);
            dy_from_start = absdiff11_from10(py, y0_10);
            diag_error    = absdiff11(dx_from_start, dy_from_start);

            is_horizontal = (y0_10 == y1_10);
            is_vertical   = (x0 == x1);
            is_diagonal_45 = !is_horizontal &&
                             !is_vertical &&
                             (absdiff10(x0, x1) == absdiff10(y0_10, y1_10));

            line_hit = en &&
                       in_box &&
                       (
                           (is_horizontal && (absdiff11(py11, y0_11) <= LINE_TOLERANCE)) ||
                           (is_vertical   && (absdiff11(px11, x0_11) <= LINE_TOLERANCE)) ||
                           (is_diagonal_45 && (diag_error <= LINE_TOLERANCE))
                       );
        end
    endfunction

    integer obj_i;
    reg [31:0] w0;
    reg [31:0] w1;
    reg [1:0]  obj_type;
    reg        obj_en;
    reg [9:0]  obj_x;
    reg [8:0]  obj_y;
    reg [9:0]  obj_param0;
    reg [9:0]  obj_w;
    reg [8:0]  obj_h;
    reg [9:0]  obj_x1;
    reg [8:0]  obj_y1;
    reg [5:0]  obj_color;
    reg        obj_hit;
    reg [5:0]  render_color;

    /*
     * IMPORTANT:
     * pix_x/pix_y are referenced directly here and passed explicitly into the
     * hit-test functions. This prevents render_color from getting stuck because
     * a simulator missed function-internal references in the implicit
     * sensitivity list.
     */
    always @* begin
        render_color = bg_color;

        // Explicit harmless self-references keep these in the sensitivity set
        // even with older Verilog simulators.
        w0 = {22'd0, pix_x};
        w1 = {22'd0, pix_y};

        for (obj_i = 0; obj_i < NUM_OBJECTS; obj_i = obj_i + 1) begin
            w0 = obj_word0_mem[obj_i];
            w1 = obj_word1_mem[obj_i];

            obj_type   = w0[31:30];
            obj_en     = w0[29];
            obj_x      = w0[28:19];
            obj_y      = w0[18:10];
            obj_param0 = w0[9:0];

            obj_w      = w1[31:22];
            obj_h      = w1[21:13];
            obj_color  = w1[12:7];

            obj_x1     = w0[9:0];
            obj_y1     = w1[31:23];

            obj_hit = 1'b0;

            case (obj_type)
                OBJ_RECT: begin
                    obj_hit = rect_hit(pix_x, pix_y, obj_en, obj_x, obj_y, obj_w, obj_h);
                end

                OBJ_OCTAGON: begin
                    obj_hit = octagon_hit(pix_x, pix_y, obj_en, obj_x, obj_y, obj_param0);
                end

                OBJ_LINE: begin
                    obj_hit = line_hit(pix_x, pix_y, obj_en, obj_x, obj_y, obj_x1, obj_y1);
                end

                default: begin
                    obj_hit = 1'b0;
                end
            endcase

            if (obj_hit) begin
                render_color = obj_color;
            end
        end
    end

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
                red   <= render_color[5:4];
                green <= render_color[3:2];
                blue  <= render_color[1:0];
            end
        end
    end

    assign vga_out = {
        hsync,
        blue[0],
        green[0],
        red[0],
        vsync,
        blue[1],
        green[1],
        red[1]
    };

endmodule

`default_nettype wire
