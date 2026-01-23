# Wishbone Crossbar Cocotb Testbench Makefile

# Simulator
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
T?=

ifneq ($T,)
COCOTB_TEST_FILTER=$T
endif

# Source files
VERILOG_SOURCES += $(PWD)/tb/wb_crossbar_tb.sv
VERILOG_SOURCES += $(PWD)/../rtl/wb_crossbar_pkg.sv
VERILOG_SOURCES += $(PWD)/../rtl/wb_crossbar_decoder.sv
VERILOG_SOURCES += $(PWD)/../rtl/wb_crossbar_arbiter.sv
VERILOG_SOURCES += $(PWD)/../rtl/wb_crossbar.sv

# Top-level module
COCOTB_TEST_MODULES = wb_crossbar_tb

# Python test module
MODULE = test_wb_crossbar

# Verilator options
EXTRA_ARGS += --trace --trace-fst
EXTRA_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
EXTRA_ARGS += -Wno-UNOPTFLAT

include $(shell cocotb-config --makefiles)/Makefile.sim
