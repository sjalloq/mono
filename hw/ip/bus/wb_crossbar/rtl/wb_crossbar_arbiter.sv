// SPDX-License-Identifier: Apache-2.0
// Wishbone Crossbar Arbiter
//
// Copyright (c) 2025 Mono Authors
//
// Per-slave priority arbiter. Lower master index has higher priority.
// Stalls all masters while a transaction is in flight.

module wb_crossbar_arbiter
  import wb_crossbar_pkg::*;
#(
  parameter int unsigned NumMasters = 2,
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  localparam int unsigned SelWidth  = DataWidth / 8
) (
  input  logic                                    clk_i,
  input  logic                                    rst_ni,

  // From decoders
  input  logic [NumMasters-1:0]                   req_i,
  input  logic [NumMasters-1:0]                   cyc_i,
  input  logic [NumMasters-1:0]                   stb_i,
  input  logic [NumMasters-1:0]                   we_i,
  input  logic [NumMasters-1:0][AddrWidth-1:0]    adr_i,
  input  logic [NumMasters-1:0][SelWidth-1:0]     sel_i,
  input  logic [NumMasters-1:0][DataWidth-1:0]    wdat_i,

  // To decoders
  output logic [NumMasters-1:0]                   stall_o,

  // To slave
  output logic                                    cyc_o,
  output logic                                    stb_o,
  output logic                                    we_o,
  output logic [AddrWidth-1:0]                    adr_o,
  output logic [SelWidth-1:0]                     sel_o,
  output logic [DataWidth-1:0]                    wdat_o,

  // From slave
  input  logic                                    ack_i,
  input  logic                                    err_i,
  input  logic                                    stall_i
);

  // ===========================================================================
  // Signal Declarations
  // ===========================================================================

  localparam int unsigned MasterIdxW = $clog2(NumMasters) > 0 ? $clog2(NumMasters) : 1;

  // State
  arb_state_e state_q, state_d;

  // Priority selection
  logic [NumMasters-1:0]    winner_oh;
  logic                     winner_valid;
  logic [MasterIdxW-1:0]    winner_idx;

  // Registered winner for data phase (one-hot)
  logic [NumMasters-1:0]    active_master_q;

  // Pipelined acceptance: can accept when idle or completing
  logic                     can_accept;

  // ===========================================================================
  // Priority Encoder
  // ===========================================================================

  always_comb begin
    winner_oh    = '0;
    winner_valid = 1'b0;
    winner_idx   = '0;

    for (int m = 0; m < NumMasters; m++) begin
      if (req_i[m] && !winner_valid) begin
        winner_oh[m] = 1'b1;
        winner_valid = 1'b1;
        winner_idx   = MasterIdxW'(m);
      end
    end
  end

  // ===========================================================================
  // State Machine
  // ===========================================================================

  always_comb begin
    state_d = state_q;

    unique case (state_q)
      StIdle: begin
        if (winner_valid && !stall_i) begin
          state_d = StBusy;
        end
      end
      StBusy: begin
        if (ack_i || err_i) begin
          // Completing: check if new request is ready (pipelined)
          if (winner_valid && !stall_i) begin
            state_d = StBusy;  // Stay busy for back-to-back
          end else begin
            state_d = StIdle;
          end
        end
      end
      default: begin
        state_d = StIdle;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= StIdle;
      active_master_q <= '0;
    end else begin
      state_q <= state_d;
      // Register winning master (one-hot) when starting transaction (or back-to-back)
      if (can_accept && winner_valid && !stall_i) begin
        active_master_q <= winner_oh;
      end else if (state_q == StBusy && (ack_i || err_i) && !winner_valid) begin
        // Completing with no follow-on request: clear active
        active_master_q <= '0;
      end
    end
  end

  // ===========================================================================
  // Forward Path (Master to Slave Mux)
  // ===========================================================================

  // Can accept new request when idle, or when busy but completing (pipelined)
  assign can_accept = (state_q == StIdle) ||
                      (state_q == StBusy && (ack_i || err_i));

  always_comb begin
    cyc_o  = 1'b0;
    stb_o  = 1'b0;
    we_o   = 1'b0;
    adr_o  = '0;
    sel_o  = '0;
    wdat_o = '0;

    if (can_accept && winner_valid) begin
      // Address phase: forward all signals from winning master
      // This works for both idle start and pipelined back-to-back
      cyc_o  = cyc_i[winner_idx];
      stb_o  = stb_i[winner_idx];
      we_o   = we_i[winner_idx];
      adr_o  = adr_i[winner_idx];
      sel_o  = sel_i[winner_idx];
      wdat_o = wdat_i[winner_idx];
    end else if (state_q == StBusy) begin
      // Data phase: keep CYC asserted from registered master (one-hot mux)
      cyc_o = |(cyc_i & active_master_q);
    end
  end

  // ===========================================================================
  // Stall Generation
  // ===========================================================================

  always_comb begin
    for (int m = 0; m < NumMasters; m++) begin
      if (state_q == StBusy && !(ack_i || err_i)) begin
        stall_o[m] = req_i[m];       // Busy (not completing): stall all requesters
      end else if (winner_oh[m]) begin
        stall_o[m] = stall_i;        // Winner: pass through slave stall
      end else begin
        stall_o[m] = req_i[m];       // Loser: stalled
      end
    end
  end

endmodule
