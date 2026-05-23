# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = alu.v control_unit.v core.v decoder.v gamepad.v h_sync_generator.v program_counter.v reg_file.v spi_fetcher.v ram.v project.v timer.v vga_peripheral.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD       = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD       = sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS        += -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
# Add test_interactive to this list for local runs

# The test test_vga_capture requires the file vga_peripheral_pattern.v in folder VGAPeripherals

# The test test_vga_rectangle require the file vga_peripheral_rectangle.v in folder VGAPeripherals
# Instantiate the vga_peripheral as:
#    vga_peripheral vga(
#        .clk(clk),
#        .rst_n(rst_n),
#        .enabled(vga_ctrl_reg == 8'd0 ? 1'b0 : 1'b1),
#        .rect_enable(1'b1),
#        .rect_x(10'd120),
#        .rect_y(10'd80),
#        .rect_w(10'd64),
#        .rect_h(10'd48),
#        .rect_color(6'b00_1100),
#        .vga_out(vga_out)
#    );

# The VGA tests (test_vga_primitives) are long running and generate large VCD files, run those at your convenience

# The VGA tests are long running and generate large VCD files, run those at your convenience

# test_vga_rectangle and test_vga_capture are not included for pipeline as those are long running and create very large VCD files, run those at your convenience
MODULE = test_core,test_ram,test_jump,test_io,test_fibonacci,test_c_code,test_alu_itype,test_alu_rtype,test_utype_lui_auipc,test_load_store_sizes,test_branch_conditions,test_firetest_asm,test_firetest_c,test_game_logic,test_system_instructions,test_spi_realistic_bin_boot,test_timer_mmio,test_gamepad_mmio,test_vga_mode

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
