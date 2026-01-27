// SPDX-License-Identifier: BSD-2-Clause
// Hello world test for ibex_soc

#include "ibex_soc.h"

int main(void) {
    puts("Hello from ibex_soc!");
    puts("");

    // Print memory map info
    puts("Memory map:");
    puts("  ITCM: 0x00010000 (16KB)");
    puts("  DTCM: 0x00020000 (16KB)");
    puts("  Timer: 0x10000000");
    puts("  SimCtrl: 0x10001000");
    puts("");

    // Read and print timer value
    uint64_t time = timer_read();
    puts("Timer value:");
    puthex((uint32_t)(time >> 32));
    putchar('_');
    puthex((uint32_t)time);
    putchar('\n');

    puts("");
    puts("Test PASSED!");

    // Halt simulation (crt0 will also halt if we return)
    return 0;
}
