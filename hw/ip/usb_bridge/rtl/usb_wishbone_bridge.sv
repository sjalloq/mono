// SPDX-License-Identifier: BSD-2-Clause
// USB Wishbone Bridge
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// A UART-like Wishbone slave module for CPU<->USB Host communication.
// The on-chip CPU can send/receive data to/from the host via simple
// FIFO-style register access.
//
// Features:
// - TX FIFO with multiple flush mechanisms (timeout, threshold, character match)
// - RX FIFO with software flush
// - Loopback mode for testing
// - Configurable IRQ generation

module usb_wishbone_bridge
    import usb_bridge_csr_reg_pkg::*;
#(
    parameter int unsigned TX_DEPTH        = 64,
    parameter int unsigned RX_DEPTH        = 64,
    parameter int unsigned AW              = 32,
    parameter int unsigned DW              = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone slave interface
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

    // USB TX streaming interface (to USB core)
    output logic             usb_tx_valid_o,
    input  logic             usb_tx_ready_i,
    output logic             usb_tx_last_o,
    output logic [31:0]      usb_tx_data_o,

    // USB RX streaming interface (from USB core)
    input  logic             usb_rx_valid_i,
    output logic             usb_rx_ready_o,
    input  logic             usb_rx_last_i,
    input  logic [31:0]      usb_rx_data_i,

    // IRQ output
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
    usb_bridge_csr_reg2hw_t reg2hw;
    usb_bridge_csr_hw2reg_t hw2reg;

    // TX FIFO signals
    logic             tx_fifo_wr_valid;
    logic             tx_fifo_wr_ready;
    logic [31:0]      tx_fifo_wr_data;
    logic             tx_fifo_rd_valid;
    logic             tx_fifo_rd_ready;
    logic [31:0]      tx_fifo_rd_data;
    logic             tx_fifo_rd_last;
    logic             tx_fifo_ready;
    logic             tx_fifo_full;
    logic             tx_fifo_empty;
    logic [15:0]      tx_fifo_level;
    logic             tx_fifo_overflow;
    logic             tx_fifo_flushing;

    // RX FIFO signals
    logic             rx_fifo_wr_valid;
    logic             rx_fifo_wr_ready;
    logic [31:0]      rx_fifo_wr_data;
    logic             rx_fifo_rd_req;
    logic [31:0]      rx_fifo_rd_data;
    logic             rx_fifo_rd_valid;
    logic             rx_fifo_valid;
    logic             rx_fifo_full;
    logic             rx_fifo_empty;
    logic [15:0]      rx_fifo_level;
    logic             rx_fifo_overflow;

    // Control signals from CSR
    logic             tx_enable;
    logic             rx_enable;
    logic             loopback;
    logic             sw_tx_flush;
    logic             sw_rx_flush;
    logic             timeout_flush_en;
    logic             thresh_flush_en;
    logic             char_flush_en;
    logic [31:0]      flush_timeout;
    logic [15:0]      flush_thresh;
    logic [7:0]       flush_char;

    // IRQ control
    logic             irq_tx_empty_en;
    logic             irq_rx_valid_en;
    logic             irq_tx_low_en;
    logic             irq_rx_high_en;
    logic [15:0]      tx_watermark;
    logic [15:0]      rx_watermark;

    // Overflow sticky bits
    logic             tx_overflow_sticky_q, tx_overflow_sticky_d;
    logic             rx_overflow_sticky_q, rx_overflow_sticky_d;

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

    usb_bridge_csr_reg_top #(
        .ResetType (rdl_subreg_pkg::ActiveLowAsync)
    ) u_csr (
        .clk       (clk_i),
        .rst       (rst_ni),
        .reg_we    (reg_we),
        .reg_re    (reg_re),
        .reg_addr  (reg_addr[5:0]),  // CSR block uses 6-bit address
        .reg_wdata (reg_wdata),
        .reg_rdata (reg_rdata),
        .reg2hw    (reg2hw),
        .hw2reg    (hw2reg)
    );

    // =========================================================================
    // CSR Signal Mapping
    // =========================================================================

    // Control signals from registers
    assign tx_enable         = reg2hw.control.tx_enable.q;
    assign rx_enable         = reg2hw.control.rx_enable.q;
    assign sw_tx_flush       = reg2hw.control.tx_flush.q;
    assign sw_rx_flush       = reg2hw.control.rx_flush.q;
    assign timeout_flush_en  = reg2hw.control.timeout_flush_en.q;
    assign thresh_flush_en   = reg2hw.control.thresh_flush_en.q;
    assign char_flush_en     = reg2hw.control.char_flush_en.q;
    assign loopback          = reg2hw.control.loopback.q;
    assign irq_tx_empty_en   = reg2hw.control.irq_tx_empty_en.q;
    assign irq_rx_valid_en   = reg2hw.control.irq_rx_valid_en.q;
    assign irq_tx_low_en     = reg2hw.control.irq_tx_low_en.q;
    assign irq_rx_high_en    = reg2hw.control.irq_rx_high_en.q;

    assign flush_timeout     = reg2hw.flush_timeout.q;
    assign flush_thresh      = reg2hw.flush_thresh.q;
    assign flush_char        = reg2hw.flush_char.q;
    assign tx_watermark      = reg2hw.tx_watermark.q;
    assign rx_watermark      = reg2hw.rx_watermark.q;

    // TX_DATA: CPU writes trigger FIFO write
    // The reg2hw.tx_data.q contains the written data
    // We need to detect when a write occurs - use address decode
    logic tx_data_write;
    assign tx_data_write = reg_we && (reg_addr[5:0] == USB_BRIDGE_CSR_TX_DATA_OFFSET);
    assign tx_fifo_wr_valid = tx_data_write;
    assign tx_fifo_wr_data  = reg_wdata;

    // RX_DATA: CPU reads trigger FIFO pop
    logic rx_data_read;
    assign rx_data_read = reg_re && (reg_addr[5:0] == USB_BRIDGE_CSR_RX_DATA_OFFSET);
    assign rx_fifo_rd_req = rx_data_read;

    // Status outputs to CSR
    assign hw2reg.status.tx_ready.d   = tx_fifo_ready;
    assign hw2reg.status.tx_full.d    = tx_fifo_full;
    assign hw2reg.status.tx_empty.d   = tx_fifo_empty;
    assign hw2reg.status.rx_valid.d   = rx_fifo_valid;
    assign hw2reg.status.rx_full.d    = rx_fifo_full;
    assign hw2reg.status.rx_empty.d   = rx_fifo_empty;

    // Overflow sticky bits
    assign hw2reg.status.tx_overflow.d  = 1'b1;
    assign hw2reg.status.tx_overflow.de = tx_fifo_overflow;
    assign hw2reg.status.rx_overflow.d  = 1'b1;
    assign hw2reg.status.rx_overflow.de = rx_fifo_overflow;

    // Level outputs (external registers)
    assign hw2reg.tx_level.d = tx_fifo_level;
    assign hw2reg.rx_level.d = rx_fifo_level;

    // RX data output (external register)
    assign hw2reg.rx_data.d = rx_fifo_rd_data;

    // =========================================================================
    // TX FIFO
    // =========================================================================

    usb_bridge_tx_fifo #(
        .DEPTH (TX_DEPTH),
        .DW    (32)
    ) u_tx_fifo (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .wr_valid_i         (tx_fifo_wr_valid),
        .wr_ready_o         (tx_fifo_wr_ready),
        .wr_data_i          (tx_fifo_wr_data),
        .rd_valid_o         (tx_fifo_rd_valid),
        .rd_ready_i         (tx_fifo_rd_ready),
        .rd_data_o          (tx_fifo_rd_data),
        .rd_last_o          (tx_fifo_rd_last),
        .enable_i           (tx_enable),
        .sw_flush_i         (sw_tx_flush),
        .timeout_flush_en_i (timeout_flush_en),
        .thresh_flush_en_i  (thresh_flush_en),
        .char_flush_en_i    (char_flush_en),
        .flush_timeout_i    (flush_timeout),
        .flush_thresh_i     (flush_thresh),
        .flush_char_i       (flush_char),
        .ready_o            (tx_fifo_ready),
        .full_o             (tx_fifo_full),
        .empty_o            (tx_fifo_empty),
        .level_o            (tx_fifo_level),
        .overflow_o         (tx_fifo_overflow),
        .flushing_o         (tx_fifo_flushing)
    );

    // =========================================================================
    // RX FIFO
    // =========================================================================

    usb_bridge_rx_fifo #(
        .DEPTH (RX_DEPTH),
        .DW    (32)
    ) u_rx_fifo (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .wr_valid_i (rx_fifo_wr_valid),
        .wr_ready_o (rx_fifo_wr_ready),
        .wr_data_i  (rx_fifo_wr_data),
        .rd_req_i   (rx_fifo_rd_req),
        .rd_data_o  (rx_fifo_rd_data),
        .rd_valid_o (rx_fifo_rd_valid),
        .enable_i   (rx_enable),
        .sw_flush_i (sw_rx_flush),
        .valid_o    (rx_fifo_valid),
        .full_o     (rx_fifo_full),
        .empty_o    (rx_fifo_empty),
        .level_o    (rx_fifo_level),
        .overflow_o (rx_fifo_overflow)
    );

    // =========================================================================
    // Loopback / USB Interface Mux
    // =========================================================================

    // TX output (to USB or loopback)
    assign usb_tx_valid_o = loopback ? 1'b0 : tx_fifo_rd_valid;
    assign usb_tx_data_o  = tx_fifo_rd_data;
    assign usb_tx_last_o  = tx_fifo_rd_last;

    // TX FIFO read ready
    assign tx_fifo_rd_ready = loopback ? rx_fifo_wr_ready : usb_tx_ready_i;

    // RX input (from USB or loopback)
    assign rx_fifo_wr_valid = loopback ? tx_fifo_rd_valid : usb_rx_valid_i;
    assign rx_fifo_wr_data  = loopback ? tx_fifo_rd_data  : usb_rx_data_i;

    // RX ready to USB
    assign usb_rx_ready_o = loopback ? 1'b0 : rx_fifo_wr_ready;

    // =========================================================================
    // IRQ Generation
    // =========================================================================

    logic irq_tx_empty;
    logic irq_rx_valid;
    logic irq_tx_low;
    logic irq_rx_high;

    assign irq_tx_empty = irq_tx_empty_en && tx_fifo_empty;
    assign irq_rx_valid = irq_rx_valid_en && rx_fifo_valid;
    assign irq_tx_low   = irq_tx_low_en   && (tx_fifo_level < tx_watermark);
    assign irq_rx_high  = irq_rx_high_en  && (rx_fifo_level > rx_watermark);

    assign irq_o = irq_tx_empty || irq_rx_valid || irq_tx_low || irq_rx_high;

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{usb_rx_last_i, rx_fifo_rd_valid};

endmodule
