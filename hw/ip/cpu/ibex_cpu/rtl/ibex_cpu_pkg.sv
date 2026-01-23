// SPDX-License-Identifier: BSD-2-Clause
// Ibex CPU Subsystem Package
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Configuration parameters for the Ibex CPU subsystem with
// tightly coupled instruction memory.

package ibex_cpu_pkg;

    // Bus parameters
    parameter int unsigned AW = 32;
    parameter int unsigned DW = 32;

    // ITCM configuration (tightly coupled, CPU-only)
    parameter logic [AW-1:0] ITCM_BASE = 32'h0001_0000;
    parameter logic [AW-1:0] ITCM_SIZE = 32'h0000_4000;  // 16KB

    // Boot address (start of ITCM)
    parameter logic [AW-1:0] BOOT_ADDR = ITCM_BASE;

endpackage
