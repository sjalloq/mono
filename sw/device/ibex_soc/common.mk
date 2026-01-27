# SPDX-License-Identifier: BSD-2-Clause
# Common Makefile for ibex_soc firmware
#
# Usage: Include from app Makefile after setting:
#   PROG     - Program name (output will be $(PROG).elf)
#   SRCS     - List of C source files
#   ASRCS    - List of assembly source files (optional)

# Paths (relative to app directory)
IBEX_SOC_DIR ?= $(dir $(lastword $(MAKEFILE_LIST)))
LIB_DIR      := $(IBEX_SOC_DIR)/lib

# Toolchain (lowRISC prebuilt or system)
CROSS_COMPILE ?= riscv32-unknown-elf-

CC      := $(CROSS_COMPILE)gcc
AS      := $(CROSS_COMPILE)gcc
LD      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
SIZE    := $(CROSS_COMPILE)size

# Architecture flags
ARCH_FLAGS := -march=rv32imc -mabi=ilp32

# Compiler flags
CFLAGS  := $(ARCH_FLAGS)
CFLAGS  += -Wall -Wextra -Werror
CFLAGS  += -Os -g
CFLAGS  += -ffreestanding -nostdlib
CFLAGS  += -ffunction-sections -fdata-sections
CFLAGS  += -I$(LIB_DIR)

# Assembler flags
ASFLAGS := $(ARCH_FLAGS)
ASFLAGS += -x assembler-with-cpp
ASFLAGS += -I$(LIB_DIR)

# Linker flags
LDFLAGS := $(ARCH_FLAGS)
LDFLAGS += -nostartfiles -nostdlib
LDFLAGS += -static
LDFLAGS += -T$(IBEX_SOC_DIR)/link.ld
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(PROG).map

# Libraries
LIBS := -lgcc

# Common sources
COMMON_SRCS := $(LIB_DIR)/ibex_soc.c
COMMON_ASRCS := $(IBEX_SOC_DIR)/crt0.S

# All sources
ALL_SRCS := $(COMMON_SRCS) $(SRCS)
ALL_ASRCS := $(COMMON_ASRCS) $(ASRCS)

# Object files
OBJS := $(ALL_SRCS:.c=.o) $(ALL_ASRCS:.S=.o)

# Default target
all: $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).dis
	@$(SIZE) $(PROG).elf

# Link
$(PROG).elf: $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^ $(LIBS)

# Binary
$(PROG).bin: $(PROG).elf
	$(OBJCOPY) -O binary $< $@

# Verilog memory file (for simulation)
$(PROG).vmem: $(PROG).bin
	od -An -tx4 -w4 -v $< | sed 's/^ //' > $@

# Disassembly
$(PROG).dis: $(PROG).elf
	$(OBJDUMP) -d -S $< > $@

# Compile C
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Compile assembly
%.o: %.S
	$(AS) $(ASFLAGS) -c -o $@ $<

# Clean
clean:
	rm -f $(OBJS) $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).map $(PROG).dis

.PHONY: all clean
