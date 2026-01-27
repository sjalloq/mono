// SPDX-License-Identifier: BSD-2-Clause
// ibex_soc minimal HAL
// For bringup and simulation validation

#ifndef IBEX_SOC_H
#define IBEX_SOC_H

#include <stdint.h>
#include "ibex_soc_regs.h"

// Register access macros
#define REG_WRITE(addr, val) (*((volatile uint32_t *)(addr)) = (val))
#define REG_READ(addr)       (*((volatile uint32_t *)(addr)))

// Character output (simulation)
int putchar(int c);

// String output
int puts(const char *str);

// Hex output
void puthex(uint32_t val);

// Halt simulation
void sim_halt(void);

// Timer functions
uint64_t timer_read(void);
void timer_set_cmp(uint64_t cmp);

// Default handlers (weak, can be overridden)
void exception_handler(void);
void timer_interrupt_handler(void);

#endif // IBEX_SOC_H
