// SPDX-License-Identifier: BSD-2-Clause
// USB Bridge RX FIFO
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// RX FIFO for USB->CPU data path. Data arrives from USB core and is
// stored until CPU reads it via CSR interface.

module usb_bridge_rx_fifo #(
    parameter int unsigned DEPTH = 64,
    parameter int unsigned DW    = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Write interface (from USB)
    input  logic             wr_valid_i,
    output logic             wr_ready_o,
    input  logic [DW-1:0]    wr_data_i,

    // Read interface (to CSR)
    input  logic             rd_req_i,      // Read request from CSR
    output logic [DW-1:0]    rd_data_o,
    output logic             rd_valid_o,    // Data is valid

    // Control inputs
    input  logic             enable_i,
    input  logic             sw_flush_i,    // Software flush (clear FIFO)

    // Status outputs
    output logic             valid_o,       // FIFO has data
    output logic             full_o,
    output logic             empty_o,
    output logic [15:0]      level_o,
    output logic             overflow_o     // Pulse on overflow attempt
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
    assign valid_o = !empty_o;

    // Write ready: accept writes when enabled and not full
    assign wr_ready_o = enable_i && !full_o;

    // Read data output
    assign rd_data_o  = mem[rd_addr];
    assign rd_valid_o = !empty_o;

    // Overflow detection
    assign overflow_o = wr_valid_i && wr_ready_o && full_o;

    // Combinational logic
    always_comb begin
        wr_ptr_d = wr_ptr_q;
        rd_ptr_d = rd_ptr_q;

        // Software flush - reset both pointers
        if (sw_flush_i) begin
            wr_ptr_d = '0;
            rd_ptr_d = '0;
        end else begin
            // Handle writes
            if (wr_valid_i && wr_ready_o) begin
                wr_ptr_d = wr_ptr_q + 1;
            end

            // Handle reads (auto-pop on read request)
            if (rd_req_i && !empty_o) begin
                rd_ptr_d = rd_ptr_q + 1;
            end
        end
    end

    // Sequential logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr_q <= '0;
            rd_ptr_q <= '0;
        end else begin
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
        end
    end

    // Memory write
    always_ff @(posedge clk_i) begin
        if (wr_valid_i && wr_ready_o) begin
            mem[wr_addr] <= wr_data_i;
        end
    end

endmodule
