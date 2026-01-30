// SPDX-License-Identifier: BSD-2-Clause
// Wishbone Bus Package
//
// Copyright (c) 2026 Shareef Jalloq
//
// Packed struct typedefs for Wishbone pipelined bus (32-bit).

package wb_pkg;

    typedef struct packed {
        logic        cyc;
        logic        stb;
        logic        we;
        logic [31:0] adr;
        logic [3:0]  sel;
        logic [31:0] dat;
    } wb_m2s_t;

    typedef struct packed {
        logic [31:0] dat;
        logic        ack;
        logic        err;
        logic        stall;
    } wb_s2m_t;

endpackage
