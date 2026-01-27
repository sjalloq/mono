SHELL     := /bin/bash
MKDIR     := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MKDIR)/../../../../..)

# Design under test
TOPLEVEL_LANG = verilog
TOPLEVEL = ibex_soc_top
COCOTB_TEST_MODULES = testbench
FILELIST = $(MKDIR)/filelist.f

# C tests
TEST ?= hello

# Verilog sources
VERILOG_SOURCES =

# Simulator
SIM = verilator
EXTRA_ARGS += --trace --trace-fst -f $(FILELIST) -GItcmInitFile=\"hello.vmem\"

# Verilator-specific
VERILATOR_FLAGS = -Wno-fatal

# Additional dependencies for the included Cocotb Makefiles
CUSTOM_COMPILE_DEPS = filelist

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: filelist

filelist: $(FILELIST)
$(FILELIST):
	cd $(REPO_ROOT) && flist -o $@ mono:ip:ibex_soc --flag target_sim --flag tool_verilator --simulator verilator

clean::
	rm $(FILELIST)