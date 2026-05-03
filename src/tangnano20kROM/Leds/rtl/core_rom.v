/*
 * RiscV Pony core variant for FPGA ROM bring-up.
 *
 * This is the same Pony core datapath, but instruction fetch is provided
 * by rom_fetcher instead of spi_fetcher.
 */

`default_nettype none

module core_rom (
    input  wire       clk,
    input  wire       rst_n,

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

    program_counter pc (
        .clk(clk),
        .rst_n(rst_n),
        .pc_en(pc_en),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    wire [31:0] pc_plus_4 = pc_current + 32'd4;
    wire [31:0] pc_branch = pc_current + imm;

    assign pc_next = (pc_src == 2'b10) ? {alu_result[31:1], 1'b0} :
                     (pc_src == 2'b01) ? pc_branch :
                                         pc_plus_4;

    rom_fetcher #(
        .ROM_ADDR_WIDTH(10)
    ) fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .fetch_req(fetch_req),
        .pc_addr(pc_current),
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

    localparam MMIO_OUT_ADDR = 32'd128;
    localparam MMIO_IN_ADDR  = 32'd132;

    wire is_mmio_out = (alu_result == MMIO_OUT_ADDR);
    wire is_mmio_in  = (alu_result == MMIO_IN_ADDR);

    wire [31:0] raw_read_data = is_mmio_in ? {24'b0, in_port} : mem_read_data;
    reg  [31:0] aligned_read_data;

    always @(*) begin
        case (mem_size)
            2'b00: begin
                case (alu_result[1:0])
                    2'b00: aligned_read_data = {{24{~mem_unsigned & raw_read_data[7]}},  raw_read_data[7:0]};
                    2'b01: aligned_read_data = {{24{~mem_unsigned & raw_read_data[15]}}, raw_read_data[15:8]};
                    2'b10: aligned_read_data = {{24{~mem_unsigned & raw_read_data[23]}}, raw_read_data[23:16]};
                    2'b11: aligned_read_data = {{24{~mem_unsigned & raw_read_data[31]}}, raw_read_data[31:24]};
                endcase
            end
            2'b01: begin
                if (alu_result[1])
                    aligned_read_data = {{16{~mem_unsigned & raw_read_data[31]}}, raw_read_data[31:16]};
                else
                    aligned_read_data = {{16{~mem_unsigned & raw_read_data[15]}}, raw_read_data[15:0]};
            end
            default: aligned_read_data = raw_read_data;
        endcase
    end

    reg [3:0]  ram_we_mask;
    reg [31:0] ram_write_data;

    always @(*) begin
        ram_we_mask = 4'b0000;
        ram_write_data = rs2_data;

        if (mem_we && !is_mmio_out) begin
            case (mem_size)
                2'b00: begin
                    ram_write_data = {4{rs2_data[7:0]}};
                    ram_we_mask = 4'b0001 << alu_result[1:0];
                end
                2'b01: begin
                    ram_write_data = {2{rs2_data[15:0]}};
                    ram_we_mask = alu_result[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    ram_we_mask = 4'b1111;
                end
            endcase
        end
    end

    reg [7:0] out_reg;
    assign out_port = out_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reg <= 8'b0;
        end else if (mem_we && is_mmio_out) begin
            out_reg <= rs2_data[7:0];
        end
    end

endmodule
