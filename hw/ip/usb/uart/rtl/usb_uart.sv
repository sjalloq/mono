// SPDX-License-Identifier: BSD-2-Clause
// USB UART - Bidirectional Character Stream over USB
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Provides printf output and REPL input over USB channel.
// Replaces traditional UART for CPU debug I/O.
//
// Features:
// - TX: Auto-flush on configurable character, timeout, or threshold
// - RX: Packet-aware dual-FIFO preserves message boundaries
// - IRQ support for TX empty and RX packet available

module usb_uart
    import wb_pkg::*;
    import usb_uart_csr_reg_pkg::*;
#(
    parameter int unsigned TX_DEPTH   = 64,
    parameter int unsigned RX_DEPTH   = 64,
    parameter int unsigned LEN_DEPTH  = 4,
    parameter int unsigned CHANNEL_ID = 2
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // Wishbone Slave Interface
    // =========================================================================
    input  wb_m2s_t          wb_m2s_i,
    output wb_s2m_t          wb_s2m_o,

    // =========================================================================
    // USB TX Stream (usb_channel_description sink - to host)
    // =========================================================================
    output logic             tx_valid_o,
    input  logic             tx_ready_i,
    output logic [31:0]      tx_data_o,
    output logic [7:0]       tx_dst_o,
    output logic [31:0]      tx_length_o,
    output logic             tx_last_o,

    // =========================================================================
    // USB RX Stream (usb_channel_description source - from host)
    // =========================================================================
    input  logic             rx_valid_i,
    output logic             rx_ready_o,
    input  logic [31:0]      rx_data_i,
    input  logic [7:0]       rx_dst_i,
    input  logic [31:0]      rx_length_i,
    input  logic             rx_last_i,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output logic             irq_o
);

    // =========================================================================
    // Signal Declarations
    // =========================================================================

    // Simple bus interface (between wb2simple and CSR block)
    logic             reg_we;
    logic             reg_re;
    logic [31:0]      reg_addr;
    logic [31:0]      reg_wdata;
    logic [31:0]      reg_rdata;

    // Hardware interface structs
    usb_uart_csr_reg2hw_t reg2hw;
    usb_uart_csr_hw2reg_t hw2reg;

    // TX FIFO signals
    logic             tx_wr_valid;
    logic [31:0]      tx_wr_data;
    logic             tx_empty;
    logic             tx_full;
    logic [3:0]       tx_level;

    // RX FIFO signals
    logic             rx_rd_req;
    logic [31:0]      rx_rd_data;
    logic [31:0]      rx_len;
    logic             rx_valid;
    logic             rx_full;
    logic [3:0]       rx_packets;
    logic             rx_data_overflow;
    logic             rx_len_overflow;

    // Control signals from CSR
    logic             tx_en;
    logic             rx_en;
    logic             char_flush_en;
    logic             timeout_flush_en;
    logic             thresh_flush_en;
    logic             sw_tx_flush;
    logic             sw_tx_flush_ack;
    logic             sw_rx_flush;
    logic             sw_tx_clear;
    logic [31:0]      flush_timeout;
    logic [7:0]       flush_thresh;
    logic [7:0]       flush_char;

    // =========================================================================
    // Wishbone to Simple Bus Adapter
    // =========================================================================

    wb2simple u_wb2simple (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .wb_m2s_i   (wb_m2s_i),
        .wb_s2m_o   (wb_s2m_o),
        .reg_we     (reg_we),
        .reg_re     (reg_re),
        .reg_addr   (reg_addr),
        .reg_wdata  (reg_wdata),
        .reg_rdata  (reg_rdata)
    );

    // =========================================================================
    // CSR Block
    // =========================================================================

    usb_uart_csr_reg_top #(
        .ResetType (rdl_subreg_pkg::ActiveLowAsync)
    ) u_csr (
        .clk       (clk_i),
        .rst       (rst_ni),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_addr  (reg_addr[BlockAw-1:0]),
        .reg_wdata (reg_wdata),
        .reg_rdata (reg_rdata),
        .reg2hw    (reg2hw),
        .hw2reg    (hw2reg)
    );

    // =========================================================================
    // CSR Signal Mapping
    // =========================================================================

    // Control signals from registers
    assign tx_en            = reg2hw.ctrl.tx_en.q;
    assign rx_en            = reg2hw.ctrl.rx_en.q;
    assign char_flush_en    = reg2hw.ctrl.char_flush_en.q;
    assign timeout_flush_en = reg2hw.ctrl.timeout_flush_en.q;
    assign thresh_flush_en  = reg2hw.ctrl.thresh_flush_en.q;
    assign sw_tx_flush      = reg2hw.ctrl.tx_flush.q;
    assign sw_rx_flush      = reg2hw.ctrl.rx_flush.q;
    assign sw_tx_clear      = reg2hw.ctrl.tx_clear.q;
    assign flush_timeout    = reg2hw.timeout.q;
    assign flush_thresh     = reg2hw.thresh.q;
    assign flush_char       = reg2hw.flush_char.q;

    // TX_DATA: CPU writes trigger FIFO write
    assign tx_wr_valid = reg_we && (reg_addr[BlockAw-1:0] == USB_UART_CSR_TX_DATA_OFFSET);
    assign tx_wr_data  = reg_wdata;

    // RX_DATA: CPU reads trigger FIFO pop
    assign rx_rd_req = reg_re && (reg_addr[BlockAw-1:0] == USB_UART_CSR_RX_DATA_OFFSET);

    // Status outputs to CSR
    assign hw2reg.status.tx_empty.d   = tx_empty;
    assign hw2reg.status.tx_full.d    = tx_full;
    assign hw2reg.status.rx_valid.d   = rx_valid;
    assign hw2reg.status.rx_full.d    = rx_full;
    assign hw2reg.status.tx_level.d   = tx_level;
    assign hw2reg.status.rx_packets.d = rx_packets;

    // RX data and length outputs (external registers)
    assign hw2reg.rx_data.d = rx_rd_data;
    assign hw2reg.rx_len.d  = rx_len;

    // Clean flush flag as soon as flush is acknowledged.
    assign hw2reg.ctrl.tx_flush.d = 1'b0;
    assign hw2reg.ctrl.tx_flush.de = sw_tx_flush_ack;

    // Single cycle pulse
    assign hw2reg.ctrl.rx_flush.d = 1'b0;
    assign hw2reg.ctrl.rx_flush.de = sw_rx_flush;
    
    // Single cycle pulse
    assign hw2reg.ctrl.tx_clear.d = 1'b0;
    assign hw2reg.ctrl.tx_clear.de = sw_tx_clear;


    // =========================================================================
    // TX FIFO
    // =========================================================================

    usb_uart_tx_fifo #(
        .DEPTH      (TX_DEPTH),
        .CHANNEL_ID (CHANNEL_ID)
    ) u_tx_fifo (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .wr_valid_i         (tx_wr_valid),
        .wr_data_i          (tx_wr_data),
        .tx_valid_o         (tx_valid_o),
        .tx_ready_i         (tx_ready_i),
        .tx_data_o          (tx_data_o),
        .tx_dst_o           (tx_dst_o),
        .tx_length_o        (tx_length_o),
        .tx_last_o          (tx_last_o),
        .enable_i           (tx_en),
        .sw_flush_i         (sw_tx_flush),
        .sw_clear_i         (sw_tx_clear),
        .char_flush_en_i    (char_flush_en),
        .flush_char_i       (flush_char),
        .timeout_flush_en_i (timeout_flush_en),
        .thresh_flush_en_i  (thresh_flush_en),
        .flush_timeout_i    (flush_timeout),
        .flush_thresh_i     (flush_thresh),
        .sw_flush_ack_o     (sw_tx_flush_ack),
        .empty_o            (tx_empty),
        .full_o             (tx_full),
        .level_o            (tx_level)
    );

    // =========================================================================
    // RX FIFO
    // =========================================================================

    usb_uart_rx_fifo #(
        .DATA_DEPTH (RX_DEPTH),
        .LEN_DEPTH  (LEN_DEPTH)
    ) u_rx_fifo (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .rx_valid_i       (rx_valid_i),
        .rx_ready_o       (rx_ready_o),
        .rx_data_i        (rx_data_i),
        .rx_length_i      (rx_length_i),
        .rx_last_i        (rx_last_i),
        .cpu_rd_req_i     (rx_rd_req),
        .cpu_rd_data_o    (rx_rd_data),
        .cpu_rx_len_o     (rx_len),
        .enable_i         (rx_en),
        .sw_flush_i       (sw_rx_flush),
        .rx_valid_o       (rx_valid),
        .rx_full_o        (rx_full),
        .rx_packets_o     (rx_packets),
        .data_overflow_o  (rx_data_overflow),
        .len_overflow_o   (rx_len_overflow)
    );

    // =========================================================================
    // IRQ Generation
    // =========================================================================

    // Edge detection for level signals (rx_valid, tx_empty)
    logic rx_valid_prev, tx_empty_prev;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_valid_prev <= 1'b0;
            tx_empty_prev <= 1'b1;  // TX starts empty
        end else begin
            rx_valid_prev <= rx_valid;
            tx_empty_prev <= tx_empty;
        end
    end

    logic rx_valid_rising, tx_empty_rising;
    assign rx_valid_rising = rx_valid && !rx_valid_prev;
    assign tx_empty_rising = tx_empty && !tx_empty_prev;

    // IRQ status sticky bits (set by HW pulse, cleared by SW writing 1)
    assign hw2reg.irq_status.rx_valid.d      = 1'b1;
    assign hw2reg.irq_status.rx_valid.de     = rx_valid_rising;
    assign hw2reg.irq_status.tx_empty.d      = 1'b1;
    assign hw2reg.irq_status.tx_empty.de     = tx_empty_rising;
    assign hw2reg.irq_status.rx_overflow.d   = 1'b1;
    assign hw2reg.irq_status.rx_overflow.de  = rx_data_overflow;
    assign hw2reg.irq_status.len_overflow.d  = 1'b1;
    assign hw2reg.irq_status.len_overflow.de = rx_len_overflow;

    // IRQ output: OR of (status & enable)
    logic [3:0] irq_status_q, irq_enable_q;
    assign irq_status_q = {reg2hw.irq_status.len_overflow.q,
                            reg2hw.irq_status.rx_overflow.q,
                            reg2hw.irq_status.tx_empty.q,
                            reg2hw.irq_status.rx_valid.q};
    assign irq_enable_q = {reg2hw.irq_enable.len_overflow.q,
                            reg2hw.irq_enable.rx_overflow.q,
                            reg2hw.irq_enable.tx_empty.q,
                            reg2hw.irq_enable.rx_valid.q};
    assign irq_o = |(irq_status_q & irq_enable_q);

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{rx_dst_i, reg_addr[31:BlockAw], reg2hw.tx_data};

endmodule
