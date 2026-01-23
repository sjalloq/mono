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

module wb2simple #(
    parameter int unsigned AW = 32,
    parameter int unsigned DW = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone slave interface (pipelined B4)
    input  logic             wb_cyc_i,
    input  logic             wb_stb_i,
    input  logic             wb_we_i,
    input  logic [AW-1:0]    wb_adr_i,
    input  logic [DW/8-1:0]  wb_sel_i,
    input  logic [DW-1:0]    wb_dat_i,
    output logic [DW-1:0]    wb_dat_o,
    output logic             wb_ack_o,
    output logic             wb_err_o,
    output logic             wb_stall_o,

    // Simple bus interface (to PeakRDL CSR block)
    output logic             reg_we,
    output logic             reg_re,
    output logic [AW-1:0]    reg_addr,
    output logic [DW-1:0]    reg_wdata,
    input  logic [DW-1:0]    reg_rdata
);

    // Valid access when both cyc and stb are asserted
    logic valid_access;
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Simple bus signals - directly derived from Wishbone
    assign reg_we    = valid_access && wb_we_i;
    assign reg_re    = valid_access && !wb_we_i;
    assign reg_addr  = wb_adr_i;
    assign reg_wdata = wb_dat_i;

    // Read data comes directly from CSR block (combinational)
    assign wb_dat_o  = reg_rdata;

    // Never stall - we can accept a new request every cycle
    assign wb_stall_o = 1'b0;

    // ACK one cycle after request (pipelined protocol)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wb_ack_o <= 1'b0;
        end else begin
            wb_ack_o <= valid_access;
        end
    end

    // No error conditions in this simple adapter
    assign wb_err_o = 1'b0;

    // Unused signals
    logic unused;
    assign unused = &{wb_sel_i};

endmodule
