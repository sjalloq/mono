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
// - Control/Status registers
// - Mailbox for host communication
// - USB Etherbone master interface

module ibex_soc_top
    import ibex_soc_pkg::*;
(
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
    output logic             eb_stall_o,

    // GPIO
    output logic [1:0]       led_o,
    input  logic [1:0]       sw_i
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
    logic [NUM_MASTERS-1:0]        m_cyc, m_stb, m_we;
    logic [NUM_MASTERS-1:0][31:0]  m_adr, m_dat_w, m_dat_r;
    logic [NUM_MASTERS-1:0][3:0]   m_sel;
    logic [NUM_MASTERS-1:0]        m_ack, m_err, m_stall;

    // Crossbar slave signals (packed arrays)
    logic [NUM_SLAVES-1:0]         s_cyc, s_stb, s_we;
    logic [NUM_SLAVES-1:0][31:0]   s_adr, s_dat_w, s_dat_r;
    logic [NUM_SLAVES-1:0][3:0]    s_sel;
    logic [NUM_SLAVES-1:0]         s_ack, s_err, s_stall;

    // Interrupts
    logic timer_irq;
    logic mailbox_h2c_irq, mailbox_c2h_irq;
    logic csr_irq;
    logic cpu_rst;

    // =========================================================================
    // Pack master signals into crossbar format
    // =========================================================================

    // Master 0: CPU I-bus
    assign m_cyc[MASTER_IBUS]   = cpu_ibus_cyc;
    assign m_stb[MASTER_IBUS]   = cpu_ibus_stb;
    assign m_we[MASTER_IBUS]    = cpu_ibus_we;
    assign m_adr[MASTER_IBUS]   = cpu_ibus_adr;
    assign m_sel[MASTER_IBUS]   = cpu_ibus_sel;
    assign m_dat_w[MASTER_IBUS] = cpu_ibus_dat_w;
    assign cpu_ibus_dat_r       = m_dat_r[MASTER_IBUS];
    assign cpu_ibus_ack         = m_ack[MASTER_IBUS];
    assign cpu_ibus_err         = m_err[MASTER_IBUS];
    assign cpu_ibus_stall       = m_stall[MASTER_IBUS];

    // Master 1: CPU D-bus
    assign m_cyc[MASTER_DBUS]   = cpu_dbus_cyc;
    assign m_stb[MASTER_DBUS]   = cpu_dbus_stb;
    assign m_we[MASTER_DBUS]    = cpu_dbus_we;
    assign m_adr[MASTER_DBUS]   = cpu_dbus_adr;
    assign m_sel[MASTER_DBUS]   = cpu_dbus_sel;
    assign m_dat_w[MASTER_DBUS] = cpu_dbus_dat_w;
    assign cpu_dbus_dat_r       = m_dat_r[MASTER_DBUS];
    assign cpu_dbus_ack         = m_ack[MASTER_DBUS];
    assign cpu_dbus_err         = m_err[MASTER_DBUS];
    assign cpu_dbus_stall       = m_stall[MASTER_DBUS];

    // Master 2: Etherbone
    assign m_cyc[MASTER_EB]     = eb_cyc_i;
    assign m_stb[MASTER_EB]     = eb_stb_i;
    assign m_we[MASTER_EB]      = eb_we_i;
    assign m_adr[MASTER_EB]     = eb_adr_i;
    assign m_sel[MASTER_EB]     = eb_sel_i;
    assign m_dat_w[MASTER_EB]   = eb_dat_i;
    assign eb_dat_o             = m_dat_r[MASTER_EB];
    assign eb_ack_o             = m_ack[MASTER_EB];
    assign eb_err_o             = m_err[MASTER_EB];
    assign eb_stall_o           = m_stall[MASTER_EB];

    // =========================================================================
    // Ibex CPU
    // =========================================================================

    ibex_wb_top #(
        .AW              (32),
        .DW              (32),
        .PMPEnable       (1'b0),
        .RV32E           (1'b0),
        .RV32B           (1'b0),
        .BootAddr        (BOOT_ADDR)
    ) u_cpu (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni && !cpu_rst),

        .boot_addr_i     (BOOT_ADDR),

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
        .irq_external_i  (csr_irq),
        .irq_fast_i      ({13'b0, mailbox_c2h_irq, mailbox_h2c_irq}),
        .irq_nm_i        (1'b0),

        // CPU control
        .fetch_enable_i  (1'b1),
        .core_sleep_o    ()
    );

    // =========================================================================
    // Wishbone Crossbar
    // =========================================================================

    wb_crossbar #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .AW          (32),
        .DW          (32),
        .SLAVE_BASE  (get_slave_bases()),
        .SLAVE_MASK  (get_slave_masks())
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
        .SIZE      (ITCM_SIZE),
        .AW        (32),
        .DW        (32),
        .INIT_FILE ("")
    ) u_itcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (s_cyc[SLAVE_ITCM]),
        .wb_stb_i  (s_stb[SLAVE_ITCM]),
        .wb_we_i   (s_we[SLAVE_ITCM]),
        .wb_adr_i  (s_adr[SLAVE_ITCM]),
        .wb_sel_i  (s_sel[SLAVE_ITCM]),
        .wb_dat_i  (s_dat_w[SLAVE_ITCM]),
        .wb_dat_o  (s_dat_r[SLAVE_ITCM]),
        .wb_ack_o  (s_ack[SLAVE_ITCM]),
        .wb_err_o  (s_err[SLAVE_ITCM]),
        .wb_stall_o(s_stall[SLAVE_ITCM])
    );

    // =========================================================================
    // DTCM (Data Tightly Coupled Memory)
    // =========================================================================

    wb_tcm #(
        .SIZE      (DTCM_SIZE),
        .AW        (32),
        .DW        (32),
        .INIT_FILE ("")
    ) u_dtcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (s_cyc[SLAVE_DTCM]),
        .wb_stb_i  (s_stb[SLAVE_DTCM]),
        .wb_we_i   (s_we[SLAVE_DTCM]),
        .wb_adr_i  (s_adr[SLAVE_DTCM]),
        .wb_sel_i  (s_sel[SLAVE_DTCM]),
        .wb_dat_i  (s_dat_w[SLAVE_DTCM]),
        .wb_dat_o  (s_dat_r[SLAVE_DTCM]),
        .wb_ack_o  (s_ack[SLAVE_DTCM]),
        .wb_err_o  (s_err[SLAVE_DTCM]),
        .wb_stall_o(s_stall[SLAVE_DTCM])
    );

    // =========================================================================
    // CSR Block
    // =========================================================================

    ibex_soc_csr u_csr (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (s_cyc[SLAVE_CSR]),
        .wb_stb_i  (s_stb[SLAVE_CSR]),
        .wb_we_i   (s_we[SLAVE_CSR]),
        .wb_adr_i  (s_adr[SLAVE_CSR]),
        .wb_sel_i  (s_sel[SLAVE_CSR]),
        .wb_dat_i  (s_dat_w[SLAVE_CSR]),
        .wb_dat_o  (s_dat_r[SLAVE_CSR]),
        .wb_ack_o  (s_ack[SLAVE_CSR]),
        .wb_err_o  (s_err[SLAVE_CSR]),
        .wb_stall_o(s_stall[SLAVE_CSR]),

        .led_o     (led_o),
        .sw_i      (sw_i),
        .cpu_rst_o (cpu_rst),
        .irq_src_i ({14'b0, mailbox_c2h_irq, mailbox_h2c_irq}),
        .irq_o     (csr_irq)
    );

    // =========================================================================
    // Timer
    // =========================================================================

    wb_timer u_timer (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),

        .wb_cyc_i   (s_cyc[SLAVE_TIMER]),
        .wb_stb_i   (s_stb[SLAVE_TIMER]),
        .wb_we_i    (s_we[SLAVE_TIMER]),
        .wb_adr_i   (s_adr[SLAVE_TIMER]),
        .wb_sel_i   (s_sel[SLAVE_TIMER]),
        .wb_dat_i   (s_dat_w[SLAVE_TIMER]),
        .wb_dat_o   (s_dat_r[SLAVE_TIMER]),
        .wb_ack_o   (s_ack[SLAVE_TIMER]),
        .wb_err_o   (s_err[SLAVE_TIMER]),
        .wb_stall_o (s_stall[SLAVE_TIMER]),

        .timer_irq_o(timer_irq)
    );

    // =========================================================================
    // Mailbox
    // =========================================================================

    ibex_soc_mailbox u_mailbox (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),

        .wb_cyc_i          (s_cyc[SLAVE_MAILBOX]),
        .wb_stb_i          (s_stb[SLAVE_MAILBOX]),
        .wb_we_i           (s_we[SLAVE_MAILBOX]),
        .wb_adr_i          (s_adr[SLAVE_MAILBOX]),
        .wb_sel_i          (s_sel[SLAVE_MAILBOX]),
        .wb_dat_i          (s_dat_w[SLAVE_MAILBOX]),
        .wb_dat_o          (s_dat_r[SLAVE_MAILBOX]),
        .wb_ack_o          (s_ack[SLAVE_MAILBOX]),
        .wb_err_o          (s_err[SLAVE_MAILBOX]),
        .wb_stall_o        (s_stall[SLAVE_MAILBOX]),

        .irq_host_to_cpu_o (mailbox_h2c_irq),
        .irq_cpu_to_host_o (mailbox_c2h_irq)
    );

endmodule
