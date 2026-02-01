// SPDX-License-Identifier: BSD-2-Clause
// Hello World for SERV SoC

#include "serv_soc.h"

int main(void) {
    puts("Hello from SERV!");
    puts("AON subsystem alive.");

    // Print timer value
    uint64_t t = timer_read();
    puts("Timer: ");
    puthex((uint32_t)(t >> 32));
    puthex((uint32_t)t);
    putchar('\n');

    sim_halt();
    return 0;
}
