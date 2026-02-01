# Cocotb testbench for Squirrel core.sv
# Exercises end-to-end USB-to-CPU data path via FT601 PHY

SHELL     := /bin/bash
MKDIR     := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MKDIR)/../../../../..)

# Design under test
TOPLEVEL_LANG = verilog
TOPLEVEL = core_tb
COCOTB_TEST_MODULES ?= test_core,test_usb_uart
FILELIST = $(MKDIR)/filelist.f

# Firmware test to build and load (directory under sw/device/squirrel/ibex_soc/)
TEST ?= hello
FW_DIR  := $(REPO_ROOT)/sw/device/squirrel/ibex_soc/$(TEST)
FW_VMEM := $(FW_DIR)/$(TEST).vmem

# Test filter (use T=test_name to run a single test)
T ?=
ifneq ($T,)
COCOTB_TEST_FILTER=$T
endif

# Verilog sources: wrapper is not in FuseSoC, add it directly
VERILOG_SOURCES += $(MKDIR)/tb/core_tb.sv

# Simulator
SIM = verilator
EXTRA_ARGS += --trace --trace-fst -f $(FILELIST)
EXTRA_ARGS += -GItcmInitFile=\"$(TEST).vmem\"
EXTRA_ARGS += -Wno-fatal

# Additional dependencies for the included Cocotb Makefiles
CUSTOM_COMPILE_DEPS = filelist
CUSTOM_SIM_DEPS = firmware

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: filelist firmware check-vmem

filelist: $(FILELIST)
$(FILELIST):
	cd $(REPO_ROOT) && flist -o $@ mono:projects:squirrel_ibex_soc \
	    --flag target_sim --flag tool_verilator --simulator verilator

firmware: $(TEST).vmem check-vmem

$(TEST).vmem: $(FW_VMEM)
	cp $< $@

$(FW_VMEM):
	$(MAKE) -C $(FW_DIR)

check-vmem:
	@if [ ! -s $(TEST).vmem ]; then \
	    echo "ERROR: $(TEST).vmem is missing or empty."; \
	    echo "  Firmware build may have failed, or TEST='$(TEST)' is not a valid test."; \
	    echo "  Available tests: $$(ls $(REPO_ROOT)/sw/device/squirrel/ibex_soc/)"; \
	    exit 1; \
	fi

# Convenience targets
.PHONY: run_usb run_all

run_usb:
	$(MAKE) TEST=usb_echo COCOTB_TEST_MODULES=test_usb_uart

run_all:
	$(MAKE) TEST=hello COCOTB_TEST_MODULES=test_core T=test_boot_heartbeat
	$(MAKE) TEST=usb_echo COCOTB_TEST_MODULES=test_usb_uart

clean::
	rm -f $(FILELIST) $(TEST).vmem

