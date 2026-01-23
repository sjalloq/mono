// SPDX-License-Identifier: BSD-2-Clause
// USB Bridge TX FIFO with Flush Logic
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// TX FIFO for CPU->USB data path with multiple flush mechanisms:
// - Software flush (immediate)
// - Timeout-based flush (after N cycles of inactivity)
// - Threshold-based flush (when level reaches N entries)
// - Character-match flush (when specific byte is written)

module usb_bridge_tx_fifo #(
    parameter int unsigned DEPTH = 64,
    parameter int unsigned DW    = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Write interface (from CSR)
    input  logic             wr_valid_i,
    output logic             wr_ready_o,
    input  logic [DW-1:0]    wr_data_i,

    // Read interface (to USB packetizer)
    output logic             rd_valid_o,
    input  logic             rd_ready_i,
    output logic [DW-1:0]    rd_data_o,
    output logic             rd_last_o,

    // Control inputs
    input  logic             enable_i,
    input  logic             sw_flush_i,         // Software flush trigger
    input  logic             timeout_flush_en_i, // Enable timeout flush
    input  logic             thresh_flush_en_i,  // Enable threshold flush
    input  logic             char_flush_en_i,    // Enable character match flush
    input  logic [31:0]      flush_timeout_i,    // Timeout value in cycles
    input  logic [15:0]      flush_thresh_i,     // Threshold level
    input  logic [7:0]       flush_char_i,       // Character to match

    // Status outputs
    output logic             ready_o,            // Can accept writes
    output logic             full_o,
    output logic             empty_o,
    output logic [15:0]      level_o,
    output logic             overflow_o,         // Pulse on overflow attempt

    // Flush output (active during flush operation)
    output logic             flushing_o
);

    // FIFO depth must be power of 2
    localparam int unsigned ADDR_W = $clog2(DEPTH);

    // FIFO storage
    logic [DW-1:0] mem [DEPTH];

    // Pointers
    logic [ADDR_W:0] wr_ptr_q, wr_ptr_d;
    logic [ADDR_W:0] rd_ptr_q, rd_ptr_d;

    // Derived signals
    logic [ADDR_W-1:0] wr_addr, rd_addr;
    assign wr_addr = wr_ptr_q[ADDR_W-1:0];
    assign rd_addr = rd_ptr_q[ADDR_W-1:0];

    // Level calculation
    logic [ADDR_W:0] level_int;
    assign level_int = wr_ptr_q - rd_ptr_q;
    assign level_o   = {{(16-ADDR_W-1){1'b0}}, level_int};

    // Full/empty detection
    assign full_o  = (level_int == (ADDR_W+1)'(DEPTH));
    assign empty_o = (level_int == '0);
    assign ready_o = enable_i && !full_o;

    // Flush state machine
    typedef enum logic [1:0] {
        IDLE,
        FLUSHING,
        WAIT_LAST
    } flush_state_e;

    flush_state_e flush_state_q, flush_state_d;

    // Timeout counter
    logic [31:0] timeout_cnt_q, timeout_cnt_d;

    // Flush trigger detection
    logic timeout_trigger;
    logic thresh_trigger;
    logic any_flush_trigger;

    // Timeout: fire when counter reaches threshold and FIFO not empty
    assign timeout_trigger = timeout_flush_en_i && !empty_o &&
                            (timeout_cnt_q >= flush_timeout_i) &&
                            (flush_timeout_i != 0);

    // Threshold: fire when level reaches or exceeds threshold
    assign thresh_trigger = thresh_flush_en_i && (level_int >= {1'b0, flush_thresh_i[ADDR_W-1:0]});

    // Character match: check lowest byte of written data
    logic char_match;
    assign char_match = char_flush_en_i && wr_valid_i && wr_ready_o &&
                       (wr_data_i[7:0] == flush_char_i);

    // Combined flush trigger
    assign any_flush_trigger = sw_flush_i || timeout_trigger || thresh_trigger || char_match;

    // Flushing indicator
    assign flushing_o = (flush_state_q == FLUSHING) || (flush_state_q == WAIT_LAST);

    // Write ready: accept writes when enabled, not full, and not flushing
    assign wr_ready_o = enable_i && !full_o && (flush_state_q == IDLE);

    // Read valid: data available during flush
    assign rd_valid_o = flushing_o && !empty_o;

    // Read data
    assign rd_data_o = mem[rd_addr];

    // Last indicator: asserted on final word of flush
    assign rd_last_o = flushing_o && (level_int == 1);

    // Overflow detection
    assign overflow_o = wr_valid_i && full_o && enable_i;

    // Combinational logic
    always_comb begin
        wr_ptr_d      = wr_ptr_q;
        rd_ptr_d      = rd_ptr_q;
        flush_state_d = flush_state_q;
        timeout_cnt_d = timeout_cnt_q;

        case (flush_state_q)
            IDLE: begin
                // Handle writes
                if (wr_valid_i && wr_ready_o) begin
                    wr_ptr_d = wr_ptr_q + 1;
                    // Reset timeout on write activity
                    timeout_cnt_d = '0;
                end else if (!empty_o && timeout_flush_en_i) begin
                    // Increment timeout counter when no write activity
                    timeout_cnt_d = timeout_cnt_q + 1;
                end

                // Check for flush triggers
                if (any_flush_trigger && !empty_o) begin
                    flush_state_d = FLUSHING;
                end
            end

            FLUSHING: begin
                // Drain FIFO
                if (rd_ready_i && rd_valid_o) begin
                    rd_ptr_d = rd_ptr_q + 1;
                    if (level_int == 1) begin
                        // Last word being read
                        flush_state_d = IDLE;
                        timeout_cnt_d = '0;
                    end
                end
            end

            WAIT_LAST: begin
                // Wait for downstream to accept last word
                if (rd_ready_i) begin
                    flush_state_d = IDLE;
                    timeout_cnt_d = '0;
                end
            end

            default: flush_state_d = IDLE;
        endcase

        // Software flush can reset pointers immediately if downstream ready
        if (sw_flush_i && (flush_state_q == IDLE)) begin
            if (empty_o) begin
                // Nothing to flush
                timeout_cnt_d = '0;
            end
        end
    end

    // Sequential logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr_q      <= '0;
            rd_ptr_q      <= '0;
            flush_state_q <= IDLE;
            timeout_cnt_q <= '0;
        end else begin
            wr_ptr_q      <= wr_ptr_d;
            rd_ptr_q      <= rd_ptr_d;
            flush_state_q <= flush_state_d;
            timeout_cnt_q <= timeout_cnt_d;
        end
    end

    // Memory write
    always_ff @(posedge clk_i) begin
        if (wr_valid_i && wr_ready_o) begin
            mem[wr_addr] <= wr_data_i;
        end
    end

endmodule
