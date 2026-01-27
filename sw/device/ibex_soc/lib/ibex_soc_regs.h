// SPDX-License-Identifier: BSD-2-Clause
// ibex_soc register definitions
// For use by both C and assembly

#ifndef IBEX_SOC_REGS_H
#define IBEX_SOC_REGS_H

// Memory regions
#define ITCM_BASE       0x00010000
#define ITCM_SIZE       0x00004000  // 16KB

#define DTCM_BASE       0x00020000
#define DTCM_SIZE       0x00004000  // 16KB

// Timer peripheral (RISC-V mtime)
#define TIMER_BASE      0x10000000
#define TIMER_MTIME     0x00
#define TIMER_MTIMEH    0x04
#define TIMER_MTIMECMP  0x08
#define TIMER_MTIMECMPH 0x0C

// Simulation control peripheral
#define SIM_CTRL_BASE   0x10001000
#define SIM_CTRL_OUT    0x00    // Write ASCII char [7:0]
#define SIM_CTRL_CTRL   0x08    // Write 1 to halt simulation

#endif // IBEX_SOC_REGS_H
