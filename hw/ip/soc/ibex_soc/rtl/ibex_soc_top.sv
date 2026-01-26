// SPDX-License-Identifier: BSD-2-Clause
// Ibex SoC Top Level
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Complete SoC integrating:
// - Ibex RISC-V CPU with Wishbone interface
// - Wishbone pipelined crossbar
// - ITCM and DTCM memories
// - RISC-V timer
// - USB Etherbone master interface

module ibex_soc_top
    import ibex_soc_pkg::*;
#(
    parameter string ItcmInitFile = "",  // Hex file for ITCM initialization
    parameter string DtcmInitFile = ""   // Hex file for DTCM initialization
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // External Etherbone Wishbone master interface
    // (directly connects to USB Etherbone generated module)
    input  logic             eb_cyc_i,
    input  logic             eb_stb_i,
    input  logic             eb_we_i,
    input  logic [31:0]      eb_adr_i,
    input  logic [3:0]       eb_sel_i,
    input  logic [31:0]      eb_dat_i,
    output logic [31:0]      eb_dat_o,
    output logic             eb_ack_o,
    output logic             eb_err_o,
    output logic             eb_stall_o
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // CPU interfaces
    logic        cpu_ibus_cyc, cpu_ibus_stb, cpu_ibus_we;
    logic [31:0] cpu_ibus_adr, cpu_ibus_dat_w, cpu_ibus_dat_r;
    logic [3:0]  cpu_ibus_sel;
    logic        cpu_ibus_ack, cpu_ibus_err, cpu_ibus_stall;

    logic        cpu_dbus_cyc, cpu_dbus_stb, cpu_dbus_we;
    logic [31:0] cpu_dbus_adr, cpu_dbus_dat_w, cpu_dbus_dat_r;
    logic [3:0]  cpu_dbus_sel;
    logic        cpu_dbus_ack, cpu_dbus_err, cpu_dbus_stall;

    // Crossbar master signals (packed arrays)
    logic [NumMasters-1:0]        m_cyc, m_stb, m_we;
    logic [NumMasters-1:0][31:0]  m_adr, m_dat_w, m_dat_r;
    logic [NumMasters-1:0][3:0]   m_sel;
    logic [NumMasters-1:0]        m_ack, m_err, m_stall;

    // Crossbar slave signals (packed arrays)
    logic [NumSlaves-1:0]         s_cyc, s_stb, s_we;
    logic [NumSlaves-1:0][31:0]   s_adr, s_dat_w, s_dat_r;
    logic [NumSlaves-1:0][3:0]    s_sel;
    logic [NumSlaves-1:0]         s_ack, s_err, s_stall;

    // Interrupts
    logic timer_irq;

    // =========================================================================
    // Pack master signals into crossbar format
    // =========================================================================

    // Master 0: CPU I-bus
    assign m_cyc[MasterIbus]   = cpu_ibus_cyc;
    assign m_stb[MasterIbus]   = cpu_ibus_stb;
    assign m_we[MasterIbus]    = cpu_ibus_we;
    assign m_adr[MasterIbus]   = cpu_ibus_adr;
    assign m_sel[MasterIbus]   = cpu_ibus_sel;
    assign m_dat_w[MasterIbus] = cpu_ibus_dat_w;
    assign cpu_ibus_dat_r      = m_dat_r[MasterIbus];
    assign cpu_ibus_ack        = m_ack[MasterIbus];
    assign cpu_ibus_err        = m_err[MasterIbus];
    assign cpu_ibus_stall      = m_stall[MasterIbus];

    // Master 1: CPU D-bus
    assign m_cyc[MasterDbus]   = cpu_dbus_cyc;
    assign m_stb[MasterDbus]   = cpu_dbus_stb;
    assign m_we[MasterDbus]    = cpu_dbus_we;
    assign m_adr[MasterDbus]   = cpu_dbus_adr;
    assign m_sel[MasterDbus]   = cpu_dbus_sel;
    assign m_dat_w[MasterDbus] = cpu_dbus_dat_w;
    assign cpu_dbus_dat_r      = m_dat_r[MasterDbus];
    assign cpu_dbus_ack        = m_ack[MasterDbus];
    assign cpu_dbus_err        = m_err[MasterDbus];
    assign cpu_dbus_stall      = m_stall[MasterDbus];

    // Master 2: Etherbone
    assign m_cyc[MasterEb]     = eb_cyc_i;
    assign m_stb[MasterEb]     = eb_stb_i;
    assign m_we[MasterEb]      = eb_we_i;
    assign m_adr[MasterEb]     = eb_adr_i;
    assign m_sel[MasterEb]     = eb_sel_i;
    assign m_dat_w[MasterEb]   = eb_dat_i;
    assign eb_dat_o            = m_dat_r[MasterEb];
    assign eb_ack_o            = m_ack[MasterEb];
    assign eb_err_o            = m_err[MasterEb];
    assign eb_stall_o          = m_stall[MasterEb];

    // =========================================================================
    // Ibex CPU
    // =========================================================================

    ibex_wb_top #(
        .AW              (32),
        .DW              (32),
        .PMPEnable       (1'b0),
        .RV32E           (1'b0),
        .RV32B           (1'b0),
        .BootAddr        (BootAddr)
    ) u_cpu (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),

        .boot_addr_i     (BootAddr),

        // Instruction bus
        .ibus_cyc_o      (cpu_ibus_cyc),
        .ibus_stb_o      (cpu_ibus_stb),
        .ibus_we_o       (cpu_ibus_we),
        .ibus_adr_o      (cpu_ibus_adr),
        .ibus_sel_o      (cpu_ibus_sel),
        .ibus_dat_o      (cpu_ibus_dat_w),
        .ibus_dat_i      (cpu_ibus_dat_r),
        .ibus_ack_i      (cpu_ibus_ack),
        .ibus_err_i      (cpu_ibus_err),
        .ibus_stall_i    (cpu_ibus_stall),

        // Data bus
        .dbus_cyc_o      (cpu_dbus_cyc),
        .dbus_stb_o      (cpu_dbus_stb),
        .dbus_we_o       (cpu_dbus_we),
        .dbus_adr_o      (cpu_dbus_adr),
        .dbus_sel_o      (cpu_dbus_sel),
        .dbus_dat_o      (cpu_dbus_dat_w),
        .dbus_dat_i      (cpu_dbus_dat_r),
        .dbus_ack_i      (cpu_dbus_ack),
        .dbus_err_i      (cpu_dbus_err),
        .dbus_stall_i    (cpu_dbus_stall),

        // Interrupts
        .irq_software_i  (1'b0),
        .irq_timer_i     (timer_irq),
        .irq_external_i  (1'b0),
        .irq_fast_i      (15'b0),
        .irq_nm_i        (1'b0),

        // CPU control
        .fetch_enable_i  (1'b1),
        .core_sleep_o    ()
    );

    // =========================================================================
    // Wishbone Crossbar
    // =========================================================================

    wb_crossbar #(
        .NumMasters (NumMasters),
        .NumSlaves  (NumSlaves),
        .AddrWidth  (32),
        .DataWidth  (32),
        .AddrBase   (getSlaveAddrs()),
        .AddrMask   (getSlaveMasks())
    ) u_crossbar (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // Masters
        .m_cyc_i     (m_cyc),
        .m_stb_i     (m_stb),
        .m_we_i      (m_we),
        .m_adr_i     (m_adr),
        .m_sel_i     (m_sel),
        .m_dat_i     (m_dat_w),
        .m_dat_o     (m_dat_r),
        .m_ack_o     (m_ack),
        .m_err_o     (m_err),
        .m_stall_o   (m_stall),

        // Slaves
        .s_cyc_o     (s_cyc),
        .s_stb_o     (s_stb),
        .s_we_o      (s_we),
        .s_adr_o     (s_adr),
        .s_sel_o     (s_sel),
        .s_dat_o     (s_dat_w),
        .s_dat_i     (s_dat_r),
        .s_ack_i     (s_ack),
        .s_err_i     (s_err),
        .s_stall_i   (s_stall)
    );

    // =========================================================================
    // ITCM (Instruction Tightly Coupled Memory)
    // =========================================================================

    wb_tcm #(
        .Size     (ItcmSize),
        .AW       (32),
        .DW       (32),
        .InitFile (ItcmInitFile)
    ) u_itcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (s_cyc[SlaveItcm]),
        .wb_stb_i  (s_stb[SlaveItcm]),
        .wb_we_i   (s_we[SlaveItcm]),
        .wb_adr_i  (s_adr[SlaveItcm]),
        .wb_sel_i  (s_sel[SlaveItcm]),
        .wb_dat_i  (s_dat_w[SlaveItcm]),
        .wb_dat_o  (s_dat_r[SlaveItcm]),
        .wb_ack_o  (s_ack[SlaveItcm]),
        .wb_err_o  (s_err[SlaveItcm]),
        .wb_stall_o(s_stall[SlaveItcm])
    );

    // =========================================================================
    // DTCM (Data Tightly Coupled Memory)
    // =========================================================================

    wb_tcm #(
        .Size     (DtcmSize),
        .AW       (32),
        .DW       (32),
        .InitFile (DtcmInitFile)
    ) u_dtcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (s_cyc[SlaveDtcm]),
        .wb_stb_i  (s_stb[SlaveDtcm]),
        .wb_we_i   (s_we[SlaveDtcm]),
        .wb_adr_i  (s_adr[SlaveDtcm]),
        .wb_sel_i  (s_sel[SlaveDtcm]),
        .wb_dat_i  (s_dat_w[SlaveDtcm]),
        .wb_dat_o  (s_dat_r[SlaveDtcm]),
        .wb_ack_o  (s_ack[SlaveDtcm]),
        .wb_err_o  (s_err[SlaveDtcm]),
        .wb_stall_o(s_stall[SlaveDtcm])
    );

    // =========================================================================
    // Timer
    // =========================================================================

    wb_timer u_timer (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),

        .wb_cyc_i   (s_cyc[SlaveTimer]),
        .wb_stb_i   (s_stb[SlaveTimer]),
        .wb_we_i    (s_we[SlaveTimer]),
        .wb_adr_i   (s_adr[SlaveTimer]),
        .wb_sel_i   (s_sel[SlaveTimer]),
        .wb_dat_i   (s_dat_w[SlaveTimer]),
        .wb_dat_o   (s_dat_r[SlaveTimer]),
        .wb_ack_o   (s_ack[SlaveTimer]),
        .wb_err_o   (s_err[SlaveTimer]),
        .wb_stall_o (s_stall[SlaveTimer]),

        .timer_irq_o(timer_irq)
    );

endmodule
