// SPDX-License-Identifier: BSD-2-Clause
// Wishbone Address Decoder
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Routes master transactions to appropriate slaves based on address.
// Supports pipelined protocol with proper stall handling.

module wb_decoder #(
    parameter int unsigned NUM_SLAVES = 4,
    parameter int unsigned AW         = 32,
    parameter int unsigned DW         = 32,
    // Base addresses for each slave (must be provided)
    parameter logic [NUM_SLAVES-1:0][AW-1:0] SLAVE_BASE = '0,
    // Address masks for each slave (1s for bits that must match base)
    parameter logic [NUM_SLAVES-1:0][AW-1:0] SLAVE_MASK = '0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Master interface (from arbiter)
    input  logic             m_cyc_i,
    input  logic             m_stb_i,
    input  logic             m_we_i,
    input  logic [AW-1:0]    m_adr_i,
    input  logic [DW/8-1:0]  m_sel_i,
    input  logic [DW-1:0]    m_dat_i,
    output logic [DW-1:0]    m_dat_o,
    output logic             m_ack_o,
    output logic             m_err_o,
    output logic             m_stall_o,

    // Slave interfaces (to slaves)
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

    // Slave select based on address
    logic [NUM_SLAVES-1:0] slave_sel;
    logic no_slave_match;

    // Address decode
    always_comb begin
        slave_sel = '0;
        for (int i = 0; i < NUM_SLAVES; i++) begin
            if ((m_adr_i & SLAVE_MASK[i]) == (SLAVE_BASE[i] & SLAVE_MASK[i])) begin
                slave_sel[i] = 1'b1;
            end
        end
    end

    assign no_slave_match = (slave_sel == '0);

    // Register slave selection for response routing
    logic [NUM_SLAVES-1:0] slave_sel_q;
    logic no_slave_match_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            slave_sel_q <= '0;
            no_slave_match_q <= 1'b0;
        end else if (m_cyc_i && m_stb_i && !m_stall_o) begin
            slave_sel_q <= slave_sel;
            no_slave_match_q <= no_slave_match;
        end else if (!m_cyc_i) begin
            slave_sel_q <= '0;
            no_slave_match_q <= 1'b0;
        end
    end

    // Distribute master signals to slaves
    always_comb begin
        for (int i = 0; i < NUM_SLAVES; i++) begin
            s_cyc_o[i] = m_cyc_i && slave_sel[i];
            s_stb_o[i] = m_stb_i && slave_sel[i];
            s_we_o[i]  = m_we_i;
            s_adr_o[i] = m_adr_i;
            s_sel_o[i] = m_sel_i;
            s_dat_o[i] = m_dat_i;
        end
    end

    // Mux slave responses to master
    always_comb begin
        m_dat_o = '0;
        m_ack_o = 1'b0;
        m_err_o = no_slave_match_q && (|slave_sel_q == 1'b0);  // Error if no match

        for (int i = 0; i < NUM_SLAVES; i++) begin
            if (slave_sel_q[i]) begin
                m_dat_o = s_dat_i[i];
                m_ack_o = s_ack_i[i];
                m_err_o = s_err_i[i];
            end
        end

        // Generate error response for invalid addresses
        if (no_slave_match_q) begin
            m_err_o = 1'b1;
            m_ack_o = 1'b0;
        end
    end

    // Stall if selected slave stalls
    always_comb begin
        m_stall_o = 1'b0;
        for (int i = 0; i < NUM_SLAVES; i++) begin
            if (slave_sel[i]) begin
                m_stall_o = s_stall_i[i];
            end
        end
    end

endmodule
