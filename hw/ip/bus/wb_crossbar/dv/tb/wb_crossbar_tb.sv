// SPDX-License-Identifier: Apache-2.0
// Wishbone Crossbar Testbench Wrapper
//
// Copyright (c) 2025 Mono Authors
//
// Simple 2x2 crossbar configuration for cocotb testing.
// Slave 0: 0x0000_0000 - 0x0000_FFFF
// Slave 1: 0x0001_0000 - 0x0001_FFFF

module wb_crossbar_tb (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Master 0 interface
  input  logic        m0_cyc_i,
  input  logic        m0_stb_i,
  input  logic        m0_we_i,
  input  logic [31:0] m0_adr_i,
  input  logic [3:0]  m0_sel_i,
  input  logic [31:0] m0_dat_i,
  output logic        m0_ack_o,
  output logic        m0_err_o,
  output logic        m0_stall_o,
  output logic [31:0] m0_dat_o,

  // Master 1 interface
  input  logic        m1_cyc_i,
  input  logic        m1_stb_i,
  input  logic        m1_we_i,
  input  logic [31:0] m1_adr_i,
  input  logic [3:0]  m1_sel_i,
  input  logic [31:0] m1_dat_i,
  output logic        m1_ack_o,
  output logic        m1_err_o,
  output logic        m1_stall_o,
  output logic [31:0] m1_dat_o,

  // Slave 0 interface
  output logic        s0_cyc_o,
  output logic        s0_stb_o,
  output logic        s0_we_o,
  output logic [31:0] s0_adr_o,
  output logic [3:0]  s0_sel_o,
  output logic [31:0] s0_dat_o,
  input  logic        s0_ack_i,
  input  logic        s0_err_i,
  input  logic        s0_stall_i,
  input  logic [31:0] s0_dat_i,

  // Slave 1 interface
  output logic        s1_cyc_o,
  output logic        s1_stb_o,
  output logic        s1_we_o,
  output logic [31:0] s1_adr_o,
  output logic [3:0]  s1_sel_o,
  output logic [31:0] s1_dat_o,
  input  logic        s1_ack_i,
  input  logic        s1_err_i,
  input  logic        s1_stall_i,
  input  logic [31:0] s1_dat_i
);

  // Address map parameters
  localparam logic [1:0][31:0] AddrBase = '{32'h0001_0000, 32'h0000_0000};
  localparam logic [1:0][31:0] AddrMask = '{32'hFFFF_0000, 32'hFFFF_0000};

  // Slave access: both masters can access both slaves (full connectivity)
  localparam logic [1:0][1:0] SlaveAccess = '{2'b11, 2'b11};

  // Pack master signals
  logic [1:0]       m_cyc;
  logic [1:0]       m_stb;
  logic [1:0]       m_we;
  logic [1:0][31:0] m_adr;
  logic [1:0][3:0]  m_sel;
  logic [1:0][31:0] m_dat_wr;
  logic [1:0]       m_ack;
  logic [1:0]       m_err;
  logic [1:0]       m_stall;
  logic [1:0][31:0] m_dat_rd;

  assign m_cyc    = {m1_cyc_i, m0_cyc_i};
  assign m_stb    = {m1_stb_i, m0_stb_i};
  assign m_we     = {m1_we_i, m0_we_i};
  assign m_adr    = {m1_adr_i, m0_adr_i};
  assign m_sel    = {m1_sel_i, m0_sel_i};
  assign m_dat_wr = {m1_dat_i, m0_dat_i};

  assign m0_ack_o   = m_ack[0];
  assign m0_err_o   = m_err[0];
  assign m0_stall_o = m_stall[0];
  assign m0_dat_o   = m_dat_rd[0];

  assign m1_ack_o   = m_ack[1];
  assign m1_err_o   = m_err[1];
  assign m1_stall_o = m_stall[1];
  assign m1_dat_o   = m_dat_rd[1];

  // Pack slave signals
  logic [1:0]       s_cyc;
  logic [1:0]       s_stb;
  logic [1:0]       s_we;
  logic [1:0][31:0] s_adr;
  logic [1:0][3:0]  s_sel;
  logic [1:0][31:0] s_dat_wr;
  logic [1:0]       s_ack;
  logic [1:0]       s_err;
  logic [1:0]       s_stall;
  logic [1:0][31:0] s_dat_rd;

  assign s0_cyc_o = s_cyc[0];
  assign s0_stb_o = s_stb[0];
  assign s0_we_o  = s_we[0];
  assign s0_adr_o = s_adr[0];
  assign s0_sel_o = s_sel[0];
  assign s0_dat_o = s_dat_wr[0];

  assign s1_cyc_o = s_cyc[1];
  assign s1_stb_o = s_stb[1];
  assign s1_we_o  = s_we[1];
  assign s1_adr_o = s_adr[1];
  assign s1_sel_o = s_sel[1];
  assign s1_dat_o = s_dat_wr[1];

  assign s_ack    = {s1_ack_i, s0_ack_i};
  assign s_err    = {s1_err_i, s0_err_i};
  assign s_stall  = {s1_stall_i, s0_stall_i};
  assign s_dat_rd = {s1_dat_i, s0_dat_i};

  // DUT instantiation
  wb_crossbar #(
    .NumMasters  (2),
    .NumSlaves   (2),
    .AddrWidth   (32),
    .DataWidth   (32),
    .AddrBase    (AddrBase),
    .AddrMask    (AddrMask),
    .SlaveAccess (SlaveAccess)
  ) u_dut (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),

    .m_cyc_i  (m_cyc),
    .m_stb_i  (m_stb),
    .m_we_i   (m_we),
    .m_adr_i  (m_adr),
    .m_sel_i  (m_sel),
    .m_dat_i  (m_dat_wr),
    .m_ack_o  (m_ack),
    .m_err_o  (m_err),
    .m_stall_o(m_stall),
    .m_dat_o  (m_dat_rd),

    .s_cyc_o  (s_cyc),
    .s_stb_o  (s_stb),
    .s_we_o   (s_we),
    .s_adr_o  (s_adr),
    .s_sel_o  (s_sel),
    .s_dat_o  (s_dat_wr),
    .s_ack_i  (s_ack),
    .s_err_i  (s_err),
    .s_stall_i(s_stall),
    .s_dat_i  (s_dat_rd)
  );

endmodule
