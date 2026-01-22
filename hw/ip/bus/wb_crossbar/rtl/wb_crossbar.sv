// SPDX-License-Identifier: BSD-2-Clause
// Wishbone B4 Pipelined Crossbar
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Full crossbar interconnect combining arbitration and address decode.
// Supports multiple masters and multiple slaves with pipelined protocol.

module wb_crossbar #(
    parameter int unsigned NUM_MASTERS = 3,   // e.g., Ibex I-bus, D-bus, Etherbone
    parameter int unsigned NUM_SLAVES  = 5,   // e.g., ITCM, DTCM, CSR, Timer, Mailbox
    parameter int unsigned AW          = 32,
    parameter int unsigned DW          = 32,
    // Slave base addresses
    parameter logic [NUM_SLAVES-1:0][AW-1:0] SLAVE_BASE = '0,
    // Slave address masks
    parameter logic [NUM_SLAVES-1:0][AW-1:0] SLAVE_MASK = '0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Master interfaces
    input  logic [NUM_MASTERS-1:0]        m_cyc_i,
    input  logic [NUM_MASTERS-1:0]        m_stb_i,
    input  logic [NUM_MASTERS-1:0]        m_we_i,
    input  logic [NUM_MASTERS-1:0][AW-1:0] m_adr_i,
    input  logic [NUM_MASTERS-1:0][DW/8-1:0] m_sel_i,
    input  logic [NUM_MASTERS-1:0][DW-1:0] m_dat_i,
    output logic [NUM_MASTERS-1:0][DW-1:0] m_dat_o,
    output logic [NUM_MASTERS-1:0]        m_ack_o,
    output logic [NUM_MASTERS-1:0]        m_err_o,
    output logic [NUM_MASTERS-1:0]        m_stall_o,

    // Slave interfaces
    output logic [NUM_SLAVES-1:0]        s_cyc_o,
    output logic [NUM_SLAVES-1:0]        s_stb_o,
    output logic [NUM_SLAVES-1:0]        s_we_o,
    output logic [NUM_SLAVES-1:0][AW-1:0] s_adr_o,
    output logic [NUM_SLAVES-1:0][DW/8-1:0] s_sel_o,
    output logic [NUM_SLAVES-1:0][DW-1:0] s_dat_o,
    input  logic [NUM_SLAVES-1:0][DW-1:0] s_dat_i,
    input  logic [NUM_SLAVES-1:0]        s_ack_i,
    input  logic [NUM_SLAVES-1:0]        s_err_i,
    input  logic [NUM_SLAVES-1:0]        s_stall_i
);

    // Internal signals from arbiter to decoder
    logic             arb_cyc;
    logic             arb_stb;
    logic             arb_we;
    logic [AW-1:0]    arb_adr;
    logic [DW/8-1:0]  arb_sel;
    logic [DW-1:0]    arb_dat_w;
    logic [DW-1:0]    arb_dat_r;
    logic             arb_ack;
    logic             arb_err;
    logic             arb_stall;

    // Arbiter: multiple masters -> single master output
    wb_arbiter #(
        .NUM_MASTERS (NUM_MASTERS),
        .AW          (AW),
        .DW          (DW)
    ) u_arbiter (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // Master interfaces
        .m_cyc_i     (m_cyc_i),
        .m_stb_i     (m_stb_i),
        .m_we_i      (m_we_i),
        .m_adr_i     (m_adr_i),
        .m_sel_i     (m_sel_i),
        .m_dat_i     (m_dat_i),
        .m_dat_o     (m_dat_o),
        .m_ack_o     (m_ack_o),
        .m_err_o     (m_err_o),
        .m_stall_o   (m_stall_o),

        // To decoder
        .s_cyc_o     (arb_cyc),
        .s_stb_o     (arb_stb),
        .s_we_o      (arb_we),
        .s_adr_o     (arb_adr),
        .s_sel_o     (arb_sel),
        .s_dat_o     (arb_dat_w),
        .s_dat_i     (arb_dat_r),
        .s_ack_i     (arb_ack),
        .s_err_i     (arb_err),
        .s_stall_i   (arb_stall)
    );

    // Decoder: single master -> multiple slaves
    wb_decoder #(
        .NUM_SLAVES  (NUM_SLAVES),
        .AW          (AW),
        .DW          (DW),
        .SLAVE_BASE  (SLAVE_BASE),
        .SLAVE_MASK  (SLAVE_MASK)
    ) u_decoder (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // From arbiter
        .m_cyc_i     (arb_cyc),
        .m_stb_i     (arb_stb),
        .m_we_i      (arb_we),
        .m_adr_i     (arb_adr),
        .m_sel_i     (arb_sel),
        .m_dat_i     (arb_dat_w),
        .m_dat_o     (arb_dat_r),
        .m_ack_o     (arb_ack),
        .m_err_o     (arb_err),
        .m_stall_o   (arb_stall),

        // Slave interfaces
        .s_cyc_o     (s_cyc_o),
        .s_stb_o     (s_stb_o),
        .s_we_o      (s_we_o),
        .s_adr_o     (s_adr_o),
        .s_sel_o     (s_sel_o),
        .s_dat_o     (s_dat_o),
        .s_dat_i     (s_dat_i),
        .s_ack_i     (s_ack_i),
        .s_err_i     (s_err_i),
        .s_stall_i   (s_stall_i)
    );

endmodule
