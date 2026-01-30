// SPDX-License-Identifier: BSD-2-Clause
// USB UART RX FIFO with Packet Boundary Tracking
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Dual-FIFO RX for USB->CPU data path:
// - Data FIFO: stores payload words
// - Len FIFO: stores packet lengths (pushed when rx_last seen)
//
// RX_LEN register shows current packet's byte count. After CPU reads
// all words for a packet, the Len FIFO automatically advances.

module usb_uart_rx_fifo #(
    parameter int unsigned DATA_DEPTH = 64,
    parameter int unsigned LEN_DEPTH  = 4
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // USB stream input (usb_channel_description)
    input  logic             rx_valid_i,
    output logic             rx_ready_o,
    input  logic [31:0]      rx_data_i,
    input  logic [31:0]      rx_length_i,
    input  logic             rx_last_i,

    // CSR read interface
    input  logic             cpu_rd_req_i,    // CPU reads rx_data register
    output logic [31:0]      cpu_rd_data_o,   // Data word to CPU
    output logic [31:0]      cpu_rx_len_o,    // Current packet byte count

    // Control
    input  logic             enable_i,
    input  logic             sw_flush_i,      // Clear both FIFOs

    // Status
    output logic             rx_valid_o,      // Packet available (Len FIFO not empty)
    output logic             rx_full_o,       // Data FIFO full
    output logic [3:0]       rx_packets_o,    // Number of queued packets

    // Overflow indicators (active-high pulse)
    output logic             data_overflow_o, // Data FIFO overflow attempt
    output logic             len_overflow_o   // Len FIFO overflow attempt
);

    // =========================================================================
    // Parameters
    // =========================================================================

    localparam int unsigned DATA_ADDR_W = $clog2(DATA_DEPTH);
    localparam int unsigned LEN_ADDR_W  = $clog2(LEN_DEPTH);

    // =========================================================================
    // Data FIFO Signals
    // =========================================================================

    logic [31:0] data_mem [DATA_DEPTH];
    logic [DATA_ADDR_W:0] data_wr_ptr_q, data_wr_ptr_d;
    logic [DATA_ADDR_W:0] data_rd_ptr_q, data_rd_ptr_d;

    logic [DATA_ADDR_W:0] data_level;
    logic data_full, data_empty;

    assign data_level = data_wr_ptr_q - data_rd_ptr_q;
    assign data_full  = (data_level == DATA_DEPTH[DATA_ADDR_W:0]);
    assign data_empty = (data_level == '0);

    logic [DATA_ADDR_W-1:0] data_wr_addr, data_rd_addr;
    assign data_wr_addr = data_wr_ptr_q[DATA_ADDR_W-1:0];
    assign data_rd_addr = data_rd_ptr_q[DATA_ADDR_W-1:0];

    // =========================================================================
    // Len FIFO Signals
    // =========================================================================

    logic [31:0] len_mem [LEN_DEPTH];
    logic [LEN_ADDR_W:0] len_wr_ptr_q, len_wr_ptr_d;
    logic [LEN_ADDR_W:0] len_rd_ptr_q, len_rd_ptr_d;

    logic [LEN_ADDR_W:0] len_level;
    logic len_full, len_empty;

    assign len_level = len_wr_ptr_q - len_rd_ptr_q;
    assign len_full  = (len_level == LEN_DEPTH[LEN_ADDR_W:0]);
    assign len_empty = (len_level == '0);

    // Extend len_level to 4 bits for status output (handles small LEN_DEPTH)
    logic [3:0] len_level_ext;
    assign len_level_ext = {{(4-LEN_ADDR_W-1){1'b0}}, len_level};

    logic [LEN_ADDR_W-1:0] len_wr_addr, len_rd_addr;
    assign len_wr_addr = len_wr_ptr_q[LEN_ADDR_W-1:0];
    assign len_rd_addr = len_rd_ptr_q[LEN_ADDR_W-1:0];

    // =========================================================================
    // Packet Receiver State
    // =========================================================================

    logic in_packet_q, in_packet_d;
    logic [31:0] pkt_length_q, pkt_length_d;

    // =========================================================================
    // Read Controller State
    // =========================================================================

    // Track words remaining in current packet being read by CPU
    logic [31:0] words_remaining_q, words_remaining_d;
    logic packet_active_q, packet_active_d;

    // =========================================================================
    // USB Stream Interface
    // =========================================================================

    // Accept data when enabled and Data FIFO has space
    // Also need Len FIFO space if this is last beat
    logic can_accept;
    assign can_accept = enable_i && !data_full && (!rx_last_i || !len_full);
    assign rx_ready_o = can_accept;

    // Write to Data FIFO
    logic data_wr_en;
    assign data_wr_en = rx_valid_i && rx_ready_o;

    // Write to Len FIFO (on last beat of packet)
    logic len_wr_en;
    assign len_wr_en = rx_valid_i && rx_ready_o && rx_last_i;

    // =========================================================================
    // CSR Interface
    // =========================================================================

    // RX_LEN: peek at Len FIFO head (0 if empty)
    assign cpu_rx_len_o = len_empty ? 32'd0 : len_mem[len_rd_addr];

    // RX_DATA: peek at Data FIFO head
    assign cpu_rd_data_o = data_mem[data_rd_addr];

    // Status outputs
    assign rx_valid_o   = !len_empty;
    assign rx_full_o    = data_full;
    assign rx_packets_o = len_level_ext;

    // Overflow detection: pulse when valid data is presented but cannot be accepted
    assign data_overflow_o = rx_valid_i && !rx_ready_o && data_full;
    assign len_overflow_o  = rx_valid_i && rx_last_i && !rx_ready_o && len_full;

    // =========================================================================
    // Combinational Logic
    // =========================================================================

    always_comb begin
        // Default: hold state
        data_wr_ptr_d    = data_wr_ptr_q;
        data_rd_ptr_d    = data_rd_ptr_q;
        len_wr_ptr_d     = len_wr_ptr_q;
        len_rd_ptr_d     = len_rd_ptr_q;
        in_packet_d      = in_packet_q;
        pkt_length_d     = pkt_length_q;
        words_remaining_d = words_remaining_q;
        packet_active_d  = packet_active_q;

        // =====================================================================
        // Software flush - reset everything
        // =====================================================================
        if (sw_flush_i) begin
            data_wr_ptr_d    = '0;
            data_rd_ptr_d    = '0;
            len_wr_ptr_d     = '0;
            len_rd_ptr_d     = '0;
            in_packet_d      = 1'b0;
            pkt_length_d     = '0;
            words_remaining_d = '0;
            packet_active_d  = 1'b0;
        end else begin
            // =================================================================
            // USB RX: Write to FIFOs
            // =================================================================
            if (data_wr_en) begin
                data_wr_ptr_d = data_wr_ptr_q + 1;

                // Capture length on first beat
                if (!in_packet_q) begin
                    pkt_length_d = rx_length_i;
                    in_packet_d  = 1'b1;
                end

                // On last beat, push length to Len FIFO
                if (rx_last_i) begin
                    len_wr_ptr_d = len_wr_ptr_q + 1;
                    in_packet_d  = 1'b0;
                end
            end

            // =================================================================
            // CPU RX: Read from FIFOs
            // =================================================================
            if (cpu_rd_req_i && !data_empty) begin
                // Pop data FIFO
                data_rd_ptr_d = data_rd_ptr_q + 1;

                // Track packet consumption
                if (!packet_active_q && !len_empty) begin
                    // Starting a new packet - calculate words from length
                    // words = ceil(len / 4) = (len + 3) / 4
                    words_remaining_d = ((cpu_rx_len_o + 32'd3) >> 2);
                    packet_active_d   = 1'b1;
                end

                if (packet_active_q || !len_empty) begin
                    if (words_remaining_q <= 1) begin
                        // Last word of packet - pop Len FIFO
                        len_rd_ptr_d     = len_rd_ptr_q + 1;
                        packet_active_d  = 1'b0;
                        words_remaining_d = '0;
                    end else begin
                        words_remaining_d = words_remaining_q - 1;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Sequential Logic
    // =========================================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            data_wr_ptr_q    <= '0;
            data_rd_ptr_q    <= '0;
            len_wr_ptr_q     <= '0;
            len_rd_ptr_q     <= '0;
            in_packet_q      <= 1'b0;
            pkt_length_q     <= '0;
            words_remaining_q <= '0;
            packet_active_q  <= 1'b0;
        end else begin
            data_wr_ptr_q    <= data_wr_ptr_d;
            data_rd_ptr_q    <= data_rd_ptr_d;
            len_wr_ptr_q     <= len_wr_ptr_d;
            len_rd_ptr_q     <= len_rd_ptr_d;
            in_packet_q      <= in_packet_d;
            pkt_length_q     <= pkt_length_d;
            words_remaining_q <= words_remaining_d;
            packet_active_q  <= packet_active_d;
        end
    end

    // Data FIFO memory write
    always_ff @(posedge clk_i) begin
        if (data_wr_en) begin
            data_mem[data_wr_addr] <= rx_data_i;
        end
    end

    // Len FIFO memory write
    always_ff @(posedge clk_i) begin
        if (len_wr_en) begin
            // Use captured length, or rx_length_i if single-beat packet
            len_mem[len_wr_addr] <= in_packet_q ? pkt_length_q : rx_length_i;
        end
    end

endmodule
