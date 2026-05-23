`default_nettype none

module core (
    input  wire       clk,
    input  wire       rst_n,

    output wire       spi_cs_n,
    output wire       spi_sck,
    output wire       spi_mosi,
    input  wire       spi_miso,

    output wire [7:0] out_port,
    input  wire [7:0] in_port
);

    wire [31:0] pc_current;
    wire [31:0] pc_next;
    wire        pc_en;
    wire [1:0]  pc_src;

    wire [2:0]  wb_sel;

    wire        fetch_req;
    wire        fetch_done;
    wire [31:0] inst_data;

    wire [6:0]  opcode;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [4:0]  rs1_addr;
    wire [4:0]  rs2_addr;
    wire [4:0]  rd_addr;
    wire [31:0] imm;

    wire        reg_we;
    wire        alu_src_b;
    wire [3:0]  alu_ctrl;

    wire        mem_we;
    wire [1:0]  mem_size;
    wire        mem_unsigned;
    wire [31:0] mem_read_data;

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] rd_data;

    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;
    wire        zero_flag;

    wire [31:0] timer_value;

    localparam MMIO_OUT_ADDR            = 32'd128;
    localparam MMIO_IN_ADDR             = 32'd132;
    localparam MMIO_TIMER_ADDR          = 32'd136;
    localparam MMIO_VGA_CTRL            = 32'd140;
    localparam MMIO_GAMEPAD_DATA        = 32'd144;
    localparam MMIO_VGA_OBJ_INDEX       = 32'd148;
    localparam MMIO_VGA_OBJ_WORD0       = 32'd152;
    localparam MMIO_VGA_OBJ_WORD1       = 32'd156;
    localparam MMIO_VGA_BG_COLOR        = 32'd160;
    localparam MMIO_VGA_OBJ_WORD2       = 32'd164;
    localparam MMIO_VGA_FRAMES_COUNTER  = 32'd168;
    localparam MMIO_VGA_LINE_COUNTER    = 32'd172; // <--- NEW

    wire is_mmio_out                = (alu_result == MMIO_OUT_ADDR);
    wire is_mmio_in                 = (alu_result == MMIO_IN_ADDR);
    wire is_mmio_timer              = (alu_result == MMIO_TIMER_ADDR);
    wire is_mmio_vga_ctrl           = (alu_result == MMIO_VGA_CTRL);
    wire is_mmio_gamepad            = (alu_result == MMIO_GAMEPAD_DATA);
    wire is_mmio_vga_obj_index      = (alu_result == MMIO_VGA_OBJ_INDEX);
    wire is_mmio_vga_obj_word0      = (alu_result == MMIO_VGA_OBJ_WORD0);
    wire is_mmio_vga_obj_word1      = (alu_result == MMIO_VGA_OBJ_WORD1);
    wire is_mmio_vga_obj_word2      = (alu_result == MMIO_VGA_OBJ_WORD2);
    wire is_mmio_vga_bg_color       = (alu_result == MMIO_VGA_BG_COLOR);
    wire is_mmio_vga_frames_counter = (alu_result == MMIO_VGA_FRAMES_COUNTER);
    wire is_mmio_vga_line_counter   = (alu_result == MMIO_VGA_LINE_COUNTER); // <--- NEW

    wire is_mmio               = is_mmio_out           ||
                                 is_mmio_in            ||
                                 is_mmio_timer         ||
                                 is_mmio_vga_ctrl      ||
                                 is_mmio_gamepad       ||
                                 is_mmio_vga_obj_index ||
                                 is_mmio_vga_obj_word0 ||
                                 is_mmio_vga_obj_word1 ||
                                 is_mmio_vga_obj_word2 ||
                                 is_mmio_vga_bg_color  ||
                                 is_mmio_vga_frames_counter ||
                                 is_mmio_vga_line_counter;

    program_counter pc (
        .clk(clk),
        .rst_n(rst_n),
        .pc_en(pc_en),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    assign pc_next = (pc_src == 2'b10) ? {alu_result[31:1], 1'b0} :
                     (pc_src == 2'b01) ? pc_branch :
                                         pc_plus_4;

    wire [31:0] pc_plus_4 = pc_current + 32'd4;
    wire [31:0] pc_branch = pc_current + imm;

    spi_fetcher fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_req(fetch_req),
        .pc_addr(pc_current),
        .spi_cs_n(spi_cs_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .inst_data(inst_data),
        .fetch_done(fetch_done)
    );

    decoder instructions_decoder (
        .inst(inst_data),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1(rs1_addr),
        .rs2(rs2_addr),
        .rd(rd_addr),
        .imm(imm)
    );

    control_unit cu (
        .clk(clk),
        .rst_n(rst_n),
        .opcode(opcode),
        .funct3(funct3),
        .funct7_bit5(funct7[5]),
        .zero(zero_flag),
        .fetch_done(fetch_done),
        .fetch_req(fetch_req),
        .pc_en(pc_en),
        .pc_src(pc_src),
        .reg_we(reg_we),
        .alu_src_b(alu_src_b),
        .alu_ctrl(alu_ctrl),
        .mem_we(mem_we),
        .wb_sel(wb_sel),
        .alu_result_0(alu_result[0]),
        .mem_size(mem_size),
        .mem_unsigned(mem_unsigned)
    );

    regfile regs (
        .clk(clk),
        .we(reg_we),
        .rs1_addr(rs1_addr[3:0]),
        .rs2_addr(rs2_addr[3:0]),
        .rd_addr(rd_addr[3:0]),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    assign rd_data = (wb_sel == 3'b100) ? pc_branch :
                     (wb_sel == 3'b011) ? imm :
                     (wb_sel == 3'b010) ? pc_plus_4 :
                     (wb_sel == 3'b001) ? aligned_read_data :
                                          alu_result;

    alu alu_unit (
        .a(rs1_data),
        .b(alu_operand_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(zero_flag)
    );

    assign alu_operand_b = alu_src_b ? imm : rs2_data;

    ram data_memory (
        .clk(clk),
        .we(ram_we_mask),
        .addr(alu_result),
        .write_data(ram_write_data),
        .read_data(mem_read_data)
    );

    timer timer (
        .clk(clk),
        .rst_n(rst_n),
        .timer_value(timer_value)
    );

    // --- READ ALIGNER (Shift & Sign Extend) ---
    wire [31:0] raw_read_data = is_mmio_timer               ? timer_value :
                                is_mmio_in                  ? {24'b0, in_port} :
                                is_mmio_gamepad             ? {19'b0, gamepad0_state} :
                                is_mmio_vga_ctrl            ? {24'b0, vga_ctrl_reg} :
                                is_mmio_vga_obj_index       ? {28'b0, vga_obj_index_reg} :
                                is_mmio_vga_bg_color        ? {26'b0, vga_bg_color_reg} :
                                is_mmio_vga_frames_counter  ? {24'b0, vga_frames_counter} :
                                is_mmio_vga_line_counter    ? {22'b0, vga_line} : // <--- NEW
                                                              mem_read_data;

    reg [31:0] aligned_read_data;

    always @(*) begin
        case (mem_size)
            2'b00: begin // LB / LBU
                case (alu_result[1:0])
                    2'b00: aligned_read_data = {{24{~mem_unsigned & raw_read_data[7]}},  raw_read_data[7:0]};
                    2'b01: aligned_read_data = {{24{~mem_unsigned & raw_read_data[15]}}, raw_read_data[15:8]};
                    2'b10: aligned_read_data = {{24{~mem_unsigned & raw_read_data[23]}}, raw_read_data[23:16]};
                    2'b11: aligned_read_data = {{24{~mem_unsigned & raw_read_data[31]}}, raw_read_data[31:24]};
                endcase
            end
            2'b01: begin // LH / LHU
                if (alu_result[1])
                    aligned_read_data = {{16{~mem_unsigned & raw_read_data[31]}}, raw_read_data[31:16]};
                else
                    aligned_read_data = {{16{~mem_unsigned & raw_read_data[15]}}, raw_read_data[15:0]};
            end
            default: aligned_read_data = raw_read_data; // LW
        endcase
    end

    // --- WRITE ALIGNER (Dynamic Masking) ---
    reg [3:0]  ram_we_mask;
    reg [31:0] ram_write_data;

    always @(*) begin
        ram_we_mask = 4'b0000;
        ram_write_data = rs2_data;

        if (mem_we && !is_mmio) begin
            case (mem_size)
                2'b00: begin
                    ram_write_data  = {4{rs2_data[7:0]}};
                    ram_we_mask     = 4'b0001 << alu_result[1:0];
                end
                2'b01: begin
                    ram_write_data  = {2{rs2_data[15:0]}};
                    ram_we_mask     = alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    ram_we_mask     = 4'b1111;
                end
            endcase
        end
    end

    reg [7:0]  out_reg;
    reg [7:0]  vga_ctrl_reg;
    reg [3:0]  vga_obj_index_reg;
    reg [5:0]  vga_bg_color_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reg             <= 8'b0;
            vga_ctrl_reg        <= 8'b0;
            vga_obj_index_reg   <= 4'b0;
            vga_bg_color_reg    <= 6'b00_00_00;
        end else begin
            if (mem_we && is_mmio_out) out_reg <= rs2_data[7:0];
            if (mem_we && is_mmio_vga_ctrl) vga_ctrl_reg <= rs2_data[7:0];
            if (mem_we && is_mmio_vga_obj_index) vga_obj_index_reg <= rs2_data[3:0];
            if (mem_we && is_mmio_vga_bg_color) vga_bg_color_reg <= rs2_data[5:0];
        end
    end

    assign out_port = (vga_ctrl_reg == 8'd0) ? out_reg : vga_out;

    wire [7:0] vga_out;
    wire [7:0] vga_frames_counter;
    wire [9:0] vga_line; // <--- NEW

    vga_peripheral vga(
        .clk(clk),
        .rst_n(rst_n),
        .enabled(vga_ctrl_reg != 8'd0),
        .bg_color(vga_bg_color_reg),

        .obj_index(vga_obj_index_reg),
        .we_w0(mem_we && is_mmio_vga_obj_word0),
        .we_w1(mem_we && is_mmio_vga_obj_word1),
        .we_w2(mem_we && is_mmio_vga_obj_word2),
        .write_data(rs2_data),

        .frames_counter(vga_frames_counter),
        .current_line(vga_line), // <--- NEW
        .vga_out(vga_out)
    );

    wire [12:0] gamepad0_state;

    gamepad_pmod_single driver (
        .rst_n(rst_n),
        .clk(clk),
        .pmod_data(in_port[6]),
        .pmod_clk(in_port[5]),
        .pmod_latch(in_port[4]),
        .b(gamepad0_state [1]),
        .y(gamepad0_state [3]),
        .select(gamepad0_state [11]),
        .start(gamepad0_state [10]),
        .up(gamepad0_state [6]),
        .down(gamepad0_state[7]),
        .left(gamepad0_state[9]),
        .right(gamepad0_state[8]),
        .a(gamepad0_state[0]),
        .x(gamepad0_state[2]),
        .l(gamepad0_state[5]),
        .r(gamepad0_state[4]),
        .is_present(gamepad0_state[12])
    );

endmodule
