// SPDX-License-Identifier: BSD-2-Clause
// OBI to Wishbone Pipelined Bridge
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Bridges Ibex's OBI interface to Wishbone B4 pipelined protocol.
// Supports outstanding transactions for pipelined operation.

module ibex_obi2wb #(
    parameter int unsigned AW = 32,  // Address width
    parameter int unsigned DW = 32   // Data width
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // OBI interface (from Ibex)
    input  logic             obi_req_i,
    output logic             obi_gnt_o,
    input  logic [AW-1:0]    obi_addr_i,
    input  logic             obi_we_i,
    input  logic [DW/8-1:0]  obi_be_i,
    input  logic [DW-1:0]    obi_wdata_i,
    output logic [DW-1:0]    obi_rdata_o,
    output logic             obi_rvalid_o,
    output logic             obi_err_o,

    // Wishbone B4 pipelined master interface
    output logic             wb_cyc_o,
    output logic             wb_stb_o,
    output logic             wb_we_o,
    output logic [AW-1:0]    wb_adr_o,
    output logic [DW/8-1:0]  wb_sel_o,
    output logic [DW-1:0]    wb_dat_o,
    input  logic [DW-1:0]    wb_dat_i,
    input  logic             wb_ack_i,
    input  logic             wb_err_i,
    input  logic             wb_stall_i
);

    // Track outstanding transactions
    logic outstanding_d, outstanding_q;
    logic req_accepted;

    // Request accepted when we assert and slave doesn't stall
    assign req_accepted = wb_stb_o && !wb_stall_i;

    // Grant when we can forward the request
    assign obi_gnt_o = obi_req_i && !wb_stall_i && (!outstanding_q || wb_ack_i || wb_err_i);

    // Wishbone signals
    assign wb_cyc_o = obi_req_i || outstanding_q;
    assign wb_stb_o = obi_req_i;
    assign wb_we_o  = obi_we_i;
    assign wb_adr_o = obi_addr_i;
    assign wb_sel_o = obi_be_i;
    assign wb_dat_o = obi_wdata_i;

    // Outstanding transaction logic
    always_comb begin
        outstanding_d = outstanding_q;
        if (req_accepted && !(wb_ack_i || wb_err_i)) begin
            outstanding_d = 1'b1;
        end else if ((wb_ack_i || wb_err_i) && !req_accepted) begin
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
    assign obi_rvalid_o = wb_ack_i || wb_err_i;
    assign obi_rdata_o  = wb_dat_i;
    assign obi_err_o    = wb_err_i;

`ifdef FORMAL
    // Formal verification properties

    // CYC must be held while outstanding
    property cyc_held_outstanding;
        @(posedge clk_i) disable iff (!rst_ni)
        outstanding_q |-> wb_cyc_o;
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
