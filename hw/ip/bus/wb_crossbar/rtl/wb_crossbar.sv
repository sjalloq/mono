// SPDX-License-Identifier: Apache-2.0
// Wishbone B4 Pipelined Crossbar
//
// Copyright (c) 2025 Mono Authors
//
// Configurable NxM crossbar interconnect with:
// - Priority-based arbitration (port 0 highest)
// - 1 outstanding transaction per slave
// - Error response for unmapped addresses
// - AND-OR response mux using registered slave select

module wb_crossbar #(
  parameter int unsigned NumMasters = 2,
  parameter int unsigned NumSlaves  = 2,
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  parameter logic [NumSlaves-1:0][AddrWidth-1:0] AddrBase = '0,
  parameter logic [NumSlaves-1:0][AddrWidth-1:0] AddrMask = '0,
  // Per-master slave access mask: SlaveAccess[m][s] = 1 means master m can access slave s
  // Defaults to full connectivity. Use to create sparse matrix and save logic.
  parameter logic [NumMasters-1:0][NumSlaves-1:0] SlaveAccess = '1,
  localparam int unsigned SelWidth = DataWidth / 8
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,

  // Master interfaces
  input  logic [NumMasters-1:0]                  m_cyc_i,
  input  logic [NumMasters-1:0]                  m_stb_i,
  input  logic [NumMasters-1:0]                  m_we_i,
  input  logic [NumMasters-1:0][AddrWidth-1:0]   m_adr_i,
  input  logic [NumMasters-1:0][SelWidth-1:0]    m_sel_i,
  input  logic [NumMasters-1:0][DataWidth-1:0]   m_dat_i,
  output logic [NumMasters-1:0]                  m_ack_o,
  output logic [NumMasters-1:0]                  m_err_o,
  output logic [NumMasters-1:0]                  m_stall_o,
  output logic [NumMasters-1:0][DataWidth-1:0]   m_dat_o,

  // Slave interfaces
  output logic [NumSlaves-1:0]                   s_cyc_o,
  output logic [NumSlaves-1:0]                   s_stb_o,
  output logic [NumSlaves-1:0]                   s_we_o,
  output logic [NumSlaves-1:0][AddrWidth-1:0]    s_adr_o,
  output logic [NumSlaves-1:0][SelWidth-1:0]     s_sel_o,
  output logic [NumSlaves-1:0][DataWidth-1:0]    s_dat_o,
  input  logic [NumSlaves-1:0]                   s_ack_i,
  input  logic [NumSlaves-1:0]                   s_err_i,
  input  logic [NumSlaves-1:0]                   s_stall_i,
  input  logic [NumSlaves-1:0][DataWidth-1:0]    s_dat_i
);

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================

  // Decoder outputs
  logic [NumMasters-1:0][NumSlaves-1:0]          dec_req;
  logic [NumMasters-1:0]                         dec_cyc;
  logic [NumMasters-1:0]                         dec_stb;
  logic [NumMasters-1:0]                         dec_we;
  logic [NumMasters-1:0][AddrWidth-1:0]          dec_adr;
  logic [NumMasters-1:0][SelWidth-1:0]           dec_sel;
  logic [NumMasters-1:0][DataWidth-1:0]          dec_wdat;

  // Arbiter outputs
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_stall;

  // Transposed signals for arbiters
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_req;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_cyc;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_stb;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_we;
  logic [NumSlaves-1:0][NumMasters-1:0][AddrWidth-1:0] arb_adr;
  logic [NumSlaves-1:0][NumMasters-1:0][SelWidth-1:0]  arb_sel;
  logic [NumSlaves-1:0][NumMasters-1:0][DataWidth-1:0] arb_wdat;

  // Transposed stall signals for decoders
  logic [NumMasters-1:0][NumSlaves-1:0]          dec_stall;

  // ===========================================================================
  // Signal Transpose
  // ===========================================================================

  always_comb begin
    for (int m = 0; m < NumMasters; m++) begin
      for (int s = 0; s < NumSlaves; s++) begin
        // Decoder → Arbiter
        arb_req[s][m]  = dec_req[m][s];
        arb_cyc[s][m]  = dec_cyc[m];
        arb_stb[s][m]  = dec_stb[m];
        arb_we[s][m]   = dec_we[m];
        arb_adr[s][m]  = dec_adr[m];
        arb_sel[s][m]  = dec_sel[m];
        arb_wdat[s][m] = dec_wdat[m];

        // Arbiter → Decoder
        dec_stall[m][s] = arb_stall[s][m];
      end
    end
  end

  // ===========================================================================
  // Decoders (Per Master)
  // ===========================================================================

  for (genvar m = 0; m < NumMasters; m++) begin : gen_decoders
    wb_crossbar_decoder #(
      .NumSlaves   (NumSlaves),
      .AddrWidth   (AddrWidth),
      .DataWidth   (DataWidth),
      .AddrBase    (AddrBase),
      .AddrMask    (AddrMask),
      .SlaveAccess (SlaveAccess[m])
    ) u_decoder (
      .clk_i    (clk_i),
      .rst_ni   (rst_ni),

      .m_cyc_i  (m_cyc_i[m]),
      .m_stb_i  (m_stb_i[m]),
      .m_we_i   (m_we_i[m]),
      .m_adr_i  (m_adr_i[m]),
      .m_sel_i  (m_sel_i[m]),
      .m_dat_i  (m_dat_i[m]),
      .m_ack_o  (m_ack_o[m]),
      .m_err_o  (m_err_o[m]),
      .m_stall_o(m_stall_o[m]),
      .m_dat_o  (m_dat_o[m]),

      .req_o    (dec_req[m]),
      .cyc_o    (dec_cyc[m]),
      .stb_o    (dec_stb[m]),
      .we_o     (dec_we[m]),
      .adr_o    (dec_adr[m]),
      .sel_o    (dec_sel[m]),
      .wdat_o   (dec_wdat[m]),

      .stall_i  (dec_stall[m]),

      .ack_i    (s_ack_i),
      .err_i    (s_err_i),
      .rdat_i   (s_dat_i)
    );
  end

  // ===========================================================================
  // Arbiters (Per Slave)
  // ===========================================================================

  for (genvar s = 0; s < NumSlaves; s++) begin : gen_arbiters
    wb_crossbar_arbiter #(
      .NumMasters(NumMasters),
      .AddrWidth (AddrWidth),
      .DataWidth (DataWidth)
    ) u_arbiter (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),

      .req_i   (arb_req[s]),
      .cyc_i   (arb_cyc[s]),
      .stb_i   (arb_stb[s]),
      .we_i    (arb_we[s]),
      .adr_i   (arb_adr[s]),
      .sel_i   (arb_sel[s]),
      .wdat_i  (arb_wdat[s]),

      .stall_o (arb_stall[s]),

      .cyc_o   (s_cyc_o[s]),
      .stb_o   (s_stb_o[s]),
      .we_o    (s_we_o[s]),
      .adr_o   (s_adr_o[s]),
      .sel_o   (s_sel_o[s]),
      .wdat_o  (s_dat_o[s]),

      .ack_i   (s_ack_i[s]),
      .err_i   (s_err_i[s]),
      .stall_i (s_stall_i[s])
    );
  end

endmodule
