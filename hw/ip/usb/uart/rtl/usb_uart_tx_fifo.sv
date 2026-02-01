// SPDX-License-Identifier: BSD-2-Clause
// USB UART TX FIFO with Flush Logic
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// TX FIFO for CPU->USB data path with multiple flush mechanisms:
// - Character flush (scans all 4 bytes for configurable character)
// - Timeout-based flush (after N cycles of inactivity)
// - Threshold-based flush (when level reaches N entries)
// - Software flush trigger
// - Software clear (discard all data)
//
// Outputs usb_channel_description stream with precise byte count.

module usb_uart_tx_fifo #(
    parameter int unsigned DEPTH      = 64,
    parameter int unsigned CHANNEL_ID = 2
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Write interface (from CSR)
    input  logic             wr_valid_i,
    input  logic [31:0]      wr_data_i,

    // USB stream output (usb_channel_description)
    output logic             tx_valid_o,
    input  logic             tx_ready_i,
    output logic [31:0]      tx_data_o,
    output logic [7:0]       tx_dst_o,
    output logic [31:0]      tx_length_o,
    output logic             tx_last_o,

    // Control inputs
    input  logic             enable_i,
    input  logic             sw_flush_i,         // Software flush trigger (send data)
    input  logic             sw_clear_i,         // Software clear (discard data)
    input  logic             char_flush_en_i,    // Enable character match flush
    input  logic [7:0]       flush_char_i,       // Character to match for flush
    input  logic             timeout_flush_en_i, // Enable timeout flush
    input  logic             thresh_flush_en_i,  // Enable threshold flush
    input  logic [31:0]      flush_timeout_i,    // Timeout value in cycles
    input  logic [7:0]       flush_thresh_i,     // Threshold level (words)

    // Acks
    output logic sw_flush_ack_o,

    // Status outputs
    output logic             empty_o,
    output logic             full_o,
    output logic [3:0]       level_o             // Truncated for CSR
);

    // =========================================================================
    // Parameters and Types
    // =========================================================================

    localparam int unsigned ADDR_W = $clog2(DEPTH);

    typedef enum logic [1:0] {
        IDLE,
        SEND_HEADER,
        SEND_DATA
    } state_e;

    // =========================================================================
    // Signal Declarations
    // =========================================================================

    // FIFO storage
    logic [31:0] mem [DEPTH];

    // Pointers
    logic [ADDR_W:0] wr_ptr_q, wr_ptr_d;
    logic [ADDR_W:0] rd_ptr_q, rd_ptr_d;

    // Level calculation
    logic [ADDR_W:0] level_int;
    assign level_int = wr_ptr_q - rd_ptr_q;
    assign level_o   = level_int[3:0];  // Truncate for 4-bit CSR field

    // Full/empty
    assign full_o  = (level_int == DEPTH[ADDR_W:0]);
    assign empty_o = (level_int == '0);

    // Derived addresses
    logic [ADDR_W-1:0] wr_addr, rd_addr;
    assign wr_addr = wr_ptr_q[ADDR_W-1:0];
    assign rd_addr = rd_ptr_q[ADDR_W-1:0];

    // State machine
    state_e state_q, state_d;

    // Timeout counter
    logic [31:0] timeout_cnt_q, timeout_cnt_d;

    // Flush tracking
    logic [31:0] flush_byte_count_q, flush_byte_count_d;
    logic [ADDR_W:0] flush_word_count_q, flush_word_count_d;
    logic [ADDR_W:0] words_sent_q, words_sent_d;

    // Character detection in current write
    logic [3:0] char_match;
    logic       char_found;
    logic [1:0] char_pos;  // Byte position of first match (0-3)

    // Flush triggers
    logic timeout_trigger;
    logic thresh_trigger;
    logic char_trigger;
    logic any_flush_trigger;

    // =========================================================================
    // Character Detection (parallel scan of all 4 bytes)
    // =========================================================================

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
    // Flush Trigger Detection
    // =========================================================================

    // Character trigger: on write with match detected
    assign char_trigger = char_flush_en_i && wr_valid_i && !full_o && enable_i && char_found;

    // Timeout: fire when counter reaches threshold and FIFO not empty
    assign timeout_trigger = timeout_flush_en_i && !empty_o &&
                            (timeout_cnt_q >= flush_timeout_i) &&
                            (flush_timeout_i != 0);

    // Threshold: fire when level reaches or exceeds threshold
    // Use full 8-bit threshold, clamped to FIFO depth
    logic [ADDR_W:0] thresh_clamped;
    assign thresh_clamped = (flush_thresh_i > DEPTH[7:0]) ?
                            DEPTH[ADDR_W:0] : {1'b0, flush_thresh_i[ADDR_W-1:0]};
    assign thresh_trigger = thresh_flush_en_i && (level_int >= thresh_clamped);

    // Combined (only in IDLE state)
    assign any_flush_trigger = (state_q == IDLE) && !empty_o &&
                               (sw_flush_i || timeout_trigger || thresh_trigger || char_trigger);

    // Trigger ack
    assign sw_flush_ack_o = (state_q == IDLE) && !empty_o && sw_flush_i;


    // =========================================================================
    // Write Logic
    // =========================================================================

    logic wr_en;
    assign wr_en = wr_valid_i && !full_o && enable_i && (state_q == IDLE);

    // =========================================================================
    // USB Stream Output
    // =========================================================================

    assign tx_dst_o = CHANNEL_ID[7:0];
    assign tx_data_o = mem[rd_addr];
    assign tx_length_o = flush_byte_count_q;

    // Valid when sending data
    assign tx_valid_o = (state_q == SEND_DATA) && (words_sent_q < flush_word_count_q);

    // Last word indicator
    assign tx_last_o = tx_valid_o && (words_sent_q == flush_word_count_q - 1);

    // =========================================================================
    // State Machine
    // =========================================================================

    always_comb begin
        state_d            = state_q;
        wr_ptr_d           = wr_ptr_q;
        rd_ptr_d           = rd_ptr_q;
        timeout_cnt_d      = timeout_cnt_q;
        flush_byte_count_d = flush_byte_count_q;
        flush_word_count_d = flush_word_count_q;
        words_sent_d       = words_sent_q;

        // Software clear: discard all data, reset to IDLE
        if (sw_clear_i) begin
            state_d            = IDLE;
            wr_ptr_d           = '0;
            rd_ptr_d           = '0;
            timeout_cnt_d      = '0;
            flush_byte_count_d = '0;
            flush_word_count_d = '0;
            words_sent_d       = '0;
        end else begin
            case (state_q)
                IDLE: begin
                    // Handle writes
                    if (wr_en) begin
                        wr_ptr_d = wr_ptr_q + 1;
                        timeout_cnt_d = '0;  // Reset timeout on write
                    end else if (!empty_o && timeout_flush_en_i) begin
                        timeout_cnt_d = timeout_cnt_q + 1;
                    end

                    // Check for flush trigger
                    if (any_flush_trigger) begin
                        // Calculate byte count
                        if (char_trigger) begin
                            // Character flush: include bytes up to and including match
                            // Words before current = level_int (before this write is committed)
                            // Plus bytes in current word up to match
                            flush_byte_count_d = (level_int * 4) + {30'd0, char_pos} + 1;
                            flush_word_count_d = level_int + 1;  // Include word being written
                        end else begin
                            // Other triggers: full words
                            flush_byte_count_d = 32'(level_int) << 2;  // level * 4
                            flush_word_count_d = level_int;
                        end
                        words_sent_d = '0;
                        state_d = SEND_DATA;
                    end
                end

                SEND_DATA: begin
                    if (tx_valid_o && tx_ready_i) begin
                        rd_ptr_d = rd_ptr_q + 1;
                        words_sent_d = words_sent_q + 1;

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
            wr_ptr_q           <= '0;
            rd_ptr_q           <= '0;
            timeout_cnt_q      <= '0;
            flush_byte_count_q <= '0;
            flush_word_count_q <= '0;
            words_sent_q       <= '0;
        end else begin
            state_q            <= state_d;
            wr_ptr_q           <= wr_ptr_d;
            rd_ptr_q           <= rd_ptr_d;
            timeout_cnt_q      <= timeout_cnt_d;
            flush_byte_count_q <= flush_byte_count_d;
            flush_word_count_q <= flush_word_count_d;
            words_sent_q       <= words_sent_d;
        end
    end

    // Memory write
    always_ff @(posedge clk_i) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data_i;
        end
    end

endmodule
