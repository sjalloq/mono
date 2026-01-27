// SPDX-License-Identifier: BSD-2-Clause
// Squirrel Ibex SoC Top Level
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Board-level integration of Ibex SoC for Squirrel/CaptainDMA board.
// Handles clock generation, reset synchronization, and USB PHY interface.

module squirrel_ibex_top #(
    parameter string ItcmInitFile = "",  // Hex file for ITCM initialization
    parameter string DtcmInitFile = ""   // Hex file for DTCM initialization
) (
    // System clock input
    input  logic        clk100,

    // User LEDs
    output logic [1:0]  user_led,

    // User switches
    input  logic [1:0]  user_sw

    // FT601 USB 3.0 FIFO interface (commented out for initial synthesis)
    // input  logic        usb_fifo_clk,
    // inout  logic [31:0] usb_fifo_data,
    // inout  logic [3:0]  usb_fifo_be,
    // input  logic        usb_fifo_rxf_n,
    // input  logic        usb_fifo_txe_n,
    // output logic        usb_fifo_rd_n,
    // output logic        usb_fifo_wr_n,
    // output logic        usb_fifo_oe_n,
    // output logic        usb_fifo_siwu_n,
    // output logic        usb_fifo_rst_n
);

    // =========================================================================
    // Logic Declarations
    // =========================================================================

    logic clk100_buf;
    logic clk_sys;
    logic clk_125m;
    logic clk_250m;
    logic rst_n;
    logic rst_por;
    logic rst_req_n;
    logic [3:0] rst_sync;
    logic mmcm_locked;

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================

    BUFG u_clk100_buf (
        .I (clk100),
        .O (clk100_buf)
    );

    SRL16E #(
        .INIT(16'hFFFF)
    ) u_por_srl (
        .CLK(clk100_buf),
        .CE (1'b1),
        .D  (1'b0),      // Shift in 0s
        .A0 (1'b1),      // Address = 15 (tap at bit 15)
        .A1 (1'b1),
        .A2 (1'b1),
        .A3 (1'b1),
        .Q  (rst_por)
    );

    mmcm #(
      .CLK_IN_PERIOD_NS(10.0),   // 100 MHz
      .VCO_MULT        (10.0),   // VCO = 1000 MHz
      .CLKOUT0_DIV     (16.0),   // 62.5 MHz
      .CLKOUT1_DIV     (8),      // 125 MHz
      .CLKOUT2_DIV     (4),      // 250 MHz
      .CLKOUT3_EN      (1'b0)
    ) u_mmcm (
      .clk_i    (clk100_buf),
      .rst_i    (rst_por),
      .clkout0_o(clk_sys),
      .clkout1_o(clk_125m),
      .clkout2_o(clk_250m),
      .clkout3_o(),
      .locked_o (mmcm_locked)
    );

    assign rst_req_n = mmcm_locked;

    // System domain reset synchronizer
    always_ff @(posedge clk_sys or negedge rst_req_n) begin
        if (!rst_req_n)
            rst_sync <= '0;
        else
            rst_sync <= {rst_sync[2:0], 1'b1};
    end

    assign rst_n = rst_sync[3];


    // =========================================================================
    // LED Heartbeat (simple counter to show FPGA is alive)
    // =========================================================================

    // Counter for LED blinking (~1Hz at 100MHz: 2^26 = 67M cycles)
    logic [26:0] led_counter;

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
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
    // Etherbone Wishbone interface (directly tied off for now)
    // =========================================================================

    logic        eb_cyc, eb_stb, eb_we;
    logic [31:0] eb_adr, eb_dat_w;
    logic [3:0]  eb_sel;

    logic [31:0] eb_dat_r;
    logic        eb_ack, eb_err, eb_stall;

    // Placeholder: Tie off Etherbone until USB bridge is implemented
    assign eb_cyc   = '0;
    assign eb_stb   = '0;
    assign eb_we    = '0;
    assign eb_adr   = '0;
    assign eb_sel   = '0;
    assign eb_dat_w = '0;

    // =========================================================================
    // Ibex SoC
    // =========================================================================

    (* DONT_TOUCH = "yes" *)
    ibex_soc_top #(
        .ItcmInitFile (ItcmInitFile),
        .DtcmInitFile (DtcmInitFile)
    ) u_soc (
        .clk_i          (clk_sys),
        .rst_ni         (rst_n),

        // Etherbone Wishbone master
        .eb_cyc_i       (eb_cyc),
        .eb_stb_i       (eb_stb),
        .eb_we_i        (eb_we),
        .eb_adr_i       (eb_adr),
        .eb_sel_i       (eb_sel),
        .eb_dat_i       (eb_dat_w),
        .eb_dat_o       (eb_dat_r),
        .eb_ack_o       (eb_ack),
        .eb_err_o       (eb_err),
        .eb_stall_o     (eb_stall)
    );

    // =========================================================================
    // FT601 USB Interface (commented out for initial synthesis)
    // =========================================================================
    // TODO: Re-enable when USB bridge path to ibex_soc is implemented
    //
    // // USB domain reset synchronizer
    // logic usb_rst_n;
    // logic [3:0] usb_rst_sync;
    // always_ff @(posedge usb_fifo_clk) begin
    //     usb_rst_sync <= {usb_rst_sync[2:0], 1'b1};
    // end
    // assign usb_rst_n = usb_rst_sync[3];
    //
    // // USB FIFO Tristate Handling
    // logic [31:0] usb_data_i, usb_data_o;
    // logic [3:0]  usb_be_o;
    // logic        usb_data_oe;
    // logic        usb_be_oe;
    //
    // // Data bus tristate
    // generate
    //     for (genvar i = 0; i < 32; i++) begin : gen_data_tristate
    //         IOBUF u_iobuf_data (
    //             .I  (usb_data_o[i]),
    //             .O  (usb_data_i[i]),
    //             .T  (~usb_data_oe),
    //             .IO (usb_fifo_data[i])
    //         );
    //     end
    // endgenerate
    //
    // // Byte enable tristate
    // logic [3:0] usb_be_i_unused;
    // generate
    //     for (genvar i = 0; i < 4; i++) begin : gen_be_tristate
    //         IOBUF u_iobuf_be (
    //             .I  (usb_be_o[i]),
    //             .O  (usb_be_i_unused[i]),
    //             .T  (~usb_be_oe),
    //             .IO (usb_fifo_be[i])
    //         );
    //     end
    // endgenerate
    //
    // // FT601 stream interface (USB clock domain)
    // logic [31:0] ft601_rx_data;
    // logic        ft601_rx_valid;
    // logic [31:0] ft601_tx_data;
    // logic        ft601_tx_valid;
    // logic        ft601_tx_ready;
    //
    // ft601_sync #(
    //     .DW (32)
    // ) u_ft601 (
    //     .clk_i      (usb_fifo_clk),
    //     .rst_ni     (usb_rst_n),
    //
    //     // FT601 control signals
    //     .rxf_ni     (usb_fifo_rxf_n),
    //     .txe_ni     (usb_fifo_txe_n),
    //     .rd_no      (usb_fifo_rd_n),
    //     .wr_no      (usb_fifo_wr_n),
    //     .oe_no      (usb_fifo_oe_n),
    //     .siwu_no    (usb_fifo_siwu_n),
    //     .rst_no     (usb_fifo_rst_n),
    //
    //     // Data bus (directly to tristate IOBUFs)
    //     .data_i     (usb_data_i),
    //     .data_o     (usb_data_o),
    //     .data_oe    (usb_data_oe),
    //     .be_o       (usb_be_o),
    //     .be_oe      (usb_be_oe),
    //
    //     // RX stream (data from USB host)
    //     .rx_data_o  (ft601_rx_data),
    //     .rx_valid_o (ft601_rx_valid),
    //
    //     // TX stream (data to USB host)
    //     .tx_data_i  (ft601_tx_data),
    //     .tx_valid_i (ft601_tx_valid),
    //     .tx_ready_o (ft601_tx_ready)
    // );
    //
    // // Placeholder: Tie off FT601 TX until Etherbone is connected
    // assign ft601_tx_data  = '0;
    // assign ft601_tx_valid = '0;

endmodule
