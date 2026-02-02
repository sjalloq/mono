// SPDX-License-Identifier: BSD-2-Clause
// USB UART RX Control Logic
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Pure control logic for RX data path — no FIFO storage.
// FIFO storage is provided by two external prim_fifo_sync instances
// (data FIFO and length FIFO).
//
// Dual-FIFO RX for USB->CPU data path:
// - Data FIFO: stores payload words
// - Len FIFO: stores packet lengths (pushed when rx_last seen)
//
// RX_LEN register shows current packet's byte count. After CPU reads
// all words for a packet, the Len FIFO automatically advances.

module usb_uart_rx_ctrl #(
    parameter int unsigned LEN_DEPTH  = 4
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // USB Stream Input (usb_channel_description)
    // =========================================================================
    input  logic             rx_valid_i,
    output logic             rx_ready_o,
    input  logic [31:0]      rx_length_i,
    input  logic             rx_last_i,

    // =========================================================================
    // Data FIFO Interface (external prim_fifo_sync)
    // =========================================================================
    output logic             data_fifo_wvalid_o,
    input  logic             data_fifo_wready_i,
    input  logic [31:0]      data_fifo_rdata_i,
    input  logic             data_fifo_rvalid_i,
    output logic             data_fifo_rready_o,
    input  logic             data_fifo_full_i,

    // =========================================================================
    // Length FIFO Interface (external prim_fifo_sync)
    // =========================================================================
    output logic             len_fifo_wvalid_o,
    output logic [31:0]      len_fifo_wdata_o,
    input  logic [31:0]      len_fifo_rdata_i,
    input  logic             len_fifo_rvalid_i,
    output logic             len_fifo_rready_o,
    input  logic             len_fifo_full_i,
    input  logic [LenDepthW-1:0] len_fifo_depth_i,

    // =========================================================================
    // FIFO Control
    // =========================================================================
    output logic             fifo_clr_o,

    // =========================================================================
    // CSR Read Interface
    // =========================================================================
    input  logic             cpu_rd_req_i,
    output logic [31:0]      cpu_rd_data_o,
    output logic [31:0]      cpu_rx_len_o,

    // =========================================================================
    // Control
    // =========================================================================
    input  logic             enable_i,
    input  logic             invalidate_i,

    // =========================================================================
    // Status
    // =========================================================================
    output logic             rx_valid_o,
    output logic             rx_full_o,
    output logic [3:0]       rx_packets_o,

    // =========================================================================
    // Overflow
    // =========================================================================
    output logic             data_overflow_o,
    output logic             len_overflow_o
);

    // =========================================================================
    // Parameters
    // =========================================================================

    localparam int unsigned LenDepthW = prim_util_pkg::vbits(LEN_DEPTH + 1);

    // =========================================================================
    // Read Controller State
    // =========================================================================

    logic [31:0] words_remaining_q, words_remaining_d;
    logic packet_active_q, packet_active_d;

    // =========================================================================
    // USB Stream Interface
    // =========================================================================

    // Accept data when enabled, data FIFO has space, and len FIFO has space
    // if this is the last beat
    assign rx_ready_o = enable_i && data_fifo_wready_i &&
                        (!rx_last_i || !len_fifo_full_i);

    // Data FIFO write: accepted beat pushes data
    logic data_wr_en;
    assign data_wr_en = rx_valid_i && rx_ready_o;
    assign data_fifo_wvalid_o = data_wr_en;
    // Note: data FIFO wdata is rx_data_i, connected at parent level

    // Len FIFO write: push length on accepted last beat
    logic len_wr_en;
    assign len_wr_en = rx_valid_i && rx_ready_o && rx_last_i;
    assign len_fifo_wvalid_o = len_wr_en;
    assign len_fifo_wdata_o  = rx_length_i;

    // =========================================================================
    // CSR Interface
    // =========================================================================

    // RX_LEN: peek at Len FIFO head (0 if empty)
    assign cpu_rx_len_o = len_fifo_rvalid_i ? len_fifo_rdata_i : 32'd0;

    // RX_DATA: peek at Data FIFO head
    assign cpu_rd_data_o = data_fifo_rdata_i;

    // Pop data FIFO on CPU read
    assign data_fifo_rready_o = cpu_rd_req_i && data_fifo_rvalid_i;

    // =========================================================================
    // Status Outputs
    // =========================================================================

    assign rx_valid_o   = len_fifo_rvalid_i;
    assign rx_full_o    = data_fifo_full_i;

    // Zero-extend len_fifo_depth to 4 bits
    assign rx_packets_o = 4'(len_fifo_depth_i);

    // =========================================================================
    // Overflow Detection
    // =========================================================================

    assign data_overflow_o = rx_valid_i && enable_i && !data_fifo_wready_i;
    assign len_overflow_o  = rx_valid_i && rx_last_i && enable_i && len_fifo_full_i;

    // =========================================================================
    // FIFO Clear
    // =========================================================================

    assign fifo_clr_o = invalidate_i;

    // =========================================================================
    // Len FIFO Read (packet consumption tracking)
    // =========================================================================

    always_comb begin
        words_remaining_d = words_remaining_q;
        packet_active_d   = packet_active_q;
        len_fifo_rready_o = 1'b0;

        if (invalidate_i) begin
            words_remaining_d = '0;
            packet_active_d   = 1'b0;
        end else if (cpu_rd_req_i && data_fifo_rvalid_i) begin
            // CPU is reading a data word
            if (!packet_active_q && len_fifo_rvalid_i) begin
                // Starting a new packet - calculate words from length
                // words = ceil(len / 4) = (len + 3) / 4
                words_remaining_d = ((cpu_rx_len_o + 32'd3) >> 2);
                packet_active_d   = 1'b1;
            end

            if (packet_active_q || len_fifo_rvalid_i) begin
                if (words_remaining_q <= 1) begin
                    // Last word of packet - pop Len FIFO
                    len_fifo_rready_o = 1'b1;
                    packet_active_d   = 1'b0;
                    words_remaining_d = '0;
                end else begin
                    words_remaining_d = words_remaining_q - 1;
                end
            end
        end
    end

    // =========================================================================
    // Sequential Logic
    // =========================================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            words_remaining_q <= '0;
            packet_active_q   <= 1'b0;
        end else begin
            words_remaining_q <= words_remaining_d;
            packet_active_q   <= packet_active_d;
        end
    end

endmodule
