// SPDX-License-Identifier: BSD-2-Clause
// ibex_soc minimal HAL implementation

#include "ibex_soc.h"

// Character output to simulation log
int putchar(int c) {
    REG_WRITE(SIM_CTRL_BASE + SIM_CTRL_OUT, (uint32_t)c);
    return c;
}

// String output
int puts(const char *str) {
    while (*str) {
        putchar(*str++);
    }
    putchar('\n');
    return 0;
}

// Output 32-bit value as hex
void puthex(uint32_t val) {
    static const char hex[] = "0123456789abcdef";
    putchar('0');
    putchar('x');
    for (int i = 28; i >= 0; i -= 4) {
        putchar(hex[(val >> i) & 0xf]);
    }
}

// Halt simulation
void sim_halt(void) {
    REG_WRITE(SIM_CTRL_BASE + SIM_CTRL_CTRL, 1);
    // Should not return, but loop just in case
    while (1) {
        __asm__ volatile("wfi");
    }
}

// Read 64-bit timer value
uint64_t timer_read(void) {
    uint32_t lo, hi, hi2;
    // Handle rollover: read high, low, high again
    do {
        hi  = REG_READ(TIMER_BASE + TIMER_MTIMEH);
        lo  = REG_READ(TIMER_BASE + TIMER_MTIME);
        hi2 = REG_READ(TIMER_BASE + TIMER_MTIMEH);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

// Set timer compare value
void timer_set_cmp(uint64_t cmp) {
    // Write high first with max value to prevent spurious interrupt
    REG_WRITE(TIMER_BASE + TIMER_MTIMECMPH, 0xFFFFFFFF);
    REG_WRITE(TIMER_BASE + TIMER_MTIMECMP, (uint32_t)cmp);
    REG_WRITE(TIMER_BASE + TIMER_MTIMECMPH, (uint32_t)(cmp >> 32));
}

// Default exception handler (weak)
__attribute__((weak))
void exception_handler(void) {
    puts("EXCEPTION!");
    sim_halt();
}

// Default timer interrupt handler (weak)
__attribute__((weak))
void timer_interrupt_handler(void) {
    puts("TIMER IRQ!");
    sim_halt();
}
