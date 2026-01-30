// SPDX-License-Identifier: BSD-2-Clause
// OBI to Wishbone Pipelined Bridge
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Bridges Ibex's OBI interface to Wishbone B4 pipelined protocol.
// Supports outstanding transactions for pipelined operation.

module ibex_obi2wb
    import wb_pkg::*;
(
    input  logic             clk_i,
    input  logic             rst_ni,

    // OBI interface (from Ibex)
    input  logic             obi_req_i,
    output logic             obi_gnt_o,
    input  logic [31:0]      obi_addr_i,
    input  logic             obi_we_i,
    input  logic [3:0]       obi_be_i,
    input  logic [31:0]      obi_wdata_i,
    output logic [31:0]      obi_rdata_o,
    output logic             obi_rvalid_o,
    output logic             obi_err_o,

    // Wishbone B4 pipelined master interface
    output wb_m2s_t          wb_m2s_o,
    input  wb_s2m_t          wb_s2m_i
);

    // Track outstanding transactions
    logic outstanding_d, outstanding_q;
    logic req_accepted;

    // Request accepted when we assert and slave doesn't stall
    assign req_accepted = wb_m2s_o.stb && !wb_s2m_i.stall;

    // Grant when we can forward the request
    assign obi_gnt_o = obi_req_i && !wb_s2m_i.stall && (!outstanding_q || wb_s2m_i.ack || wb_s2m_i.err);

    // Wishbone signals
    assign wb_m2s_o = '{cyc: obi_req_i || outstanding_q,
                        stb: obi_req_i,
                        we:  obi_we_i,
                        adr: obi_addr_i,
                        sel: obi_be_i,
                        dat: obi_wdata_i};

    // Outstanding transaction logic
    always_comb begin
        outstanding_d = outstanding_q;
        if (req_accepted && !(wb_s2m_i.ack || wb_s2m_i.err)) begin
            outstanding_d = 1'b1;
        end else if ((wb_s2m_i.ack || wb_s2m_i.err) && !req_accepted) begin
            outstanding_d = 1'b0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            outstanding_q <= 1'b0;
        end else begin
            outstanding_q <= outstanding_d;
        end
    end

    // Response to OBI
    assign obi_rvalid_o = wb_s2m_i.ack || wb_s2m_i.err;
    assign obi_rdata_o  = wb_s2m_i.dat;
    assign obi_err_o    = wb_s2m_i.err;

`ifdef FORMAL
    // Formal verification properties

    // CYC must be held while outstanding
    property cyc_held_outstanding;
        @(posedge clk_i) disable iff (!rst_ni)
        outstanding_q |-> wb_m2s_o.cyc;
    endproperty
    assert property (cyc_held_outstanding);

    // Grant only when request is present
    property gnt_requires_req;
        @(posedge clk_i) disable iff (!rst_ni)
        obi_gnt_o |-> obi_req_i;
    endproperty
    assert property (gnt_requires_req);

    // rvalid must have corresponding request
    property rvalid_after_req;
        @(posedge clk_i) disable iff (!rst_ni)
        obi_rvalid_o |-> outstanding_q || $past(obi_gnt_o);
    endproperty
    assert property (rvalid_after_req);
`endif

endmodule
