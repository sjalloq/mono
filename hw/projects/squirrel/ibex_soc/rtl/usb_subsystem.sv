// SPDX-License-Identifier: BSD-2-Clause
// USB Subsystem
//
// Copyright (c) 2026 Shareef Jalloq
//
// Integrates USB Core (Migen-generated channel mux) with USB UART peripheral.
// Runs entirely in the sys_clk domain.
//
// Channel assignment:
//   ch0 = USB UART (printf/REPL)
//   ch1 = Etherbone (future, tied off)

module usb_subsystem
    import wb_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    // PHY stream interface (to FT601 or testbench)
    input  logic [31:0] phy_rx_data_i,
    input  logic        phy_rx_valid_i,
    output logic        phy_rx_ready_o,

    output logic [31:0] phy_tx_data_o,
    output logic        phy_tx_valid_o,
    input  logic        phy_tx_ready_i,

    // Etherbone Wishbone master (to SoC, tied off for now)
    output wb_m2s_t     eb_wb_m2s_o,
    input  wb_s2m_t     eb_wb_s2m_i,

    // USB UART Wishbone slave (from SoC crossbar)
    input  wb_m2s_t     uart_wb_m2s_i,
    output wb_s2m_t     uart_wb_s2m_o,

    // USB UART interrupt
    output logic        uart_irq_o
);

    // =========================================================================
    // Internal signals: USB Core <-> USB UART (ch0)
    // =========================================================================

    // ch0 TX: UART -> USB Core (data to host)
    logic        ch0_tx_valid;
    logic        ch0_tx_ready;
    logic [31:0] ch0_tx_data;
    logic [7:0]  ch0_tx_dst;
    logic [31:0] ch0_tx_length;
    logic        ch0_tx_last;
    logic        ch0_tx_first;
    logic [3:0]  ch0_tx_error;

    // ch0 RX: USB Core -> UART (data from host)
    logic        ch0_rx_valid;
    logic        ch0_rx_ready;
    logic [31:0] ch0_rx_data;
    logic [7:0]  ch0_rx_dst;
    logic [31:0] ch0_rx_length;
    logic        ch0_rx_last;
    logic        ch0_rx_first;
    logic [3:0]  ch0_rx_error;

    // =========================================================================
    // Internal signals: USB Core ch1 (tied off)
    // =========================================================================

    logic        ch1_tx_ready;
    logic        ch1_rx_valid;
    logic [31:0] ch1_rx_data;
    logic [7:0]  ch1_rx_dst;
    logic [31:0] ch1_rx_length;
    logic        ch1_rx_last;
    logic        ch1_rx_first;
    logic [3:0]  ch1_rx_error;

    // =========================================================================
    // USB Core (Migen-generated channel mux)
    // =========================================================================

    usb_core u_usb_core (
        .sys_clk        (clk_i),
        .sys_rst        (~rst_ni),

        // PHY RX (from FT601)
        .phy_rx_data    (phy_rx_data_i),
        .phy_rx_valid   (phy_rx_valid_i),
        .phy_rx_ready   (phy_rx_ready_o),
        .phy_rx_first   (1'b0),
        .phy_rx_last    (1'b0),

        // PHY TX (to FT601)
        .phy_tx_data    (phy_tx_data_o),
        .phy_tx_valid   (phy_tx_valid_o),
        .phy_tx_ready   (phy_tx_ready_i),
        .phy_tx_first   (),
        .phy_tx_last    (),

        // Channel 0: USB UART
        .ch0_rx_valid   (ch0_rx_valid),
        .ch0_rx_ready   (ch0_rx_ready),
        .ch0_rx_data    (ch0_rx_data),
        .ch0_rx_dst     (ch0_rx_dst),
        .ch0_rx_length  (ch0_rx_length),
        .ch0_rx_last    (ch0_rx_last),
        .ch0_rx_first   (ch0_rx_first),
        .ch0_rx_error   (ch0_rx_error),

        .ch0_tx_valid   (ch0_tx_valid),
        .ch0_tx_ready   (ch0_tx_ready),
        .ch0_tx_data    (ch0_tx_data),
        .ch0_tx_dst     (ch0_tx_dst),
        .ch0_tx_length  (ch0_tx_length),
        .ch0_tx_last    (ch0_tx_last),
        .ch0_tx_first   (ch0_tx_first),
        .ch0_tx_error   (ch0_tx_error),

        // Channel 1: Etherbone (tied off)
        .ch1_rx_valid   (ch1_rx_valid),
        .ch1_rx_ready   (1'b0),
        .ch1_rx_data    (ch1_rx_data),
        .ch1_rx_dst     (ch1_rx_dst),
        .ch1_rx_length  (ch1_rx_length),
        .ch1_rx_last    (ch1_rx_last),
        .ch1_rx_first   (ch1_rx_first),
        .ch1_rx_error   (ch1_rx_error),

        .ch1_tx_valid   (1'b0),
        .ch1_tx_ready   (ch1_tx_ready),
        .ch1_tx_data    (32'b0),
        .ch1_tx_dst     (8'b0),
        .ch1_tx_length  (32'b0),
        .ch1_tx_last    (1'b0),
        .ch1_tx_first   (1'b0),
        .ch1_tx_error   (4'b0)
    );

    // =========================================================================
    // USB UART (ch0)
    // =========================================================================

    usb_uart #(
        .CHANNEL_ID (0)
    ) u_usb_uart (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // Wishbone slave (from SoC crossbar)
        .wb_m2s_i    (uart_wb_m2s_i),
        .wb_s2m_o    (uart_wb_s2m_o),

        // TX stream (UART -> USB Core ch0)
        .tx_valid_o  (ch0_tx_valid),
        .tx_ready_i  (ch0_tx_ready),
        .tx_data_o   (ch0_tx_data),
        .tx_dst_o    (ch0_tx_dst),
        .tx_length_o (ch0_tx_length),
        .tx_last_o   (ch0_tx_last),

        // RX stream (USB Core ch0 -> UART)
        .rx_valid_i  (ch0_rx_valid),
        .rx_ready_o  (ch0_rx_ready),
        .rx_data_i   (ch0_rx_data),
        .rx_dst_i    (ch0_rx_dst),
        .rx_length_i (ch0_rx_length),
        .rx_last_i   (ch0_rx_last),

        // Interrupt
        .irq_o       (uart_irq_o)
    );

    // ch0 TX first/error: not used by usb_uart, tie to defaults
    assign ch0_tx_first = 1'b0;
    assign ch0_tx_error = 4'b0;

    // =========================================================================
    // Etherbone Wishbone master (tied off for now)
    // =========================================================================

    assign eb_wb_m2s_o = '0;

    // =========================================================================
    // Unused signal handling
    // =========================================================================

    logic unused;
    assign unused = &{eb_wb_s2m_i,
                      ch0_rx_first, ch0_rx_error,
                      ch1_rx_valid, ch1_rx_data, ch1_rx_dst, ch1_rx_length,
                      ch1_rx_last, ch1_rx_first, ch1_rx_error,
                      ch1_tx_ready};

endmodule
