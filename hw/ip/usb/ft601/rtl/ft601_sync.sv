// SPDX-License-Identifier: BSD-2-Clause
// FT601 USB 3.0 Synchronous FIFO PHY
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// FSM based on PCILeech pcileech_ft601.sv timing.
// Provides stream interfaces for USB communication with proper
// wait states and cooldown periods for reliable FT601 operation.
//
// This module does NOT instantiate tristate buffers - those belong
// at the toplevel. Instead it provides data_o, data_i, and data_oe
// signals for external tristate control.
//
// RX Timing (3 data words):
//
//   clk     ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
//            └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘
//
//   rxf_n   ─────┐                               ┌───────
//                └───────────────────────────────┘
//
//   oe_n    ─────────────┐                           ┌───
//                        └───────────────────────────┘
//
//   rd_n    ─────────────────┐                       ┌───
//                            └───────────────────────┘
//
//   data    ─────────────────────X D0 X D1 X D2 X────────
//
//   state    IDLE W1  W2  W3  ACT  ACT  ACT  CD1 CD2
//
// TX Timing:
//
//   clk     ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
//            └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘
//
//   txe_n   ─────┐               ┌─────────
//                └───────────────┘
//
//   wr_n    ─────────────┐   ┌─────────────
//                        └───┘
//
//   data    ─────────X D0 X D1 X D2 X──────
//
//   state    IDLE W1  W2  ACTIVE   CD1 CD2

