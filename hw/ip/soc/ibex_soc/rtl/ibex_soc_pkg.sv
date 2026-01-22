// SPDX-License-Identifier: BSD-2-Clause
// Ibex SoC Package
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Memory map definitions and configuration parameters.

package ibex_soc_pkg;

    // Bus parameters
    parameter int unsigned AW = 32;
    parameter int unsigned DW = 32;

    // Number of masters and slaves
    parameter int unsigned NUM_MASTERS = 3;  // I-bus, D-bus, Etherbone
    parameter int unsigned NUM_SLAVES  = 5;  // ITCM, DTCM, CSR, Timer, Mailbox

    // Master indices
    parameter int unsigned MASTER_IBUS = 0;
    parameter int unsigned MASTER_DBUS = 1;
    parameter int unsigned MASTER_EB   = 2;

    // Slave indices
    parameter int unsigned SLAVE_ITCM    = 0;
    parameter int unsigned SLAVE_DTCM    = 1;
    parameter int unsigned SLAVE_CSR     = 2;
    parameter int unsigned SLAVE_TIMER   = 3;
    parameter int unsigned SLAVE_MAILBOX = 4;

    // Memory map
    // Region: Base address and size
    parameter logic [AW-1:0] ITCM_BASE    = 32'h0001_0000;
    parameter logic [AW-1:0] ITCM_SIZE    = 32'h0000_4000;  // 16KB
    parameter logic [AW-1:0] ITCM_MASK    = 32'hFFFF_C000;

    parameter logic [AW-1:0] DTCM_BASE    = 32'h0002_0000;
    parameter logic [AW-1:0] DTCM_SIZE    = 32'h0000_4000;  // 16KB
    parameter logic [AW-1:0] DTCM_MASK    = 32'hFFFF_C000;

    parameter logic [AW-1:0] CSR_BASE     = 32'h1000_0000;
    parameter logic [AW-1:0] CSR_SIZE     = 32'h0000_1000;  // 4KB
    parameter logic [AW-1:0] CSR_MASK     = 32'hFFFF_F000;

    parameter logic [AW-1:0] TIMER_BASE   = 32'h1000_1000;
    parameter logic [AW-1:0] TIMER_SIZE   = 32'h0000_1000;  // 4KB
    parameter logic [AW-1:0] TIMER_MASK   = 32'hFFFF_F000;

    parameter logic [AW-1:0] MAILBOX_BASE = 32'h2000_0000;
    parameter logic [AW-1:0] MAILBOX_SIZE = 32'h0000_1000;  // 4KB
    parameter logic [AW-1:0] MAILBOX_MASK = 32'hFFFF_F000;

    // Boot address (start of ITCM)
    parameter logic [AW-1:0] BOOT_ADDR = ITCM_BASE;

    // Debug addresses (within ITCM)
    parameter logic [AW-1:0] DM_HALT_ADDR = ITCM_BASE;
    parameter logic [AW-1:0] DM_EXCEPTION_ADDR = ITCM_BASE + 4;

    // Slave base and mask arrays for crossbar
    function automatic logic [NUM_SLAVES-1:0][AW-1:0] get_slave_bases();
        logic [NUM_SLAVES-1:0][AW-1:0] bases;
        bases[SLAVE_ITCM]    = ITCM_BASE;
        bases[SLAVE_DTCM]    = DTCM_BASE;
        bases[SLAVE_CSR]     = CSR_BASE;
        bases[SLAVE_TIMER]   = TIMER_BASE;
        bases[SLAVE_MAILBOX] = MAILBOX_BASE;
        return bases;
    endfunction

    function automatic logic [NUM_SLAVES-1:0][AW-1:0] get_slave_masks();
        logic [NUM_SLAVES-1:0][AW-1:0] masks;
        masks[SLAVE_ITCM]    = ITCM_MASK;
        masks[SLAVE_DTCM]    = DTCM_MASK;
        masks[SLAVE_CSR]     = CSR_MASK;
        masks[SLAVE_TIMER]   = TIMER_MASK;
        masks[SLAVE_MAILBOX] = MAILBOX_MASK;
        return masks;
    endfunction

endpackage
