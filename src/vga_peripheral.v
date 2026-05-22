`default_nettype none

module vga_peripheral (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enabled,

    input  wire [5:0]  bg_color,

    input  wire [3:0]  obj_index,
    input  wire        we_w0,
    input  wire        we_w1,
    input  wire        we_w2,
    input  wire [31:0] write_data,

    output reg  [7:0]  frames_counter,
    output wire [9:0]  current_line,
    output wire [7:0]  vga_out
);
    // Sync Generator Wires
    wire hsync, vsync, display_on;
    wire [9:0] hpos;
    wire [9:0] vpos;

    hvsync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // Output the LOGICAL line
    assign current_line = {1'b0, vpos[9:1]};

    // -----------------------------------------------------
    // MEMORY ARRAYS (Trimmed to 10 Objects Total)
    // -----------------------------------------------------
    reg [31:0] mem_w0 [0:9];
    reg [31:0] mem_w1 [0:9];
    reg [31:0] mem_w2 [0:3];

    always @(posedge clk) begin
        if (we_w0 && obj_index < 10) mem_w0[obj_index] <= write_data;
        if (we_w1 && obj_index < 10) mem_w1[obj_index] <= write_data;
        if (we_w2 && obj_index < 4)  mem_w2[obj_index] <= write_data;
    end

    // -----------------------------------------------------
    // ACTIVE ENGINES (Render Phase)
    // -----------------------------------------------------
    reg        sp_active    [0:3];
    reg [9:0]  sp_x_count   [0:3];
    reg [7:0]  sp_shift     [0:3];
    reg [2:0]  sp_bits_left [0:3];
    reg [5:0]  sp_color     [0:3];

    // NEW: Scaling state registers (Only 20 bits total!)
    reg [1:0]  sp_scale       [0:3];
    reg [2:0]  sp_scale_count [0:3];

    reg        rect_active  [0:3];
    reg [9:0]  rect_x_count [0:3];
    reg [9:0]  rect_w_count [0:3];
    reg [5:0]  rect_color   [0:3];

    reg        line_active  [0:1];
    reg [9:0]  line_x_count [0:1];
    reg [5:0]  line_color   [0:1];

    // -----------------------------------------------------
    // HBLANK SCANNER (Evaluation Phase)
    // -----------------------------------------------------
    reg [3:0] scan_idx;
    reg       is_scanning;

    wire [9:0] next_vpos = (vpos == 524) ? 10'd0 : (vpos + 10'd1);
    wire [9:0] logical_next_vpos = {1'b0, next_vpos[9:1]};

    // NEW: Dynamic Y-Axis Scaling Math (Pure Combinational)
    wire [1:0] current_scale = mem_w0[scan_idx][1:0];
    wire [9:0] dy_full = logical_next_vpos - mem_w0[scan_idx][14:5];
    wire [2:0] scaled_dy = dy_full >> current_scale;

    reg  [7:0] extracted_row;

    always @* begin
        case(scaled_dy)
            3'd0: extracted_row = mem_w1[scan_idx][31:24];
            3'd1: extracted_row = mem_w1[scan_idx][23:16];
            3'd2: extracted_row = mem_w1[scan_idx][15:8];
            3'd3: extracted_row = mem_w1[scan_idx][7:0];
            3'd4: extracted_row = mem_w2[scan_idx][31:24];
            3'd5: extracted_row = mem_w2[scan_idx][23:16];
            3'd6: extracted_row = mem_w2[scan_idx][15:8];
            3'd7: extracted_row = mem_w2[scan_idx][7:0];
        endcase
    end

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_scanning <= 1'b0;
            for(i=0; i<4; i=i+1) sp_active[i]   <= 1'b0;
            for(i=0; i<4; i=i+1) rect_active[i] <= 1'b0;
            for(i=0; i<2; i=i+1) line_active[i] <= 1'b0;
        end else begin

            if (hpos == 10'd640) begin
                is_scanning <= 1'b1;
                scan_idx    <= 4'd0;
                for(i=0; i<4; i=i+1) sp_active[i]   <= 1'b0;
                for(i=0; i<4; i=i+1) rect_active[i] <= 1'b0;
                for(i=0; i<2; i=i+1) line_active[i] <= 1'b0;
            end

            else if (is_scanning) begin
                // --- Sprites (0 to 3) ---
                if (scan_idx < 4) begin
                    // NEW: Calculate scaled height bound
                    if (mem_w0[scan_idx][31] &&
                       (logical_next_vpos >= mem_w0[scan_idx][14:5]) &&
                       (logical_next_vpos <  mem_w0[scan_idx][14:5] + (10'd8 << mem_w0[scan_idx][1:0]))) begin

                        sp_active[scan_idx]      <= 1'b1;
                        sp_x_count[scan_idx]     <= mem_w0[scan_idx][24:15];
                        sp_color[scan_idx]       <= mem_w0[scan_idx][30:25];
                        sp_bits_left[scan_idx]   <= 3'd7;
                        sp_shift[scan_idx]       <= extracted_row;
                        sp_scale[scan_idx]       <= mem_w0[scan_idx][1:0];
                        sp_scale_count[scan_idx] <= 3'd0;
                    end
                end
                // --- Rectangles (4 to 7) ---
                else if (scan_idx < 8) begin
                    if (mem_w0[scan_idx][31] &&
                       (logical_next_vpos >= mem_w0[scan_idx][14:5]) &&
                       (logical_next_vpos <  mem_w0[scan_idx][14:5] + {1'b0, mem_w1[scan_idx][21:13]})) begin

                        rect_active[scan_idx - 4]  <= 1'b1;
                        rect_x_count[scan_idx - 4] <= mem_w0[scan_idx][24:15];
                        rect_w_count[scan_idx - 4] <= mem_w1[scan_idx][31:22];
                        rect_color[scan_idx - 4]   <= mem_w1[scan_idx][12:7];
                    end
                end
                // --- Diagonal Lines (8 to 9) ---
                else begin
                    if (mem_w0[scan_idx][31] &&
                       (logical_next_vpos >= mem_w0[scan_idx][14:5]) &&
                       (logical_next_vpos <  mem_w0[scan_idx][14:5] + {1'b0, mem_w1[scan_idx][31:22]})) begin

                        line_active[scan_idx - 8] <= 1'b1;
                        line_color[scan_idx - 8]  <= mem_w1[scan_idx][12:7];

                        if (mem_w1[scan_idx][21] == 1'b0) // Right (\)
                            line_x_count[scan_idx - 8] <= mem_w0[scan_idx][24:15] + (logical_next_vpos - mem_w0[scan_idx][14:5]);
                        else                              // Left (/)
                            line_x_count[scan_idx - 8] <= mem_w0[scan_idx][24:15] - (logical_next_vpos - mem_w0[scan_idx][14:5]);
                    end
                end

                scan_idx <= scan_idx + 1'b1;
                if (scan_idx == 4'd10) is_scanning <= 1'b0;
            end

            // --- Active Rendering ---
            else if (display_on) begin
                if (~hpos[0]) begin
                    for(i=0; i<4; i=i+1) begin
                        if (sp_active[i]) begin
                            if (sp_x_count[i] > 0) begin
                                sp_x_count[i] <= sp_x_count[i] - 1'b1;
                            end else begin
                                // NEW: Dynamic X-Axis Scaling Math
                                if (sp_scale_count[i] < ((3'd1 << sp_scale[i]) - 1'b1)) begin
                                    sp_scale_count[i] <= sp_scale_count[i] + 1'b1;
                                end else begin
                                    sp_scale_count[i] <= 3'd0;
                                    sp_shift[i] <= {sp_shift[i][6:0], 1'b0};
                                    if (sp_bits_left[i] == 3'd0) sp_active[i] <= 1'b0;
                                    else sp_bits_left[i] <= sp_bits_left[i] - 1'b1;
                                end
                            end
                        end
                    end

                    for(i=0; i<4; i=i+1) begin
                        if (rect_active[i]) begin
                            if (rect_x_count[i] > 0) rect_x_count[i] <= rect_x_count[i] - 1'b1;
                            else if (rect_w_count[i] > 0) rect_w_count[i] <= rect_w_count[i] - 1'b1;
                            else rect_active[i] <= 1'b0;
                        end
                    end

                    for(i=0; i<2; i=i+1) begin
                        if (line_active[i]) begin
                            if (line_x_count[i] > 0) line_x_count[i] <= line_x_count[i] - 1'b1;
                            else line_active[i] <= 1'b0;
                        end
                    end
                end
            end
        end
    end

    // -----------------------------------------------------
    // COMPOSITOR / MIXER
    // -----------------------------------------------------
    reg [5:0] out_color;

    always @* begin
        out_color = bg_color;

        if (rect_active[3] && rect_x_count[3] == 0 && rect_w_count[3] > 0) out_color = rect_color[3];
        if (rect_active[2] && rect_x_count[2] == 0 && rect_w_count[2] > 0) out_color = rect_color[2];
        if (rect_active[1] && rect_x_count[1] == 0 && rect_w_count[1] > 0) out_color = rect_color[1];
        if (rect_active[0] && rect_x_count[0] == 0 && rect_w_count[0] > 0) out_color = rect_color[0];

        if (line_active[1] && line_x_count[1] == 0) out_color = line_color[1];
        if (line_active[0] && line_x_count[0] == 0) out_color = line_color[0];

        if (sp_active[3] && sp_x_count[3] == 0 && sp_shift[3][7]) out_color = sp_color[3];
        if (sp_active[2] && sp_x_count[2] == 0 && sp_shift[2][7]) out_color = sp_color[2];
        if (sp_active[1] && sp_x_count[1] == 0 && sp_shift[1][7]) out_color = sp_color[1];
        if (sp_active[0] && sp_x_count[0] == 0 && sp_shift[0][7]) out_color = sp_color[0];

        if (!enabled || !display_on) out_color = 6'b000000;
    end

    always @(negedge vsync or negedge rst_n) begin
        if (!rst_n) frames_counter <= 8'd0;
        else        frames_counter <= frames_counter + 8'd1;
    end

    assign vga_out = {
        hsync,
        out_color[1], out_color[3], out_color[5],
        vsync,
        out_color[0], out_color[2], out_color[4]
    };
endmodule
