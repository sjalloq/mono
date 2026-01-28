// SPDX-License-Identifier: BSD-2-Clause
// USB UART - Bidirectional Character Stream over USB
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Provides printf output and REPL input over USB channel.
// Replaces traditional UART for CPU debug I/O.
//
// Features:
// - TX: Auto-flush on newline, timeout, or threshold
// - RX: Packet-aware dual-FIFO preserves message boundaries
// - IRQ support for TX empty and RX packet available

module usb_uart
    import usb_uart_csr_reg_pkg::*;
#(
    parameter int unsigned TX_DEPTH   = 64,
    parameter int unsigned RX_DEPTH   = 64,
    parameter int unsigned LEN_DEPTH  = 4,
    parameter int unsigned CHANNEL_ID = 2,
    parameter int unsigned AW         = 32,
    parameter int unsigned DW         = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // Wishbone Slave Interface
    // =========================================================================
    input  logic             wb_cyc_i,
    input  logic             wb_stb_i,
    input  logic             wb_we_i,
    input  logic [AW-1:0]    wb_adr_i,
    input  logic [DW/8-1:0]  wb_sel_i,
    input  logic [DW-1:0]    wb_dat_i,
    output logic [DW-1:0]    wb_dat_o,
    output logic             wb_ack_o,
    output logic             wb_err_o,
    output logic             wb_stall_o,

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
    logic [AW-1:0]    reg_addr;
    logic [DW-1:0]    reg_wdata;
    logic [DW-1:0]    reg_rdata;

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

    // Control signals from CSR
    logic             tx_en;
    logic             rx_en;
    logic             nl_flush_en;
    logic             timeout_flush_en;
    logic             thresh_flush_en;
    logic             sw_tx_flush;
    logic             sw_rx_flush;
    logic             irq_rx_en;
    logic             irq_tx_empty_en;
    logic [31:0]      flush_timeout;
    logic [7:0]       flush_thresh;

    // =========================================================================
    // Wishbone to Simple Bus Adapter
    // =========================================================================

    wb2simple #(
        .AW (AW),
        .DW (DW)
    ) u_wb2simple (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .wb_cyc_i   (wb_cyc_i),
        .wb_stb_i   (wb_stb_i),
        .wb_we_i    (wb_we_i),
        .wb_adr_i   (wb_adr_i),
        .wb_sel_i   (wb_sel_i),
        .wb_dat_i   (wb_dat_i),
        .wb_dat_o   (wb_dat_o),
        .wb_ack_o   (wb_ack_o),
        .wb_err_o   (wb_err_o),
        .wb_stall_o (wb_stall_o),
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
    assign nl_flush_en      = reg2hw.ctrl.nl_flush_en.q;
    assign timeout_flush_en = reg2hw.ctrl.timeout_flush_en.q;
    assign thresh_flush_en  = reg2hw.ctrl.thresh_flush_en.q;
    assign sw_tx_flush      = reg2hw.ctrl.tx_flush.q;
    assign sw_rx_flush      = reg2hw.ctrl.rx_flush.q;
    assign irq_rx_en        = reg2hw.ctrl.irq_rx_en.q;
    assign irq_tx_empty_en  = reg2hw.ctrl.irq_tx_empty_en.q;
    assign flush_timeout    = reg2hw.timeout.q;
    assign flush_thresh     = reg2hw.thresh.q;

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
        .nl_flush_en_i      (nl_flush_en),
        .timeout_flush_en_i (timeout_flush_en),
        .thresh_flush_en_i  (thresh_flush_en),
        .flush_timeout_i    (flush_timeout),
        .flush_thresh_i     (flush_thresh),
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
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .rx_valid_i     (rx_valid_i),
        .rx_ready_o     (rx_ready_o),
        .rx_data_i      (rx_data_i),
        .rx_length_i    (rx_length_i),
        .rx_last_i      (rx_last_i),
        .cpu_rd_req_i   (rx_rd_req),
        .cpu_rd_data_o  (rx_rd_data),
        .cpu_rx_len_o   (rx_len),
        .enable_i       (rx_en),
        .sw_flush_i     (sw_rx_flush),
        .rx_valid_o     (rx_valid),
        .rx_full_o      (rx_full),
        .rx_packets_o   (rx_packets)
    );

    // =========================================================================
    // IRQ Generation
    // =========================================================================

    logic irq_rx;
    logic irq_tx_empty;

    assign irq_rx       = irq_rx_en && rx_valid;
    assign irq_tx_empty = irq_tx_empty_en && tx_empty;

    assign irq_o = irq_rx || irq_tx_empty;

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{rx_dst_i, reg_addr[AW-1:BlockAw], reg2hw.tx_data};

endmodule
