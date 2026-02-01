// SPDX-License-Identifier: BSD-2-Clause
// Squirrel SERV SoC Core Level
//
// Copyright (c) 2026 Shareef Jalloq
//
// Core/Functional level of hierarchy. Everything but the Xilinx prims.
// Contains:
//   - FT601 PHY (usb_clk domain)
//   - USB Subsystem (sys_clk domain)
//   - SERV SoC (sys_clk domain)
//   - LED heartbeat
//
// CDC between FT601 (usb_clk) and USB subsystem (sys_clk) is handled by
// prim_fifo_async instances below.

module core
    import wb_pkg::*;
#(
    parameter string TcmInitFile = ""   // Hex file for TCM initialization
) (
    // System clock and reset
    input  logic        sys_clk,
    input  logic        sys_rst_n,

    // User LEDs
    output logic [1:0]  user_led,

    // User switches
    input  logic [1:0]  user_sw,

    // FT601 USB 3.0 FIFO interface (split signals from IOBUFs)
    input  logic        usb_clk_i,
    input  logic [31:0] usb_data_i,
    output logic [31:0] usb_data_o,
    output logic        usb_data_oe,
    output logic [3:0]  usb_be_o,
    output logic        usb_be_oe,
    input  logic        usb_rxf_ni,
    input  logic        usb_txe_ni,
    output logic        usb_rd_no,
    output logic        usb_wr_no,
    output logic        usb_oe_no,
    output logic        usb_siwu_no,
    output logic        usb_rst_no,

    // Simulation control (directly accessible by testbench)
    output logic        sim_halt_o,
    output logic        sim_char_valid_o,
    output logic [7:0]  sim_char_data_o
);

    // =========================================================================
    // LED Heartbeat (simple counter to show FPGA is alive)
    // =========================================================================

    logic [26:0] led_counter;

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led_counter <= '0;
        end else begin
            led_counter <= led_counter + 1'b1;
        end
    end

    // LED[0]: heartbeat blink (~0.75Hz)
    // LED[1]: directly controlled by switch for basic I/O test
    assign user_led[0] = led_counter[26];
    assign user_led[1] = user_sw[0];

    // =========================================================================
    // USB Domain Reset Synchronizer
    // =========================================================================

    logic usb_rst_n;
    logic [3:0] usb_rst_sync;

    always_ff @(posedge usb_clk_i) begin
        usb_rst_sync <= {usb_rst_sync[2:0], 1'b1};
    end

    assign usb_rst_n = usb_rst_sync[3];

    // =========================================================================
    // FT601 PHY (USB clock domain)
    // =========================================================================

    logic [31:0] ft601_rx_data;
    logic        ft601_rx_valid;
    logic [31:0] ft601_tx_data;
    logic        ft601_tx_valid;
    logic        ft601_tx_ready;

    ft601_sync #(
        .DW (32)
    ) u_ft601 (
        .clk_i      (usb_clk_i),
        .rst_ni     (usb_rst_n),

        // FT601 control signals
        .rxf_ni     (usb_rxf_ni),
        .txe_ni     (usb_txe_ni),
        .rd_no      (usb_rd_no),
        .wr_no      (usb_wr_no),
        .oe_no      (usb_oe_no),
        .siwu_no    (usb_siwu_no),
        .rst_no     (usb_rst_no),

        // Data bus (directly to tristate IOBUFs in top)
        .data_i     (usb_data_i),
        .data_o     (usb_data_o),
        .data_oe    (usb_data_oe),
        .be_o       (usb_be_o),
        .be_oe      (usb_be_oe),

        // RX stream (data from USB host)
        .rx_data_o  (ft601_rx_data),
        .rx_valid_o (ft601_rx_valid),

        // TX stream (data to USB host)
        .tx_data_i  (ft601_tx_data),
        .tx_valid_i (ft601_tx_valid),
        .tx_ready_o (ft601_tx_ready)
    );

    // =========================================================================
    // CDC FIFOs (usb_clk <-> sys_clk)
    // =========================================================================

    // RX path: FT601 (usb_clk) -> USB subsystem (sys_clk)
    logic [31:0] cdc_rx_data;
    logic        cdc_rx_valid;
    logic        cdc_rx_ready;

    prim_fifo_async #(
        .Width (32),
        .Depth (4)
    ) u_cdc_rx_fifo (
        .clk_wr_i  (usb_clk_i),
        .rst_wr_ni (usb_rst_n),
        .wvalid_i  (ft601_rx_valid),
        .wready_o  (),  // FT601 RX has no backpressure
        .wdata_i   (ft601_rx_data),
        .wdepth_o  (),

        .clk_rd_i  (sys_clk),
        .rst_rd_ni (sys_rst_n),
        .rvalid_o  (cdc_rx_valid),
        .rready_i  (cdc_rx_ready),
        .rdata_o   (cdc_rx_data),
        .rdepth_o  ()
    );

    // TX path: USB subsystem (sys_clk) -> FT601 (usb_clk)
    logic [31:0] cdc_tx_data;
    logic        cdc_tx_valid;
    logic        cdc_tx_ready;

    prim_fifo_async #(
        .Width (32),
        .Depth (4)
    ) u_cdc_tx_fifo (
        .clk_wr_i  (sys_clk),
        .rst_wr_ni (sys_rst_n),
        .wvalid_i  (cdc_tx_valid),
        .wready_o  (cdc_tx_ready),
        .wdata_i   (cdc_tx_data),
        .wdepth_o  (),

        .clk_rd_i  (usb_clk_i),
        .rst_rd_ni (usb_rst_n),
        .rvalid_o  (ft601_tx_valid),
        .rready_i  (ft601_tx_ready),
        .rdata_o   (ft601_tx_data),
        .rdepth_o  ()
    );

    // =========================================================================
    // USB Subsystem (sys_clk domain)
    // =========================================================================

    wb_m2s_t uart_wb_m2s;
    wb_s2m_t uart_wb_s2m;
    logic    uart_irq;

    usb_subsystem u_usb_subsystem (
        .clk_i          (sys_clk),
        .rst_ni         (sys_rst_n),

        // PHY stream (from CDC FIFOs, now in sys_clk domain)
        .phy_rx_data_i  (cdc_rx_data),
        .phy_rx_valid_i (cdc_rx_valid),
        .phy_rx_ready_o (cdc_rx_ready),

        .phy_tx_data_o  (cdc_tx_data),
        .phy_tx_valid_o (cdc_tx_valid),
        .phy_tx_ready_i (cdc_tx_ready),

        // USB UART WB slave (from SoC crossbar)
        .uart_wb_m2s_i  (uart_wb_m2s),
        .uart_wb_s2m_o  (uart_wb_s2m),

        // Interrupt
        .uart_irq_o     (uart_irq)
    );

    // =========================================================================
    // SERV SoC
    // =========================================================================

    serv_soc_top #(
        .TcmInitFile   (TcmInitFile),
        .NumExtSlaves  (1)
    ) u_soc (
        .clk_i          (sys_clk),
        .rst_ni         (sys_rst_n),

        // External slave ports (USB UART)
        .ext_wb_m2s_o   (uart_wb_m2s),
        .ext_wb_s2m_i   (uart_wb_s2m),

        // Simulation control
        .sim_halt_o       (sim_halt_o),
        .sim_char_valid_o (sim_char_valid_o),
        .sim_char_data_o  (sim_char_data_o)
    );

    // =========================================================================
    // Unused signal handling
    // =========================================================================

    logic unused;
    assign unused = &{user_sw[1], uart_irq};

endmodule
