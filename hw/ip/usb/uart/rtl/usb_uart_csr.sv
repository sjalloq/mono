// SPDX-License-Identifier: BSD-2-Clause
// USB UART CSR Wrapper
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Wraps Wishbone-to-simple-bus adapter, auto-generated CSR register block,
// and IRQ generation. Translates CSR register names to clean datapath names:
//   ctrl.tx_flush  -> sw_flush_o      (send buffered TX data)
//   ctrl.tx_clear  -> tx_invalidate_o (discard TX FIFO contents)
//   ctrl.rx_flush  -> rx_invalidate_o (discard RX FIFO contents)

module usb_uart_csr
    import wb_pkg::*;
    import usb_uart_csr_reg_pkg::*;
(
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // Wishbone Slave Interface
    // =========================================================================
    input  wb_m2s_t          wb_m2s_i,
    output wb_s2m_t          wb_s2m_o,

    // =========================================================================
    // TX Write Interface (CPU write to TX_DATA register)
    // =========================================================================
    output logic             tx_wr_valid_o,
    output logic [31:0]      tx_wr_data_o,

    // =========================================================================
    // RX Read Interface (CPU read of RX_DATA register)
    // =========================================================================
    output logic             rx_rd_req_o,

    // =========================================================================
    // Control Outputs (decoded from CSR registers)
    // =========================================================================
    output logic             tx_en_o,
    output logic             rx_en_o,
    output logic             char_flush_en_o,
    output logic             timeout_flush_en_o,
    output logic             thresh_flush_en_o,
    output logic             sw_flush_o,          // Send TX data (reg: ctrl.tx_flush)
    output logic             tx_invalidate_o,     // Discard TX data (reg: ctrl.tx_clear)
    output logic             rx_invalidate_o,     // Discard RX data (reg: ctrl.rx_flush)
    output logic [31:0]      flush_timeout_o,
    output logic [7:0]       flush_thresh_o,
    output logic [7:0]       flush_char_o,

    // =========================================================================
    // Ack Input (from TX ctrl, for de-pulsing sw_flush)
    // =========================================================================
    input  logic             sw_flush_ack_i,

    // =========================================================================
    // Status Inputs (from datapath)
    // =========================================================================
    input  logic             tx_empty_i,
    input  logic             tx_full_i,
    input  logic [3:0]       tx_level_i,
    input  logic             rx_valid_i,
    input  logic             rx_full_i,
    input  logic [3:0]       rx_packets_i,
    input  logic [31:0]      rx_data_i,
    input  logic [31:0]      rx_len_i,

    // =========================================================================
    // Overflow Pulses (for sticky IRQ bits)
    // =========================================================================
    input  logic             rx_data_overflow_i,
    input  logic             rx_len_overflow_i,

    // =========================================================================
    // Interrupt Output
    // =========================================================================
    output logic             irq_o
);

    // =========================================================================
    // Simple Bus Interface Signals
    // =========================================================================

    logic             reg_we;
    logic             reg_re;
    logic [31:0]      reg_addr;
    logic [31:0]      reg_wdata;
    logic [31:0]      reg_rdata;

    // Hardware interface structs
    usb_uart_csr_reg2hw_t reg2hw;
    usb_uart_csr_hw2reg_t hw2reg;

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
    // CSR Register Block
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
    // Control Signal Mapping (CSR register names -> clean datapath names)
    // =========================================================================

    assign tx_en_o            = reg2hw.ctrl.tx_en.q;
    assign rx_en_o            = reg2hw.ctrl.rx_en.q;
    assign char_flush_en_o    = reg2hw.ctrl.char_flush_en.q;
    assign timeout_flush_en_o = reg2hw.ctrl.timeout_flush_en.q;
    assign thresh_flush_en_o  = reg2hw.ctrl.thresh_flush_en.q;
    assign sw_flush_o         = reg2hw.ctrl.tx_flush.q;      // "flush" = send data
    assign flush_timeout_o    = reg2hw.timeout.q;
    assign flush_thresh_o     = reg2hw.thresh.q;
    assign flush_char_o       = reg2hw.flush_char.q;

    // Invalidate signals: single-cycle pulses, self-acked
    logic sw_tx_clear;
    logic sw_rx_flush;
    assign sw_tx_clear    = reg2hw.ctrl.tx_clear.q;
    assign sw_rx_flush    = reg2hw.ctrl.rx_flush.q;
    assign tx_invalidate_o = sw_tx_clear;
    assign rx_invalidate_o = sw_rx_flush;

    // =========================================================================
    // TX_DATA / RX_DATA Detection
    // =========================================================================

    assign tx_wr_valid_o = reg_we && (reg_addr[BlockAw-1:0] == USB_UART_CSR_TX_DATA_OFFSET);
    assign tx_wr_data_o  = reg_wdata;

    assign rx_rd_req_o = reg_re && (reg_addr[BlockAw-1:0] == USB_UART_CSR_RX_DATA_OFFSET);

    // =========================================================================
    // Status Outputs to CSR
    // =========================================================================

    assign hw2reg.status.tx_empty.d   = tx_empty_i;
    assign hw2reg.status.tx_full.d    = tx_full_i;
    assign hw2reg.status.rx_valid.d   = rx_valid_i;
    assign hw2reg.status.rx_full.d    = rx_full_i;
    assign hw2reg.status.tx_level.d   = tx_level_i;
    assign hw2reg.status.rx_packets.d = rx_packets_i;

    assign hw2reg.rx_data.d = rx_data_i;
    assign hw2reg.rx_len.d  = rx_len_i;

    // =========================================================================
    // De-pulse Control Bits
    // =========================================================================

    // sw_flush: cleared when TX ctrl acknowledges the flush
    assign hw2reg.ctrl.tx_flush.d  = 1'b0;
    assign hw2reg.ctrl.tx_flush.de = sw_flush_ack_i;

    // tx_invalidate (tx_clear): single-cycle pulse, self-ack
    assign hw2reg.ctrl.tx_clear.d  = 1'b0;
    assign hw2reg.ctrl.tx_clear.de = sw_tx_clear;

    // rx_invalidate (rx_flush): single-cycle pulse, self-ack
    assign hw2reg.ctrl.rx_flush.d  = 1'b0;
    assign hw2reg.ctrl.rx_flush.de = sw_rx_flush;

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
            rx_valid_prev <= rx_valid_i;
            tx_empty_prev <= tx_empty_i;
        end
    end

    logic rx_valid_rising, tx_empty_rising;
    assign rx_valid_rising = rx_valid_i && !rx_valid_prev;
    assign tx_empty_rising = tx_empty_i && !tx_empty_prev;

    // IRQ status sticky bits (set by HW pulse, cleared by SW writing 1)
    assign hw2reg.irq_status.rx_valid.d      = 1'b1;
    assign hw2reg.irq_status.rx_valid.de     = rx_valid_rising;
    assign hw2reg.irq_status.tx_empty.d      = 1'b1;
    assign hw2reg.irq_status.tx_empty.de     = tx_empty_rising;
    assign hw2reg.irq_status.rx_overflow.d   = 1'b1;
    assign hw2reg.irq_status.rx_overflow.de  = rx_data_overflow_i;
    assign hw2reg.irq_status.len_overflow.d  = 1'b1;
    assign hw2reg.irq_status.len_overflow.de = rx_len_overflow_i;

    // IRQ output: OR of (status & enable)
    logic [3:0] irq_status_vec, irq_enable_vec;
    assign irq_status_vec = {reg2hw.irq_status.len_overflow.q,
                             reg2hw.irq_status.rx_overflow.q,
                             reg2hw.irq_status.tx_empty.q,
                             reg2hw.irq_status.rx_valid.q};
    assign irq_enable_vec = {reg2hw.irq_enable.len_overflow.q,
                             reg2hw.irq_enable.rx_overflow.q,
                             reg2hw.irq_enable.tx_empty.q,
                             reg2hw.irq_enable.rx_valid.q};
    assign irq_o = |(irq_status_vec & irq_enable_vec);

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{reg_addr[31:BlockAw], reg2hw.tx_data};

endmodule
