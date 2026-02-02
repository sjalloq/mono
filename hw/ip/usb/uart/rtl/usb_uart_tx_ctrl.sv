// SPDX-License-Identifier: BSD-2-Clause
// USB UART TX Control Logic
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Pure control logic for TX data path — no FIFO storage.
// FIFO storage is provided by an external prim_fifo_sync instance.
//
// Flush mechanisms:
// - Character flush (scans all 4 bytes for configurable character)
// - Timeout-based flush (after N cycles of inactivity)
// - Threshold-based flush (when level reaches N entries)
// - Software flush trigger (sw_flush_i = send buffered data)
// - Invalidate (invalidate_i = discard all data via FIFO clear)
//
// Outputs usb_channel_description stream with precise byte count.

module usb_uart_tx_ctrl #(
    parameter int unsigned DEPTH      = 64,
    parameter int unsigned CHANNEL_ID = 2
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // CPU Write Interface (from CSR)
    // =========================================================================
    input  logic             wr_valid_i,
    input  logic [31:0]      wr_data_i,

    // =========================================================================
    // FIFO Write Interface (drives external prim_fifo_sync)
    // =========================================================================
    output logic             fifo_wvalid_o,
    output logic [31:0]      fifo_wdata_o,
    input  logic             fifo_wready_i,

    // =========================================================================
    // FIFO Read Interface (from external prim_fifo_sync)
    // =========================================================================
    input  logic [31:0]      fifo_rdata_i,
    input  logic             fifo_rvalid_i,
    output logic             fifo_rready_o,

    // =========================================================================
    // FIFO Status (from external prim_fifo_sync)
    // =========================================================================
    input  logic [DepthW-1:0] fifo_depth_i,

    // =========================================================================
    // FIFO Control
    // =========================================================================
    output logic             fifo_clr_o,

    // =========================================================================
    // USB Stream Output (usb_channel_description)
    // =========================================================================
    output logic             tx_valid_o,
    input  logic             tx_ready_i,
    output logic [31:0]      tx_data_o,
    output logic [7:0]       tx_dst_o,
    output logic [31:0]      tx_length_o,
    output logic             tx_last_o,

    // =========================================================================
    // Control Inputs
    // =========================================================================
    input  logic             enable_i,
    input  logic             sw_flush_i,         // Send data trigger
    input  logic             invalidate_i,       // Discard all data
    input  logic             char_flush_en_i,
    input  logic [7:0]       flush_char_i,
    input  logic             timeout_flush_en_i,
    input  logic             thresh_flush_en_i,
    input  logic [31:0]      flush_timeout_i,
    input  logic [7:0]       flush_thresh_i,

    // =========================================================================
    // Acks
    // =========================================================================
    output logic             sw_flush_ack_o,

    // =========================================================================
    // Status Outputs
    // =========================================================================
    output logic             empty_o,
    output logic             full_o,
    output logic [3:0]       level_o
);

    // =========================================================================
    // Parameters and Types
    // =========================================================================

    localparam int unsigned DepthW = prim_util_pkg::vbits(DEPTH + 1);

    typedef enum logic [1:0] {
        IDLE,
        SEND_DATA
    } state_e;

    // =========================================================================
    // Signal Declarations
    // =========================================================================

    state_e state_q, state_d;

    // Timeout counter
    logic [31:0] timeout_cnt_q, timeout_cnt_d;

    // Flush tracking
    logic [31:0] flush_byte_count_q, flush_byte_count_d;
    logic [DepthW-1:0] flush_word_count_q, flush_word_count_d;
    logic [DepthW-1:0] words_sent_q, words_sent_d;

    // FIFO level as wider type for arithmetic
    logic [DepthW-1:0] level_int;
    assign level_int = fifo_depth_i;

    // Status outputs derived from FIFO signals
    assign empty_o = !fifo_rvalid_i;
    assign full_o  = !fifo_wready_i;
    assign level_o = level_int[3:0];

    // =========================================================================
    // Character Detection (parallel scan of all 4 bytes)
    // =========================================================================

    logic [3:0] char_match;
    logic       char_found;
    logic [1:0] char_pos;

    assign char_match[0] = (wr_data_i[7:0]   == flush_char_i);
    assign char_match[1] = (wr_data_i[15:8]  == flush_char_i);
    assign char_match[2] = (wr_data_i[23:16] == flush_char_i);
    assign char_match[3] = (wr_data_i[31:24] == flush_char_i);

    assign char_found = |char_match;

    // Priority encode: find lowest byte position with match
    always_comb begin
        if (char_match[0])      char_pos = 2'd0;
        else if (char_match[1]) char_pos = 2'd1;
        else if (char_match[2]) char_pos = 2'd2;
        else                    char_pos = 2'd3;
    end

    // =========================================================================
    // FIFO Write Gating
    // =========================================================================

    logic wr_en;
    assign wr_en = wr_valid_i && enable_i && (state_q == IDLE);

    assign fifo_wvalid_o = wr_en;
    assign fifo_wdata_o  = wr_data_i;

    // =========================================================================
    // Flush Trigger Detection
    // =========================================================================

    // Character trigger: on write with match detected (write must be accepted)
    logic char_trigger;
    assign char_trigger = char_flush_en_i && wr_en && fifo_wready_i && char_found;

    // Timeout: fire when counter reaches threshold and FIFO not empty
    logic timeout_trigger;
    assign timeout_trigger = timeout_flush_en_i && !empty_o &&
                            (timeout_cnt_q >= flush_timeout_i) &&
                            (flush_timeout_i != 0);

    // Threshold: fire when level reaches or exceeds threshold
    logic [DepthW-1:0] thresh_clamped;
    assign thresh_clamped = (flush_thresh_i > DEPTH[7:0]) ?
                            DepthW'(DEPTH) : DepthW'(flush_thresh_i);
    logic thresh_trigger;
    assign thresh_trigger = thresh_flush_en_i && (level_int >= thresh_clamped);

    // Combined (only in IDLE state)
    logic any_flush_trigger;
    assign any_flush_trigger = (state_q == IDLE) && !empty_o &&
                               (sw_flush_i || timeout_trigger || thresh_trigger || char_trigger);

    // Trigger ack
    assign sw_flush_ack_o = (state_q == IDLE) && !empty_o && sw_flush_i;

    // =========================================================================
    // FIFO Clear
    // =========================================================================

    assign fifo_clr_o = invalidate_i;

    // =========================================================================
    // USB Stream Output
    // =========================================================================

    assign tx_dst_o    = CHANNEL_ID[7:0];
    assign tx_data_o   = fifo_rdata_i;
    assign tx_length_o = flush_byte_count_q;

    // Valid when sending data
    assign tx_valid_o = (state_q == SEND_DATA) && (words_sent_q < flush_word_count_q);

    // Last word indicator
    assign tx_last_o = tx_valid_o && (words_sent_q == flush_word_count_q - DepthW'(1));

    // Pop FIFO on downstream consume
    assign fifo_rready_o = tx_valid_o && tx_ready_i;

    // =========================================================================
    // State Machine
    // =========================================================================

    always_comb begin
        state_d            = state_q;
        timeout_cnt_d      = timeout_cnt_q;
        flush_byte_count_d = flush_byte_count_q;
        flush_word_count_d = flush_word_count_q;
        words_sent_d       = words_sent_q;

        // Invalidate: reset control state (FIFO cleared via fifo_clr_o)
        if (invalidate_i) begin
            state_d            = IDLE;
            timeout_cnt_d      = '0;
            flush_byte_count_d = '0;
            flush_word_count_d = '0;
            words_sent_d       = '0;
        end else begin
            case (state_q)
                IDLE: begin
                    // Handle timeout counting
                    if (wr_en && fifo_wready_i) begin
                        timeout_cnt_d = '0;  // Reset timeout on write
                    end else if (!empty_o && timeout_flush_en_i) begin
                        timeout_cnt_d = timeout_cnt_q + 1;
                    end

                    // Check for flush trigger
                    if (any_flush_trigger) begin
                        // Calculate byte count
                        if (char_trigger) begin
                            // Character flush: include bytes up to and including match
                            // level_int = words currently in FIFO (before this write is committed)
                            // Plus bytes in current word up to match
                            flush_byte_count_d = (32'(level_int) * 4) + {30'd0, char_pos} + 1;
                            flush_word_count_d = level_int + DepthW'(1);
                        end else begin
                            // Other triggers: full words
                            flush_byte_count_d = 32'(level_int) << 2;
                            flush_word_count_d = level_int;
                        end
                        words_sent_d = '0;
                        state_d = SEND_DATA;
                    end
                end

                SEND_DATA: begin
                    if (tx_valid_o && tx_ready_i) begin
                        words_sent_d = words_sent_q + DepthW'(1);

                        if (tx_last_o) begin
                            state_d = IDLE;
                            timeout_cnt_d = '0;
                        end
                    end
                end

                default: state_d = IDLE;
            endcase
        end
    end

    // =========================================================================
    // Sequential Logic
    // =========================================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q            <= IDLE;
            timeout_cnt_q      <= '0;
            flush_byte_count_q <= '0;
            flush_word_count_q <= '0;
            words_sent_q       <= '0;
        end else begin
            state_q            <= state_d;
            timeout_cnt_q      <= timeout_cnt_d;
            flush_byte_count_q <= flush_byte_count_d;
            flush_word_count_q <= flush_word_count_d;
            words_sent_q       <= words_sent_d;
        end
    end

endmodule
