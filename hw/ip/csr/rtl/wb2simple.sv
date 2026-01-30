// SPDX-License-Identifier: BSD-2-Clause
// Wishbone B4 Pipelined to Simple Bus Adapter
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Converts Wishbone B4 pipelined slave interface to the simple bus interface
// expected by PeakRDL-sv generated CSR blocks.
//
// The simple bus interface has no handshaking - reads return data combinationally.
// This adapter provides a single-cycle ACK for all accesses.

module wb2simple
    import wb_pkg::*;
(
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone slave interface (pipelined B4)
    input  wb_m2s_t          wb_m2s_i,
    output wb_s2m_t          wb_s2m_o,

    // Simple bus interface (to PeakRDL CSR block)
    output logic             reg_we,
    output logic             reg_re,
    output logic [31:0]      reg_addr,
    output logic [31:0]      reg_wdata,
    input  logic [31:0]      reg_rdata
);

    // Valid access when both cyc and stb are asserted
    logic valid_access;
    assign valid_access = wb_m2s_i.cyc && wb_m2s_i.stb;

    // Simple bus signals - directly derived from Wishbone
    assign reg_we    = valid_access && wb_m2s_i.we;
    assign reg_re    = valid_access && !wb_m2s_i.we;
    assign reg_addr  = wb_m2s_i.adr;
    assign reg_wdata = wb_m2s_i.dat;

    // ACK and read data registered to align with pipelined protocol.
    // The CSR read data mux is combinational from the address, so we
    // register it here to break the timing path.
    logic        wb_ack_q;
    logic [31:0] reg_rdata_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wb_ack_q    <= 1'b0;
            reg_rdata_q <= '0;
        end else begin
            wb_ack_q    <= valid_access;
            reg_rdata_q <= reg_rdata;
        end
    end

    // Output struct
    assign wb_s2m_o = '{dat: reg_rdata_q, ack: wb_ack_q, err: 1'b0, stall: 1'b0};

    // Unused signals
    logic unused;
    assign unused = &{wb_m2s_i.sel};

endmodule
