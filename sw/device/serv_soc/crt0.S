# SPDX-License-Identifier: BSD-2-Clause
# Startup code for serv_soc
# SERV resets to RESET_PC (0x00000000)

#include "serv_soc_regs.h"

    .section .text.start
    .global _start

_start:
    # Zero all registers
    mv  x1, x0
    mv  x2, x1
    mv  x3, x1
    mv  x4, x1
    mv  x5, x1
    mv  x6, x1
    mv  x7, x1
    mv  x8, x1
    mv  x9, x1
    mv x10, x1
    mv x11, x1
    mv x12, x1
    mv x13, x1
    mv x14, x1
    mv x15, x1
    mv x16, x1
    mv x17, x1
    mv x18, x1
    mv x19, x1
    mv x20, x1
    mv x21, x1
    mv x22, x1
    mv x23, x1
    mv x24, x1
    mv x25, x1
    mv x26, x1
    mv x27, x1
    mv x28, x1
    mv x29, x1
    mv x30, x1
    mv x31, x1

    # Initialize stack pointer
    la x2, _stack_start

    # Clear BSS section
    la x26, _bss_start
    la x27, _bss_end
    bge x26, x27, bss_zero_end

bss_zero_loop:
    sw x0, 0(x26)
    addi x26, x26, 4
    blt x26, x27, bss_zero_loop

bss_zero_end:

main_entry:
    # Call main (argc=0, argv=NULL)
    addi x10, x0, 0
    addi x11, x0, 0
    jal x1, main

    # Halt simulation after main returns
    li x5, SIM_CTRL_BASE + SIM_CTRL_CTRL
    li x6, 1
    sw x6, 0(x5)

    # If simulation doesn't halt, spin forever
sleep_loop:
    j sleep_loop
