// SPDX-License-Identifier: Apache-2.0
// Wishbone Crossbar Decoder
//
// Copyright (c) 2025 Mono Authors
//
// Per-master frontend handling address decode, request presentation,
// and response multiplexing. Registers the target slave on address
// phase complete for use as AND-OR mux select.

module wb_crossbar_decoder #(
  parameter int unsigned NumSlaves  = 2,
  // Slave access mask: SlaveAccess[s] = 1 means this master can access slave s
  parameter logic [NumSlaves-1:0] SlaveAccess = '1
) (
  input  logic                                   clk_i,
  input  logic                                   rst_ni,

  // Address map configuration
  input  logic [NumSlaves-1:0][31:0]             cfg_addr_base_i,
  input  logic [NumSlaves-1:0][31:0]             cfg_addr_mask_i,

  // Master interface (individual signals — unpacked by crossbar)
  input  logic                                   m_cyc_i,
  input  logic                                   m_stb_i,
  input  logic                                   m_we_i,
  input  logic [31:0]                            m_adr_i,
  input  logic [3:0]                             m_sel_i,
  input  logic [31:0]                            m_dat_i,
  output logic                                   m_ack_o,
  output logic                                   m_err_o,
  output logic                                   m_stall_o,
  output logic [31:0]                            m_dat_o,

  // To arbiters
  output logic [NumSlaves-1:0]                   req_o,
  output logic                                   cyc_o,
  output logic                                   stb_o,
  output logic                                   we_o,
  output logic [31:0]                            adr_o,
  output logic [3:0]                             sel_o,
  output logic [31:0]                            wdat_o,

  // From arbiters
  input  logic [NumSlaves-1:0]                   stall_i,

  // From slaves
  input  logic [NumSlaves-1:0]                   ack_i,
  input  logic [NumSlaves-1:0]                   err_i,
  input  logic [NumSlaves-1:0][31:0]             rdat_i
);

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================

  // Address decode
  logic [NumSlaves-1:0] slave_sel;

  // Transaction state
  logic [NumSlaves-1:0] pending_slave_q;
  logic                 pending_unmapped_q;  // Default slave for unmapped addresses
  logic                 busy;
  logic                 resp_received;

  // Request handling
  logic req_stall;
  logic unmapped;
  logic txn_accepted;

  // ===========================================================================
  // Address Decode
  // ===========================================================================

  // Decode address and mask with slave access permissions
  for (genvar s = 0; s < NumSlaves; s++) begin : gen_decode
    assign slave_sel[s] = SlaveAccess[s] &&
                          ((m_adr_i & cfg_addr_mask_i[s]) == (cfg_addr_base_i[s] & cfg_addr_mask_i[s]));
  end

  // ===========================================================================
  // Request Path
  // ===========================================================================

  // Response completing this cycle - not busy, can accept new request
  // Include pending_unmapped_q as it will respond with ERR this cycle
  assign resp_received = |(pending_slave_q & (ack_i | err_i)) || pending_unmapped_q;
  assign busy = (|pending_slave_q || pending_unmapped_q) && !resp_received;

  // Request to arbiters: valid transaction, not busy
  assign req_o = (m_cyc_i && m_stb_i && !busy) ? slave_sel : '0;

  // Forward master signals
  assign cyc_o  = m_cyc_i;
  assign stb_o  = m_stb_i && !busy;
  assign we_o   = m_we_i;
  assign adr_o  = m_adr_i;
  assign sel_o  = m_sel_i;
  assign wdat_o = m_dat_i;

  // Stall handling
  assign req_stall = |(req_o & stall_i);
  assign unmapped  = m_cyc_i && m_stb_i && !busy && (slave_sel == '0);
  assign m_stall_o = busy || req_stall;

  // ===========================================================================
  // Response Path (AND-OR Mux)
  // ===========================================================================

  always_comb begin
    m_ack_o = 1'b0;
    m_err_o = 1'b0;
    m_dat_o = '0;

    for (int s = 0; s < NumSlaves; s++) begin
      m_ack_o = m_ack_o | (pending_slave_q[s] & ack_i[s]);
      m_err_o = m_err_o | (pending_slave_q[s] & err_i[s]);
      m_dat_o = m_dat_o | ({32{pending_slave_q[s]}} & rdat_i[s]);
    end

    // Default slave: ERR response for unmapped addresses in data phase
    if (pending_unmapped_q) begin
      m_err_o = 1'b1;
    end
  end

  // ===========================================================================
  // State Machine
  // ===========================================================================

  assign txn_accepted = (|req_o) && !req_stall;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_slave_q    <= '0;
      pending_unmapped_q <= 1'b0;
    end else begin
      // New transaction takes priority - overwrites pending slave
      if (txn_accepted) begin
        pending_slave_q    <= slave_sel;
        pending_unmapped_q <= 1'b0;
      end else if (unmapped) begin
        // Unmapped address accepted - default slave will respond next cycle
        pending_slave_q    <= '0;
        pending_unmapped_q <= 1'b1;
      end else if (resp_received) begin
        pending_slave_q    <= '0;
        pending_unmapped_q <= 1'b0;
      end
    end
  end

endmodule
