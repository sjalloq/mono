// SPDX-License-Identifier: BSD-2-Clause
// USB UART - Bidirectional Character Stream over USB
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Provides printf output and REPL input over USB channel.
// Replaces traditional UART for CPU debug I/O.
//
// Architecture:
//   usb_uart_csr        — Wishbone + CSR registers + IRQ generation
//   prim_fifo_sync      — TX data FIFO
//   usb_uart_tx_ctrl    — TX flush/send control logic
//   prim_fifo_sync      — RX data FIFO
//   prim_fifo_sync      — RX length FIFO
//   usb_uart_rx_ctrl    — RX packet tracking control logic
//
// Features:
// - TX: Auto-flush on configurable character, timeout, or threshold
// - RX: Packet-aware dual-FIFO preserves message boundaries
// - IRQ support for TX empty and RX packet available

module usb_uart
    import wb_pkg::*;
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
    // Local Parameters
    // =========================================================================

    localparam int unsigned TxDepthW  = prim_util_pkg::vbits(TX_DEPTH + 1);
    localparam int unsigned RxDepthW  = prim_util_pkg::vbits(RX_DEPTH + 1);
    localparam int unsigned LenDepthW = prim_util_pkg::vbits(LEN_DEPTH + 1);

    // =========================================================================
    // CSR <-> Datapath Signals
    // =========================================================================

    // TX write (CPU -> TX FIFO)
    logic             tx_wr_valid;
    logic [31:0]      tx_wr_data;

    // RX read (CPU <- RX FIFO)
    logic             rx_rd_req;

    // Control signals
    logic             tx_en, rx_en;
    logic             char_flush_en, timeout_flush_en, thresh_flush_en;
    logic             sw_flush, sw_flush_ack;
    logic             tx_invalidate, rx_invalidate;
    logic [31:0]      flush_timeout;
    logic [7:0]       flush_thresh, flush_char;

    // TX status
    logic             tx_empty, tx_full;
    logic [3:0]       tx_level;

    // RX status
    logic             rx_valid, rx_full;
    logic [3:0]       rx_packets;
    logic [31:0]      rx_rd_data, rx_len;
    logic             rx_data_overflow, rx_len_overflow;

    // =========================================================================
    // TX FIFO Signals
    // =========================================================================

    logic             tx_fifo_wvalid, tx_fifo_wready;
    logic [31:0]      tx_fifo_wdata;
    logic             tx_fifo_rvalid, tx_fifo_rready;
    logic [31:0]      tx_fifo_rdata;
    logic [TxDepthW-1:0] tx_fifo_depth;
    logic             tx_fifo_clr;

    // =========================================================================
    // RX Data FIFO Signals
    // =========================================================================

    logic             rx_data_fifo_wvalid, rx_data_fifo_wready;
    logic             rx_data_fifo_rvalid, rx_data_fifo_rready;
    logic [31:0]      rx_data_fifo_rdata;
    logic             rx_data_fifo_full;
    logic [RxDepthW-1:0] rx_data_fifo_depth;

    // =========================================================================
    // RX Length FIFO Signals
    // =========================================================================

    logic             rx_len_fifo_wvalid;
    logic [31:0]      rx_len_fifo_wdata;
    logic             rx_len_fifo_rvalid, rx_len_fifo_rready;
    logic [31:0]      rx_len_fifo_rdata;
    logic             rx_len_fifo_full;
    logic [LenDepthW-1:0] rx_len_fifo_depth;

    // RX FIFO clear (shared between both RX FIFOs)
    logic             rx_fifo_clr;

    // =========================================================================
    // CSR Wrapper
    // =========================================================================

    usb_uart_csr u_csr (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .wb_m2s_i           (wb_m2s_i),
        .wb_s2m_o           (wb_s2m_o),
        .tx_wr_valid_o      (tx_wr_valid),
        .tx_wr_data_o       (tx_wr_data),
        .rx_rd_req_o        (rx_rd_req),
        .tx_en_o            (tx_en),
        .rx_en_o            (rx_en),
        .char_flush_en_o    (char_flush_en),
        .timeout_flush_en_o (timeout_flush_en),
        .thresh_flush_en_o  (thresh_flush_en),
        .sw_flush_o         (sw_flush),
        .tx_invalidate_o    (tx_invalidate),
        .rx_invalidate_o    (rx_invalidate),
        .flush_timeout_o    (flush_timeout),
        .flush_thresh_o     (flush_thresh),
        .flush_char_o       (flush_char),
        .sw_flush_ack_i     (sw_flush_ack),
        .tx_empty_i         (tx_empty),
        .tx_full_i          (tx_full),
        .tx_level_i         (tx_level),
        .rx_valid_i         (rx_valid),
        .rx_full_i          (rx_full),
        .rx_packets_i       (rx_packets),
        .rx_data_i          (rx_rd_data),
        .rx_len_i           (rx_len),
        .rx_data_overflow_i (rx_data_overflow),
        .rx_len_overflow_i  (rx_len_overflow),
        .irq_o              (irq_o)
    );

    // =========================================================================
    // TX Data FIFO
    // =========================================================================

    prim_fifo_sync #(
        .Width            (32),
        .Depth            (TX_DEPTH),
        .Pass             (1'b0),
        .OutputZeroIfEmpty(1'b0)
    ) u_tx_fifo (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .clr_i    (tx_fifo_clr),
        .wvalid_i (tx_fifo_wvalid),
        .wready_o (tx_fifo_wready),
        .wdata_i  (tx_fifo_wdata),
        .rvalid_o (tx_fifo_rvalid),
        .rready_i (tx_fifo_rready),
        .rdata_o  (tx_fifo_rdata),
        .full_o   (),  // TX ctrl derives full from wready
        .depth_o  (tx_fifo_depth),
        .err_o    ()
    );

    // =========================================================================
    // TX Control Logic
    // =========================================================================

    usb_uart_tx_ctrl #(
        .DEPTH      (TX_DEPTH),
        .CHANNEL_ID (CHANNEL_ID)
    ) u_tx_ctrl (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .wr_valid_i         (tx_wr_valid),
        .wr_data_i          (tx_wr_data),
        .fifo_wvalid_o      (tx_fifo_wvalid),
        .fifo_wdata_o       (tx_fifo_wdata),
        .fifo_wready_i      (tx_fifo_wready),
        .fifo_rdata_i       (tx_fifo_rdata),
        .fifo_rvalid_i      (tx_fifo_rvalid),
        .fifo_rready_o      (tx_fifo_rready),
        .fifo_depth_i       (tx_fifo_depth),
        .fifo_clr_o         (tx_fifo_clr),
        .tx_valid_o         (tx_valid_o),
        .tx_ready_i         (tx_ready_i),
        .tx_data_o          (tx_data_o),
        .tx_dst_o           (tx_dst_o),
        .tx_length_o        (tx_length_o),
        .tx_last_o          (tx_last_o),
        .enable_i           (tx_en),
        .sw_flush_i         (sw_flush),
        .invalidate_i       (tx_invalidate),
        .char_flush_en_i    (char_flush_en),
        .flush_char_i       (flush_char),
        .timeout_flush_en_i (timeout_flush_en),
        .thresh_flush_en_i  (thresh_flush_en),
        .flush_timeout_i    (flush_timeout),
        .flush_thresh_i     (flush_thresh),
        .sw_flush_ack_o     (sw_flush_ack),
        .empty_o            (tx_empty),
        .full_o             (tx_full),
        .level_o            (tx_level)
    );

    // =========================================================================
    // RX Data FIFO
    // =========================================================================

    prim_fifo_sync #(
        .Width            (32),
        .Depth            (RX_DEPTH),
        .Pass             (1'b0),
        .OutputZeroIfEmpty(1'b1)
    ) u_rx_data_fifo (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .clr_i    (rx_fifo_clr),
        .wvalid_i (rx_data_fifo_wvalid),
        .wready_o (rx_data_fifo_wready),
        .wdata_i  (rx_data_i),
        .rvalid_o (rx_data_fifo_rvalid),
        .rready_i (rx_data_fifo_rready),
        .rdata_o  (rx_data_fifo_rdata),
        .full_o   (rx_data_fifo_full),
        .depth_o  (rx_data_fifo_depth),
        .err_o    ()
    );

    // =========================================================================
    // RX Length FIFO
    // =========================================================================

    prim_fifo_sync #(
        .Width            (32),
        .Depth            (LEN_DEPTH),
        .Pass             (1'b0),
        .OutputZeroIfEmpty(1'b1)
    ) u_rx_len_fifo (
        .clk_i    (clk_i),
        .rst_ni   (rst_ni),
        .clr_i    (rx_fifo_clr),
        .wvalid_i (rx_len_fifo_wvalid),
        .wready_o (),  // Backpressure uses full_o via rx_ctrl
        .wdata_i  (rx_len_fifo_wdata),
        .rvalid_o (rx_len_fifo_rvalid),
        .rready_i (rx_len_fifo_rready),
        .rdata_o  (rx_len_fifo_rdata),
        .full_o   (rx_len_fifo_full),
        .depth_o  (rx_len_fifo_depth),
        .err_o    ()
    );

    // =========================================================================
    // RX Control Logic
    // =========================================================================

    usb_uart_rx_ctrl #(
        .LEN_DEPTH  (LEN_DEPTH)
    ) u_rx_ctrl (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .rx_valid_i          (rx_valid_i),
        .rx_ready_o          (rx_ready_o),
        .rx_length_i         (rx_length_i),
        .rx_last_i           (rx_last_i),
        .data_fifo_wvalid_o  (rx_data_fifo_wvalid),
        .data_fifo_wready_i  (rx_data_fifo_wready),
        .data_fifo_rdata_i   (rx_data_fifo_rdata),
        .data_fifo_rvalid_i  (rx_data_fifo_rvalid),
        .data_fifo_rready_o  (rx_data_fifo_rready),
        .data_fifo_full_i    (rx_data_fifo_full),
        .len_fifo_wvalid_o   (rx_len_fifo_wvalid),
        .len_fifo_wdata_o    (rx_len_fifo_wdata),
        .len_fifo_rdata_i    (rx_len_fifo_rdata),
        .len_fifo_rvalid_i   (rx_len_fifo_rvalid),
        .len_fifo_rready_o   (rx_len_fifo_rready),
        .len_fifo_full_i     (rx_len_fifo_full),
        .len_fifo_depth_i    (rx_len_fifo_depth),
        .fifo_clr_o          (rx_fifo_clr),
        .cpu_rd_req_i        (rx_rd_req),
        .cpu_rd_data_o       (rx_rd_data),
        .cpu_rx_len_o        (rx_len),
        .enable_i            (rx_en),
        .invalidate_i        (rx_invalidate),
        .rx_valid_o          (rx_valid),
        .rx_full_o           (rx_full),
        .rx_packets_o        (rx_packets),
        .data_overflow_o     (rx_data_overflow),
        .len_overflow_o      (rx_len_overflow)
    );

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{rx_dst_i, rx_data_fifo_depth};

endmodule
