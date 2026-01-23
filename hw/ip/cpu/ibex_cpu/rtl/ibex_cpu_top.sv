// SPDX-License-Identifier: BSD-2-Clause
// Ibex CPU with Tightly Coupled Instruction Memory
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// This module provides:
// - Ibex RISC-V CPU with Wishbone interfaces
// - ITCM directly connected to I-bus (deterministic fetch, no arbitration)
// - D-bus exposed as Wishbone master for external interconnect
//
// The ITCM provides single-cycle instruction fetch with no bus contention,
// while the D-bus can be connected to external arbitration for shared
// access to data memory and peripherals.

module ibex_cpu_top
    import ibex_cpu_pkg::*;
#(
    parameter int unsigned ItcmSizeBytes   = 16384,  // 16KB default
    parameter string       ItcmInitFile    = "",

    // Ibex configuration passthrough
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
    parameter bit          SecureIbex       = 1'b0
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Boot address override
    input  logic [31:0] boot_addr_i,

    // Data bus Wishbone master (directly exposed for external interconnect)
    output logic        dbus_cyc_o,
    output logic        dbus_stb_o,
    output logic        dbus_we_o,
    output logic [31:0] dbus_adr_o,
    output logic [3:0]  dbus_sel_o,
    output logic [31:0] dbus_dat_o,
    input  logic [31:0] dbus_dat_i,
    input  logic        dbus_ack_i,
    input  logic        dbus_err_i,
    input  logic        dbus_stall_i,

    // Interrupts
    input  logic        irq_software_i,
    input  logic        irq_timer_i,
    input  logic        irq_external_i,
    input  logic [14:0] irq_fast_i,
    input  logic        irq_nm_i,

    // CPU control
    input  logic        fetch_enable_i,
    output logic        core_sleep_o
);

    // =========================================================================
    // Internal I-bus signals (directly connected to ITCM)
    // =========================================================================

    logic        ibus_cyc, ibus_stb, ibus_we;
    logic [31:0] ibus_adr, ibus_dat_w, ibus_dat_r;
    logic [3:0]  ibus_sel;
    logic        ibus_ack, ibus_err, ibus_stall;

    // =========================================================================
    // Ibex CPU with Wishbone interfaces
    // =========================================================================

    ibex_wb_top #(
        .AW              (32),
        .DW              (32),
        .PMPEnable       (PMPEnable),
        .PMPGranularity  (PMPGranularity),
        .PMPNumRegions   (PMPNumRegions),
        .MHPMCounterNum  (MHPMCounterNum),
        .MHPMCounterWidth(MHPMCounterWidth),
        .RV32E           (RV32E),
        .RV32B           (RV32B),
        .BranchTargetALU (BranchTargetALU),
        .WritebackStage  (WritebackStage),
        .ICache          (ICache),
        .ICacheECC       (ICacheECC),
        .SecureIbex      (SecureIbex),
        .BootAddr        (BOOT_ADDR)
    ) u_cpu (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .boot_addr_i     (boot_addr_i),

        // Instruction bus -> internal ITCM (tightly coupled)
        .ibus_cyc_o      (ibus_cyc),
        .ibus_stb_o      (ibus_stb),
        .ibus_we_o       (ibus_we),
        .ibus_adr_o      (ibus_adr),
        .ibus_sel_o      (ibus_sel),
        .ibus_dat_o      (ibus_dat_w),
        .ibus_dat_i      (ibus_dat_r),
        .ibus_ack_i      (ibus_ack),
        .ibus_err_i      (ibus_err),
        .ibus_stall_i    (ibus_stall),

        // Data bus -> external port (for shared bus)
        .dbus_cyc_o      (dbus_cyc_o),
        .dbus_stb_o      (dbus_stb_o),
        .dbus_we_o       (dbus_we_o),
        .dbus_adr_o      (dbus_adr_o),
        .dbus_sel_o      (dbus_sel_o),
        .dbus_dat_o      (dbus_dat_o),
        .dbus_dat_i      (dbus_dat_i),
        .dbus_ack_i      (dbus_ack_i),
        .dbus_err_i      (dbus_err_i),
        .dbus_stall_i    (dbus_stall_i),

        // Interrupts
        .irq_software_i  (irq_software_i),
        .irq_timer_i     (irq_timer_i),
        .irq_external_i  (irq_external_i),
        .irq_fast_i      (irq_fast_i),
        .irq_nm_i        (irq_nm_i),

        // CPU control
        .fetch_enable_i  (fetch_enable_i),
        .core_sleep_o    (core_sleep_o)
    );

    // =========================================================================
    // ITCM - Tightly Coupled Instruction Memory
    // =========================================================================
    //
    // Directly connected to I-bus with no arbitration.
    // Provides single-cycle instruction fetch for deterministic performance.

    wb_tcm #(
        .SIZE      (ItcmSizeBytes),
        .AW        (32),
        .DW        (32),
        .INIT_FILE (ItcmInitFile)
    ) u_itcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),

        .wb_cyc_i  (ibus_cyc),
        .wb_stb_i  (ibus_stb),
        .wb_we_i   (ibus_we),
        .wb_adr_i  (ibus_adr),
        .wb_sel_i  (ibus_sel),
        .wb_dat_i  (ibus_dat_w),
        .wb_dat_o  (ibus_dat_r),
        .wb_ack_o  (ibus_ack),
        .wb_err_o  (ibus_err),
        .wb_stall_o(ibus_stall)
    );

endmodule
