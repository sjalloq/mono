// SPDX-License-Identifier: BSD-2-Clause
// Wishbone Round-Robin Arbiter
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Round-robin arbitration between multiple Wishbone masters.
// Supports pipelined protocol with stall signaling.

module wb_arbiter #(
    parameter int unsigned NUM_MASTERS = 2,
    parameter int unsigned AW          = 32,
    parameter int unsigned DW          = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Master interfaces (from masters)
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

    // Slave interface (to shared slave)
    output logic             s_cyc_o,
    output logic             s_stb_o,
    output logic             s_we_o,
    output logic [AW-1:0]    s_adr_o,
    output logic [DW/8-1:0]  s_sel_o,
    output logic [DW-1:0]    s_dat_o,
    input  logic [DW-1:0]    s_dat_i,
    input  logic             s_ack_i,
    input  logic             s_err_i,
    input  logic             s_stall_i
);

    // Grant signals
    logic [NUM_MASTERS-1:0] grant;
    logic [NUM_MASTERS-1:0] grant_next;
    logic [$clog2(NUM_MASTERS)-1:0] grant_idx;
    logic [$clog2(NUM_MASTERS)-1:0] last_grant;

    // Requests
    logic [NUM_MASTERS-1:0] requests;
    assign requests = m_cyc_i;

    // Find next grant using round-robin
    always_comb begin
        grant_next = '0;
        for (int i = 0; i < NUM_MASTERS; i++) begin
            int idx = (last_grant + 1 + i) % NUM_MASTERS;
            if (requests[idx] && grant_next == '0) begin
                grant_next[idx] = 1'b1;
            end
        end
    end

    // Grant register - hold grant while transaction active
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            grant <= '0;
            grant[0] <= 1'b1;  // Default grant to master 0
            last_grant <= '0;
        end else begin
            if (grant == '0 || !(|(grant & requests))) begin
                // No current grant or granted master dropped CYC
                grant <= grant_next;
                for (int i = 0; i < NUM_MASTERS; i++) begin
                    if (grant_next[i]) last_grant <= i[$clog2(NUM_MASTERS)-1:0];
                end
            end
        end
    end

    // Find grant index
    always_comb begin
        grant_idx = '0;
        for (int i = 0; i < NUM_MASTERS; i++) begin
            if (grant[i]) grant_idx = i[$clog2(NUM_MASTERS)-1:0];
        end
    end

    // Mux master signals to slave
    assign s_cyc_o = |(m_cyc_i & grant);
    assign s_stb_o = |(m_stb_i & grant);
    assign s_we_o  = m_we_i[grant_idx];
    assign s_adr_o = m_adr_i[grant_idx];
    assign s_sel_o = m_sel_i[grant_idx];
    assign s_dat_o = m_dat_i[grant_idx];

    // Distribute slave signals to masters
    always_comb begin
        for (int i = 0; i < NUM_MASTERS; i++) begin
            m_dat_o[i]   = s_dat_i;
            m_ack_o[i]   = s_ack_i && grant[i];
            m_err_o[i]   = s_err_i && grant[i];
            m_stall_o[i] = grant[i] ? s_stall_i : 1'b1;  // Stall non-granted masters
        end
    end

endmodule
