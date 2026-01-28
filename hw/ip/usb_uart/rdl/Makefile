# USB UART CSR Generation Makefile
#
# Regenerates SystemVerilog from SystemRDL definitions using PeakRDL-sv.

RTL_DIR := ../rtl
RDL_SRC := usb_uart_csr.rdl

# PeakRDL-sv options
PEAKRDL      := peakrdl sv
PEAKRDL_OPTS := --reset-polarity low --reset-type async

# Generated files
GEN_PKG := $(RTL_DIR)/usb_uart_csr_reg_pkg.sv
GEN_TOP := $(RTL_DIR)/usb_uart_csr_reg_top.sv

.PHONY: all clean

all: $(GEN_PKG) $(GEN_TOP)

$(GEN_PKG) $(GEN_TOP): $(RDL_SRC)
	@echo "Generating CSR from $<..."
	$(PEAKRDL) $(PEAKRDL_OPTS) -o $(RTL_DIR)/gen $<
	mv $(RTL_DIR)/gen/usb_uart_csr_reg_pkg.sv $(RTL_DIR)/
	mv $(RTL_DIR)/gen/usb_uart_csr_reg_top.sv $(RTL_DIR)/
	rmdir $(RTL_DIR)/gen
	@echo "Generated: $(GEN_PKG) $(GEN_TOP)"

clean:
	rm -f $(GEN_PKG) $(GEN_TOP)
	rm -rf $(RTL_DIR)/gen