module ft601_sync #(
    parameter int unsigned DW = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // FT601 control signals (active low where noted)
    input  logic             rxf_ni,     // RX FIFO not empty (active low)
    input  logic             txe_ni,     // TX FIFO not full (active low)
    output logic             rd_no,      // Read strobe (active low)
    output logic             wr_no,      // Write strobe (active low)
    output logic             oe_no,      // Output enable to FT601 (active low)
    output logic             siwu_no,    // Send immediate / wake up (active low)
    output logic             rst_no,     // Reset to FT601 (active low)

    // Data bus (directly to external tristate at toplevel)
    input  logic [DW-1:0]    data_i,
    output logic [DW-1:0]    data_o,
    output logic             data_oe,    // 1=drive, 0=hi-Z
    output logic [DW/8-1:0]  be_o,
    output logic             be_oe,

    // RX stream interface (data received from USB host)
    // FT601 doesn't support backpressure, data must be consumed immediately
    output logic [DW-1:0]    rx_data_o,
    output logic             rx_valid_o,

    // TX stream interface (data to send to USB host)
    input  logic [DW-1:0]    tx_data_i,
    input  logic             tx_valid_i,
    output logic             tx_ready_o
);

  // ===========================================================================
  // Types
  // ===========================================================================

  typedef enum logic [3:0] {
    StIdle        = 4'h0,
    StRxWait1     = 4'h2,
    StRxWait2     = 4'h3,
    StRxWait3     = 4'h4,
    StRxActive    = 4'h5,
    StRxCooldown1 = 4'h6,
    StRxCooldown2 = 4'h7,
    StTxWait1     = 4'h8,
    StTxWait2     = 4'h9,
    StTxActive    = 4'hA,
    StTxCooldown1 = 4'hB,
    StTxCooldown2 = 4'hC
  } ft601_state_e;

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================

  ft601_state_e state_q, state_d;

  // Active high versions of FT601 status signals
  logic rxf;
  logic txe;

  // Registered control outputs
  logic rd_n_q, rd_n_d;
  logic wr_n_q, wr_n_d;
  logic oe_n_q, oe_n_d;
  logic data_oe_q, data_oe_d;

  // RX data path
  logic [DW-1:0] rx_data_d, rx_data_q;
  logic          rx_valid_d, rx_valid_q;

  // TX data path
  logic [DW-1:0] tx_data_d, tx_data_q;
  logic          tx_ready_d, tx_ready_q;

  // State decode signals
  logic in_rx_oe_states;
  logic in_rx_oe_n_states;
  logic in_rx_rd_states;
  logic tx_active;
  logic tx_latch;

  // ===========================================================================
  // Combinational Logic
  // ===========================================================================

  assign rxf = !rxf_ni;
  assign txe = !txe_ni;

  assign in_rx_oe_states = (state_q == StRxWait2) || (state_q == StRxWait3) ||
                           (state_q == StRxActive) || (state_q == StRxCooldown1) ||
                           (state_q == StRxCooldown2);

  assign in_rx_oe_n_states = (state_q == StRxWait2) || (state_q == StRxWait3) ||
                             (state_q == StRxActive);

  assign in_rx_rd_states = (state_q == StRxWait3) || (state_q == StRxActive);

  assign tx_active = txe && (state_q == StTxActive);

  assign tx_latch = ((state_q == StTxWait2) && tx_valid_i) ||
                    (tx_active && tx_valid_i);

  // ===========================================================================
  // Next State Logic
  // ===========================================================================

  always_comb begin
    state_d = state_q;

    unique case (state_q)
      StIdle:        state_d = rxf                  ? StRxWait1     :
                               (txe && tx_valid_i) ? StTxWait1     : StIdle;

      StRxWait1:     state_d = !rxf ? StRxCooldown1 : StRxWait2;
      StRxWait2:     state_d = !rxf ? StRxCooldown1 : StRxWait3;
      StRxWait3:     state_d = !rxf ? StRxCooldown1 : StRxActive;
      StRxActive:    state_d = !rxf ? StRxCooldown1 : StRxActive;
      StRxCooldown1: state_d = StRxCooldown2;
      StRxCooldown2: state_d = StIdle;

      StTxWait1:     state_d = !txe ? StTxCooldown1 : StTxWait2;
      StTxWait2:     state_d = !txe ? StTxCooldown1 : StTxActive;
      StTxActive:    state_d = (!txe || !tx_valid_i) ? StTxCooldown1 : StTxActive;
      StTxCooldown1: state_d = StTxCooldown2;
      StTxCooldown2: state_d = StIdle;

      default:       state_d = StIdle;
    endcase
  end

  // ===========================================================================
  // Control Signal Logic
  // ===========================================================================

  always_comb begin
    // Control outputs
    data_oe_d = rxf_ni || !in_rx_oe_states;
    oe_n_d    = rxf_ni || !in_rx_oe_n_states;
    rd_n_d    = rxf_ni || !in_rx_rd_states;
    wr_n_d    = !(txe && (state_q == StTxActive) && tx_valid_i);

    // RX data path
    rx_data_d  = data_i;
    rx_valid_d = rxf && (state_q == StRxActive);

    // TX data path
    tx_data_d  = tx_latch ? tx_data_i : tx_data_q;
    tx_ready_d = tx_latch;
  end

  // ===========================================================================
  // Registers
  // ===========================================================================

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= StIdle;
      rd_n_q     <= '1;
      wr_n_q     <= '1;
      oe_n_q     <= '1;
      data_oe_q  <= '1;
      rx_data_q  <= '0;
      rx_valid_q <= '0;
      tx_data_q  <= '0;
      tx_ready_q <= '0;
    end else begin
      state_q    <= state_d;
      rd_n_q     <= rd_n_d;
      wr_n_q     <= wr_n_d;
      oe_n_q     <= oe_n_d;
      data_oe_q  <= data_oe_d;
      rx_data_q  <= rx_data_d;
      rx_valid_q <= rx_valid_d;
      tx_data_q  <= tx_data_d;
      tx_ready_q <= tx_ready_d;
    end
  end

  // ===========================================================================
  // Output Assignments
  // ===========================================================================

  assign rd_no   = rd_n_q;
  assign wr_no   = wr_n_q;
  assign oe_no   = oe_n_q;
  assign data_oe = data_oe_q;
  assign be_oe   = data_oe_q;

  assign siwu_no = '1;
  assign rst_no  = '1;

  assign data_o = tx_data_q;
  assign be_o   = '1;

  assign rx_data_o  = rx_data_q;
  assign rx_valid_o = rx_valid_q;

  assign tx_ready_o = tx_ready_q;

endmodule
