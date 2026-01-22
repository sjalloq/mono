// SPDX-License-Identifier: BSD-2-Clause
// Wishbone B4 Pipelined Package
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Common types and parameters for Wishbone infrastructure.

package wb_pkg;

    // Default bus widths
    parameter int unsigned WB_AW = 32;
    parameter int unsigned WB_DW = 32;

    // Memory map region descriptor
    typedef struct packed {
        logic [WB_AW-1:0] base_addr;
        logic [WB_AW-1:0] mask;       // Address mask (1s for bits that must match)
    } wb_region_t;

    // Check if address is in region
    function automatic logic addr_in_region(
        input logic [WB_AW-1:0] addr,
        input wb_region_t       region
    );
        return (addr & region.mask) == (region.base_addr & region.mask);
    endfunction

endpackage
