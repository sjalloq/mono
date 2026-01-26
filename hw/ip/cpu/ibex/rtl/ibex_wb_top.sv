// SPDX-License-Identifier: BSD-2-Clause
// Ibex RISC-V Core with Wishbone Interface
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Wraps lowRISC's Ibex core with OBI-to-Wishbone bridges,
// providing Wishbone pipelined interfaces for instruction and data buses.
//
// Debug is stubbed out. See docs/plans/ibex_debug_options.md for
// future debug implementation options.

module ibex_wb_top #(
    parameter int unsigned AW = 32,
    parameter int unsigned DW = 32,

    // Ibex configuration
    parameter bit          PMPEnable        = 1'b0,
    parameter int unsigned PMPGranularity   = 0,
    parameter int unsigned PMPNumRegions    = 4,
    parameter int unsigned MHPMCounterNum   = 0,
    parameter int unsigned MHPMCounterWidth = 40,
    parameter bit          RV32E            = 1'b0,
    parameter bit          RV32B            = 1'b0,
    parameter bit          BranchTargetALU  = 1'b0,
    parameter bit          WritebackStage   = 1'b0,
    parameter bit          ICache           = 1'b0,
    parameter bit          ICacheECC        = 1'b0,
    parameter bit          SecureIbex       = 1'b0,

    // Boot address
    parameter logic [31:0] BootAddr         = 32'h0001_0000
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Boot address (can override parameter)
    input  logic [31:0]      boot_addr_i,

    // Instruction Wishbone master
    output logic             ibus_cyc_o,
    output logic             ibus_stb_o,
    output logic             ibus_we_o,
    output logic [AW-1:0]    ibus_adr_o,
    output logic [DW/8-1:0]  ibus_sel_o,
    output logic [DW-1:0]    ibus_dat_o,
    input  logic [DW-1:0]    ibus_dat_i,
    input  logic             ibus_ack_i,
    input  logic             ibus_err_i,
    input  logic             ibus_stall_i,

    // Data Wishbone master
    output logic             dbus_cyc_o,
    output logic             dbus_stb_o,
    output logic             dbus_we_o,
    output logic [AW-1:0]    dbus_adr_o,
    output logic [DW/8-1:0]  dbus_sel_o,
    output logic [DW-1:0]    dbus_dat_o,
    input  logic [DW-1:0]    dbus_dat_i,
    input  logic             dbus_ack_i,
    input  logic             dbus_err_i,
    input  logic             dbus_stall_i,

    // Interrupt inputs
    input  logic             irq_software_i,
    input  logic             irq_timer_i,
    input  logic             irq_external_i,
    input  logic [14:0]      irq_fast_i,
    input  logic             irq_nm_i,

    // CPU control
    input  logic             fetch_enable_i,
    output logic             core_sleep_o
);

    // Internal OBI signals for instruction bus
    logic        instr_req;
    logic        instr_gnt;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic        instr_rvalid;
    logic        instr_err;

    // Internal OBI signals for data bus
    logic        data_req;
    logic        data_gnt;
    logic        data_we;
    logic [3:0]  data_be;
    logic [31:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;
    logic        data_rvalid;
    logic        data_err;

    // Ibex core instance
    ibex_top #(
        .PMPEnable        (PMPEnable),
        .PMPGranularity   (PMPGranularity),
        .PMPNumRegions    (PMPNumRegions),
        .MHPMCounterNum   (MHPMCounterNum),
        .MHPMCounterWidth (MHPMCounterWidth),
        .RV32E            (RV32E),
        .RV32M            (ibex_pkg::RV32MSingleCycle),
        .RV32B            (RV32B ? ibex_pkg::RV32BBalanced : ibex_pkg::RV32BNone),
        .RegFile          (ibex_pkg::RegFileFPGA),
        .BranchTargetALU  (BranchTargetALU),
        .WritebackStage   (WritebackStage),
        .ICache           (ICache),
        .ICacheECC        (ICacheECC),
        .DbgTriggerEn     (1'b0),       // Debug disabled
        .DbgHwBreakNum    (0),
        .SecureIbex       (SecureIbex),
        .DmHaltAddr       (BootAddr),
        .DmExceptionAddr  (BootAddr + 4)
    ) u_ibex_core (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),

        .test_en_i       (1'b0),
        .scan_rst_ni     (1'b1),

        // RAM config (for ICache - tie off when ICache disabled)
        .ram_cfg_icache_tag_i   ('0),
        .ram_cfg_rsp_icache_tag_o (),
        .ram_cfg_icache_data_i  ('0),
        .ram_cfg_rsp_icache_data_o (),

        .hart_id_i       (32'h0),
        .boot_addr_i     (boot_addr_i),

        // Instruction fetch interface (OBI)
        .instr_req_o     (instr_req),
        .instr_gnt_i     (instr_gnt),
        .instr_rvalid_i  (instr_rvalid),
        .instr_addr_o    (instr_addr),
        .instr_rdata_i   (instr_rdata),
        .instr_rdata_intg_i (7'h0),
        .instr_err_i     (instr_err),

        // Data interface (OBI)
        .data_req_o      (data_req),
        .data_gnt_i      (data_gnt),
        .data_rvalid_i   (data_rvalid),
        .data_we_o       (data_we),
        .data_be_o       (data_be),
        .data_addr_o     (data_addr),
        .data_wdata_o    (data_wdata),
        .data_wdata_intg_o (),
        .data_rdata_i    (data_rdata),
        .data_rdata_intg_i (7'h0),
        .data_err_i      (data_err),

        // Interrupts
        .irq_software_i  (irq_software_i),
        .irq_timer_i     (irq_timer_i),
        .irq_external_i  (irq_external_i),
        .irq_fast_i      (irq_fast_i),
        .irq_nm_i        (irq_nm_i),

        // Scrambling - disabled (tie off)
        .scramble_key_valid_i (1'b0),
        .scramble_key_i       ('0),
        .scramble_nonce_i     ('0),
        .scramble_req_o       (),

        // Debug - stubbed out
        .debug_req_i     (1'b0),
        .crash_dump_o    (),

        // Double fault
        .double_fault_seen_o (),

        // CPU control
        .fetch_enable_i  (fetch_enable_i ? ibex_pkg::IbexMuBiOn : ibex_pkg::IbexMuBiOff),
        .alert_minor_o   (),
        .alert_major_internal_o (),
        .alert_major_bus_o (),
        .core_sleep_o    (core_sleep_o)
    );

    // Instruction bus OBI to Wishbone bridge
    ibex_obi2wb #(
        .AW (AW),
        .DW (DW)
    ) u_ibus_bridge (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // OBI (from Ibex)
        .obi_req_i   (instr_req),
        .obi_gnt_o   (instr_gnt),
        .obi_addr_i  (instr_addr),
        .obi_we_i    (1'b0),
        .obi_be_i    (4'hF),
        .obi_wdata_i (32'h0),
        .obi_rdata_o (instr_rdata),
        .obi_rvalid_o(instr_rvalid),
        .obi_err_o   (instr_err),

        // Wishbone
        .wb_cyc_o    (ibus_cyc_o),
        .wb_stb_o    (ibus_stb_o),
        .wb_we_o     (ibus_we_o),
        .wb_adr_o    (ibus_adr_o),
        .wb_sel_o    (ibus_sel_o),
        .wb_dat_o    (ibus_dat_o),
        .wb_dat_i    (ibus_dat_i),
        .wb_ack_i    (ibus_ack_i),
        .wb_err_i    (ibus_err_i),
        .wb_stall_i  (ibus_stall_i)
    );

    // Data bus OBI to Wishbone bridge
    ibex_obi2wb #(
        .AW (AW),
        .DW (DW)
    ) u_dbus_bridge (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),

        // OBI (from Ibex)
        .obi_req_i   (data_req),
        .obi_gnt_o   (data_gnt),
        .obi_addr_i  (data_addr),
        .obi_we_i    (data_we),
        .obi_be_i    (data_be),
        .obi_wdata_i (data_wdata),
        .obi_rdata_o (data_rdata),
        .obi_rvalid_o(data_rvalid),
        .obi_err_o   (data_err),

        // Wishbone
        .wb_cyc_o    (dbus_cyc_o),
        .wb_stb_o    (dbus_stb_o),
        .wb_we_o     (dbus_we_o),
        .wb_adr_o    (dbus_adr_o),
        .wb_sel_o    (dbus_sel_o),
        .wb_dat_o    (dbus_dat_o),
        .wb_dat_i    (dbus_dat_i),
        .wb_ack_i    (dbus_ack_i),
        .wb_err_i    (dbus_err_i),
        .wb_stall_i  (dbus_stall_i)
    );

endmodule
