// SPDX-License-Identifier: BSD-2-Clause
// USB UART Testbench
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Basic verification of USB UART functionality:
// - TX: Write words, trigger newline flush, verify USB stream output
// - RX: Inject USB packets, read via CSR, verify rx_len tracking

module usb_uart_tb;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter int CLK_PERIOD = 10;  // 100MHz

    // =========================================================================
    // Signals
    // =========================================================================

    logic        clk;
    logic        rst_n;

    // Wishbone
    logic        wb_cyc;
    logic        wb_stb;
    logic        wb_we;
    logic [31:0] wb_adr;
    logic [3:0]  wb_sel;
    logic [31:0] wb_dat_w;
    logic [31:0] wb_dat_r;
    logic        wb_ack;
    logic        wb_err;
    logic        wb_stall;

    // USB TX
    logic        tx_valid;
    logic        tx_ready;
    logic [31:0] tx_data;
    logic [7:0]  tx_dst;
    logic [31:0] tx_length;
    logic        tx_last;

    // USB RX
    logic        rx_valid;
    logic        rx_ready;
    logic [31:0] rx_data;
    logic [7:0]  rx_dst;
    logic [31:0] rx_length;
    logic        rx_last;

    // IRQ
    logic        irq;

    // =========================================================================
    // DUT
    // =========================================================================

    usb_uart #(
        .TX_DEPTH   (16),
        .RX_DEPTH   (16),
        .LEN_DEPTH  (4),
        .CHANNEL_ID (2)
    ) dut (
        .clk_i       (clk),
        .rst_ni      (rst_n),
        .wb_cyc_i    (wb_cyc),
        .wb_stb_i    (wb_stb),
        .wb_we_i     (wb_we),
        .wb_adr_i    (wb_adr),
        .wb_sel_i    (wb_sel),
        .wb_dat_i    (wb_dat_w),
        .wb_dat_o    (wb_dat_r),
        .wb_ack_o    (wb_ack),
        .wb_err_o    (wb_err),
        .wb_stall_o  (wb_stall),
        .tx_valid_o  (tx_valid),
        .tx_ready_i  (tx_ready),
        .tx_data_o   (tx_data),
        .tx_dst_o    (tx_dst),
        .tx_length_o (tx_length),
        .tx_last_o   (tx_last),
        .rx_valid_i  (rx_valid),
        .rx_ready_o  (rx_ready),
        .rx_data_i   (rx_data),
        .rx_dst_i    (rx_dst),
        .rx_length_i (rx_length),
        .rx_last_i   (rx_last),
        .irq_o       (irq)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Wishbone Tasks
    // =========================================================================

    task automatic wb_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        wb_cyc   <= 1;
        wb_stb   <= 1;
        wb_we    <= 1;
        wb_adr   <= addr;
        wb_dat_w <= data;
        wb_sel   <= 4'hF;
        @(posedge clk);
        while (!wb_ack) @(posedge clk);
        wb_cyc <= 0;
        wb_stb <= 0;
        wb_we  <= 0;
    endtask

    task automatic wb_read(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        wb_cyc <= 1;
        wb_stb <= 1;
        wb_we  <= 0;
        wb_adr <= addr;
        wb_sel <= 4'hF;
        @(posedge clk);
        while (!wb_ack) @(posedge clk);
        data = wb_dat_r;
        wb_cyc <= 0;
        wb_stb <= 0;
    endtask

    // =========================================================================
    // USB RX Injection Task
    // =========================================================================

    task automatic usb_rx_packet(input [31:0] length, input [31:0] words[$]);
        rx_length <= length;
        rx_dst    <= 8'd2;
        for (int i = 0; i < words.size(); i++) begin
            rx_valid <= 1;
            rx_data  <= words[i];
            rx_last  <= (i == words.size() - 1);
            @(posedge clk);
            while (!rx_ready) @(posedge clk);
        end
        rx_valid <= 0;
        rx_last  <= 0;
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================

    logic [31:0] read_data;
    logic [31:0] rx_words[$];

    initial begin
        $display("=== USB UART Testbench ===");

        // Initialize
        rst_n    = 0;
        wb_cyc   = 0;
        wb_stb   = 0;
        wb_we    = 0;
        wb_adr   = 0;
        wb_dat_w = 0;
        wb_sel   = 0;
        tx_ready = 1;
        rx_valid = 0;
        rx_data  = 0;
        rx_dst   = 0;
        rx_length = 0;
        rx_last  = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 1: TX with newline flush
        // ---------------------------------------------------------------------
        $display("\n[Test 1] TX with newline flush");

        // Write "Hi\n" = 0x000A6948 (little-endian: 'H', 'i', '\n', 0)
        wb_write(32'h00, 32'h000A6948);

        // Wait for TX output
        repeat (5) @(posedge clk);

        // Check TX stream
        if (tx_valid) begin
            $display("  TX valid: dst=%0d, length=%0d, data=0x%08x, last=%0d",
                     tx_dst, tx_length, tx_data, tx_last);
            if (tx_dst == 2 && tx_length == 3 && tx_last == 1)
                $display("  PASS: Correct TX packet");
            else
                $display("  FAIL: Unexpected TX values");
        end else begin
            $display("  FAIL: TX not valid");
        end

        // Consume TX
        repeat (3) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 2: RX packet reception
        // ---------------------------------------------------------------------
        $display("\n[Test 2] RX packet reception");

        // Inject "OK\n" = 2 words, 3 bytes
        rx_words = '{32'h000A4B4F};  // 'O', 'K', '\n', 0
        usb_rx_packet(32'd3, rx_words);

        repeat (5) @(posedge clk);

        // Check rx_len
        wb_read(32'h08, read_data);
        $display("  RX_LEN = %0d", read_data);
        if (read_data == 3)
            $display("  PASS: Correct RX length");
        else
            $display("  FAIL: Expected 3, got %0d", read_data);

        // Read rx_data
        wb_read(32'h04, read_data);
        $display("  RX_DATA = 0x%08x", read_data);
        if (read_data == 32'h000A4B4F)
            $display("  PASS: Correct RX data");
        else
            $display("  FAIL: Expected 0x000A4B4F");

        // Check rx_len is now 0 (packet consumed)
        wb_read(32'h08, read_data);
        $display("  RX_LEN after read = %0d", read_data);
        if (read_data == 0)
            $display("  PASS: RX_LEN cleared");
        else
            $display("  FAIL: RX_LEN should be 0");

        // ---------------------------------------------------------------------
        // Done
        // ---------------------------------------------------------------------
        $display("\n=== Tests Complete ===");
        repeat (10) @(posedge clk);
        $finish;
    end

    // =========================================================================
    // Timeout
    // =========================================================================

    initial begin
        #100000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
