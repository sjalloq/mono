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

module wb_crossbar
    import wb_pkg::*;
#(
  parameter int unsigned NumMasters = 2,
  parameter int unsigned NumSlaves  = 2,
  // Per-master slave access mask: SlaveAccess[m][s] = 1 means master m can access slave s
  // Defaults to full connectivity. Use to create sparse matrix and save logic.
  parameter logic [NumMasters-1:0][NumSlaves-1:0] SlaveAccess = '1
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,

  // Address map configuration
  input  logic [NumSlaves-1:0][31:0]             cfg_addr_base_i,
  input  logic [NumSlaves-1:0][31:0]             cfg_addr_mask_i,

  // Master interfaces
  input  wb_m2s_t [NumMasters-1:0]               m_i,
  output wb_s2m_t [NumMasters-1:0]               m_o,

  // Slave interfaces
  output wb_m2s_t [NumSlaves-1:0]                s_o,
  input  wb_s2m_t [NumSlaves-1:0]                s_i
);

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================

  // Unpacked master signals (from struct arrays)
  logic [NumMasters-1:0]        m_cyc, m_stb, m_we;
  logic [NumMasters-1:0][31:0]  m_adr, m_dat_w;
  logic [NumMasters-1:0][3:0]   m_sel;

  // Unpacked slave signals (from struct arrays)
  logic [NumSlaves-1:0]         s_ack, s_err, s_stall;
  logic [NumSlaves-1:0][31:0]   s_dat_r;

  // Decoder outputs
  logic [NumMasters-1:0][NumSlaves-1:0]          dec_req;
  logic [NumMasters-1:0]                         dec_cyc;
  logic [NumMasters-1:0]                         dec_stb;
  logic [NumMasters-1:0]                         dec_we;
  logic [NumMasters-1:0][31:0]                   dec_adr;
  logic [NumMasters-1:0][3:0]                    dec_sel;
  logic [NumMasters-1:0][31:0]                   dec_wdat;

  // Arbiter outputs
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_stall;

  // Transposed signals for arbiters
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_req;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_cyc;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_stb;
  logic [NumSlaves-1:0][NumMasters-1:0]          arb_we;
  logic [NumSlaves-1:0][NumMasters-1:0][31:0]    arb_adr;
  logic [NumSlaves-1:0][NumMasters-1:0][3:0]     arb_sel;
  logic [NumSlaves-1:0][NumMasters-1:0][31:0]    arb_wdat;

  // Transposed stall signals for decoders
  logic [NumMasters-1:0][NumSlaves-1:0]          dec_stall;

  // Master response from decoders
  logic [NumMasters-1:0]        m_ack, m_err, m_stall_out;
  logic [NumMasters-1:0][31:0]  m_dat_r;

  // Slave forward from arbiters
  logic [NumSlaves-1:0]         s_cyc, s_stb, s_we;
  logic [NumSlaves-1:0][31:0]   s_adr, s_dat_w;
  logic [NumSlaves-1:0][3:0]    s_sel;

  // ===========================================================================
  // Struct Unpack / Repack
  // ===========================================================================

  for (genvar m = 0; m < NumMasters; m++) begin : gen_m_unpack
    assign m_cyc[m]   = m_i[m].cyc;
    assign m_stb[m]   = m_i[m].stb;
    assign m_we[m]    = m_i[m].we;
    assign m_adr[m]   = m_i[m].adr;
    assign m_sel[m]   = m_i[m].sel;
    assign m_dat_w[m] = m_i[m].dat;
    assign m_o[m]     = '{dat: m_dat_r[m], ack: m_ack[m], err: m_err[m], stall: m_stall_out[m]};
  end

  for (genvar s = 0; s < NumSlaves; s++) begin : gen_s_unpack
    assign s_ack[s]   = s_i[s].ack;
    assign s_err[s]   = s_i[s].err;
    assign s_stall[s] = s_i[s].stall;
    assign s_dat_r[s] = s_i[s].dat;
    assign s_o[s]     = '{cyc: s_cyc[s], stb: s_stb[s], we: s_we[s],
                          adr: s_adr[s], sel: s_sel[s], dat: s_dat_w[s]};
  end

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

    // Mask slave responses to only accessible slaves, so synthesis eliminates
    // combinational paths from inaccessible slaves through the response mux.
    logic [NumSlaves-1:0]        masked_ack, masked_err;
    logic [NumSlaves-1:0][31:0]  masked_rdat;

    for (genvar s = 0; s < NumSlaves; s++) begin : gen_resp_mask
      if (SlaveAccess[m][s]) begin : gen_connected
        assign masked_ack[s]  = s_ack[s];
        assign masked_err[s]  = s_err[s];
        assign masked_rdat[s] = s_dat_r[s];
      end else begin : gen_tied_off
        assign masked_ack[s]  = 1'b0;
        assign masked_err[s]  = 1'b0;
        assign masked_rdat[s] = '0;
      end
    end

    wb_crossbar_decoder #(
      .NumSlaves   (NumSlaves),
      .SlaveAccess (SlaveAccess[m])
    ) u_decoder (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),

      .cfg_addr_base_i (cfg_addr_base_i),
      .cfg_addr_mask_i (cfg_addr_mask_i),

      .m_cyc_i  (m_cyc[m]),
      .m_stb_i  (m_stb[m]),
      .m_we_i   (m_we[m]),
      .m_adr_i  (m_adr[m]),
      .m_sel_i  (m_sel[m]),
      .m_dat_i  (m_dat_w[m]),
      .m_ack_o  (m_ack[m]),
      .m_err_o  (m_err[m]),
      .m_stall_o(m_stall_out[m]),
      .m_dat_o  (m_dat_r[m]),

      .req_o    (dec_req[m]),
      .cyc_o    (dec_cyc[m]),
      .stb_o    (dec_stb[m]),
      .we_o     (dec_we[m]),
      .adr_o    (dec_adr[m]),
      .sel_o    (dec_sel[m]),
      .wdat_o   (dec_wdat[m]),

      .stall_i  (dec_stall[m]),

      .ack_i    (masked_ack),
      .err_i    (masked_err),
      .rdat_i   (masked_rdat)
    );
  end

  // ===========================================================================
  // Arbiters (Per Slave)
  // ===========================================================================

  for (genvar s = 0; s < NumSlaves; s++) begin : gen_arbiters
    wb_crossbar_arbiter #(
      .NumMasters(NumMasters)
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

      .cyc_o   (s_cyc[s]),
      .stb_o   (s_stb[s]),
      .we_o    (s_we[s]),
      .adr_o   (s_adr[s]),
      .sel_o   (s_sel[s]),
      .wdat_o  (s_dat_w[s]),

      .ack_i   (s_ack[s]),
      .err_i   (s_err[s]),
      .stall_i (s_stall[s])
    );
  end

endmodule
