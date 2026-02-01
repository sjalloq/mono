// SPDX-License-Identifier: BSD-2-Clause
// Squirrel SERV SoC Top Level
//
// Copyright (c) 2026 Shareef Jalloq
//
// Board-level integration of SERV AON SoC for Squirrel/CaptainDMA board.
// Handles clock generation, reset synchronization, and USB PHY tristate I/O.
// All functional logic is in core.sv.

module squirrel_serv_top #(
    parameter string TcmInitFile = ""   // Hex file for TCM initialization
) (
    // System clock input
    input  logic        clk100,

    // User LEDs
    output logic [1:0]  user_led,

    // User switches
    input  logic [1:0]  user_sw,

    // FT601 USB 3.0 FIFO interface
    input  logic        usb_fifo_clk,
    inout  logic [31:0] usb_fifo_data,
    inout  logic [3:0]  usb_fifo_be,
    input  logic        usb_fifo_rxf_n,
    input  logic        usb_fifo_txe_n,
    output logic        usb_fifo_rd_n,
    output logic        usb_fifo_wr_n,
    output logic        usb_fifo_oe_n,
    output logic        usb_fifo_siwu_n,
    output logic        usb_fifo_rst_n
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
    // FT601 USB Tristate I/O (Xilinx IOBUF primitives)
    // =========================================================================

    logic [31:0] usb_data_i, usb_data_o;
    logic        usb_data_oe;
    logic [3:0]  usb_be_o;
    logic        usb_be_oe;

    // Data bus tristate
    for (genvar i = 0; i < 32; i++) begin : gen_data_iobuf
        IOBUF u_iobuf_data (
            .I  (usb_data_o[i]),
            .O  (usb_data_i[i]),
            .T  (~usb_data_oe),
            .IO (usb_fifo_data[i])
        );
    end

    // Byte enable tristate
    logic [3:0] usb_be_i_unused;
    for (genvar i = 0; i < 4; i++) begin : gen_be_iobuf
        IOBUF u_iobuf_be (
            .I  (usb_be_o[i]),
            .O  (usb_be_i_unused[i]),
            .T  (~usb_be_oe),
            .IO (usb_fifo_be[i])
        );
    end

    // =========================================================================
    // Core (all functional logic)
    // =========================================================================

    core #(
        .TcmInitFile (TcmInitFile)
    ) u_core (
        .sys_clk      (clk_sys),
        .sys_rst_n    (rst_n),

        .user_led     (user_led),
        .user_sw      (user_sw),

        // FT601 split signals (from/to IOBUFs)
        .usb_clk_i    (usb_fifo_clk),
        .usb_data_i   (usb_data_i),
        .usb_data_o   (usb_data_o),
        .usb_data_oe  (usb_data_oe),
        .usb_be_o     (usb_be_o),
        .usb_be_oe    (usb_be_oe),
        .usb_rxf_ni   (usb_fifo_rxf_n),
        .usb_txe_ni   (usb_fifo_txe_n),
        .usb_rd_no    (usb_fifo_rd_n),
        .usb_wr_no    (usb_fifo_wr_n),
        .usb_oe_no    (usb_fifo_oe_n),
        .usb_siwu_no  (usb_fifo_siwu_n),
        .usb_rst_no   (usb_fifo_rst_n),

        // Simulation control (unused in synthesis)
        .sim_halt_o       (),
        .sim_char_valid_o (),
        .sim_char_data_o  ()
    );

    // =========================================================================
    // Unused signal handling
    // =========================================================================

    logic unused;
    assign unused = &{clk_125m, clk_250m, usb_be_i_unused};

endmodule
