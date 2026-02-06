// SPDX-License-Identifier: Apache-2.0
// Wishbone Crossbar Testbench Wrapper
//
// Copyright (c) 2025 Mono Authors
//
// Simple 2x2 crossbar configuration for cocotb testing.
// Slave 0: 0x0000_0000 - 0x0000_FFFF
// Slave 1: 0x0001_0000 - 0x0001_FFFF

module wb_crossbar_tb
  import wb_pkg::*;
(
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

  // Address map configuration
  localparam logic [1:0][31:0] AddrBase = '{32'h0001_0000, 32'h0000_0000};
  localparam logic [1:0][31:0] AddrMask = '{32'hFFFF_0000, 32'hFFFF_0000};

  // Slave access: both masters can access both slaves (full connectivity)
  localparam logic [1:0][1:0] SlaveAccess = '{2'b11, 2'b11};

  // Pack flat cocotb signals into structs
  wb_m2s_t [1:0] m_i;
  wb_s2m_t [1:0] m_o;
  wb_m2s_t [1:0] s_o;
  wb_s2m_t [1:0] s_i;

  // Master 0
  assign m_i[0].cyc = m0_cyc_i;
  assign m_i[0].stb = m0_stb_i;
  assign m_i[0].we  = m0_we_i;
  assign m_i[0].adr = m0_adr_i;
  assign m_i[0].sel = m0_sel_i;
  assign m_i[0].dat = m0_dat_i;

  assign m0_ack_o   = m_o[0].ack;
  assign m0_err_o   = m_o[0].err;
  assign m0_stall_o = m_o[0].stall;
  assign m0_dat_o   = m_o[0].dat;

  // Master 1
  assign m_i[1].cyc = m1_cyc_i;
  assign m_i[1].stb = m1_stb_i;
  assign m_i[1].we  = m1_we_i;
  assign m_i[1].adr = m1_adr_i;
  assign m_i[1].sel = m1_sel_i;
  assign m_i[1].dat = m1_dat_i;

  assign m1_ack_o   = m_o[1].ack;
  assign m1_err_o   = m_o[1].err;
  assign m1_stall_o = m_o[1].stall;
  assign m1_dat_o   = m_o[1].dat;

  // Slave 0
  assign s0_cyc_o = s_o[0].cyc;
  assign s0_stb_o = s_o[0].stb;
  assign s0_we_o  = s_o[0].we;
  assign s0_adr_o = s_o[0].adr;
  assign s0_sel_o = s_o[0].sel;
  assign s0_dat_o = s_o[0].dat;

  assign s_i[0].ack   = s0_ack_i;
  assign s_i[0].err   = s0_err_i;
  assign s_i[0].stall = s0_stall_i;
  assign s_i[0].dat   = s0_dat_i;

  // Slave 1
  assign s1_cyc_o = s_o[1].cyc;
  assign s1_stb_o = s_o[1].stb;
  assign s1_we_o  = s_o[1].we;
  assign s1_adr_o = s_o[1].adr;
  assign s1_sel_o = s_o[1].sel;
  assign s1_dat_o = s_o[1].dat;

  assign s_i[1].ack   = s1_ack_i;
  assign s_i[1].err   = s1_err_i;
  assign s_i[1].stall = s1_stall_i;
  assign s_i[1].dat   = s1_dat_i;

  // DUT instantiation
  wb_crossbar #(
    .NumMasters  (2),
    .NumSlaves   (2),
    .SlaveAccess (SlaveAccess)
  ) u_dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),

    .cfg_addr_base_i (AddrBase),
    .cfg_addr_mask_i (AddrMask),

    .m_i             (m_i),
    .m_o             (m_o),

    .s_o             (s_o),
    .s_i             (s_i)
  );

endmodule
