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
// - Simulation control peripheral
// - USB Etherbone master interface
// - Parameterized external Wishbone slave ports

module ibex_soc_top
    import ibex_soc_pkg::*;
    import ibex_pkg::crash_dump_t;
    import wb_pkg::*;
#(
    parameter string ItcmInitFile = "",  // Hex file for ITCM initialization
    parameter string DtcmInitFile = "",  // Hex file for DTCM initialization
    parameter int unsigned NumExtSlaves = 0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // External Etherbone Wishbone master interface
    input  wb_m2s_t          eb_wb_m2s_i,
    output wb_s2m_t          eb_wb_s2m_o,

    // External Wishbone slave ports
    output wb_m2s_t [NumExtSlaves > 0 ? NumExtSlaves-1 : 0:0] ext_wb_m2s_o,
    input  wb_s2m_t [NumExtSlaves > 0 ? NumExtSlaves-1 : 0:0] ext_wb_s2m_i,

    // Simulation control outputs (directly accessible by testbench)
    output logic             sim_halt_o,
    output logic             sim_char_valid_o,
    output logic [7:0]       sim_char_data_o,

    // CPU status / error outputs
    output logic             alert_minor_o,
    output logic             alert_major_internal_o,
    output logic             alert_major_bus_o,
    output logic             double_fault_seen_o,
    output crash_dump_t      crash_dump_o
);

    // =========================================================================
    // Address map: concatenate internal + external slave address maps
    // =========================================================================

    localparam int unsigned NumSlaves = NumIntSlaves + NumExtSlaves;

    logic [NumSlaves-1:0][AddrWidth-1:0] cfg_addr_base;
    logic [NumSlaves-1:0][AddrWidth-1:0] cfg_addr_mask;

    assign cfg_addr_base[SlaveItcm] = ItcmBase;
    assign cfg_addr_mask[SlaveItcm] = ItcmMask;
    assign cfg_addr_base[SlaveDtcm] = DtcmBase;
    assign cfg_addr_mask[SlaveDtcm] = DtcmMask;

    for (genvar i = 0; i < NumIntPeriphs + NumExtSlaves; i++) begin : gen_periph_addr
        assign cfg_addr_base[NumMemSlaves + i] = PeriphBase + i * 32'h1000;
        assign cfg_addr_mask[NumMemSlaves + i] = PeriphMask;
    end

    // =========================================================================
    // Internal signals
    // =========================================================================

    // Crossbar struct arrays
    wb_m2s_t [NumMasters-1:0] m2s;
    wb_s2m_t [NumMasters-1:0] s2m;
    wb_m2s_t [NumSlaves-1:0]  s_m2s;
    wb_s2m_t [NumSlaves-1:0]  s_s2m;

    // Interrupts
    logic timer_irq;

    // =========================================================================
    // Master port wiring
    // =========================================================================

    // Master 2: Etherbone
    assign m2s[MasterEb] = eb_wb_m2s_i;
    assign eb_wb_s2m_o   = s2m[MasterEb];

    // =========================================================================
    // External slave port wiring
    // =========================================================================

    for (genvar i = 0; i < NumExtSlaves; i++) begin : gen_ext_slaves
        assign ext_wb_m2s_o[i] = s_m2s[NumIntSlaves + i];
        assign s_s2m[NumIntSlaves + i] = ext_wb_s2m_i[i];
    end

    // When NumExtSlaves == 0, tie off the unused external ports
    if (NumExtSlaves == 0) begin : gen_no_ext_slaves
        assign ext_wb_m2s_o[0] = '0;
    end

    // =========================================================================
    // Ibex CPU
    // =========================================================================

    ibex_wb_top #(
        .PMPEnable       (1'b0),
        .RV32E           (1'b0),
        .RV32B           (1'b0),
        .BootAddr        (BootAddr)
    ) u_cpu (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),

        .boot_addr_i     (BootAddr),

        // Instruction bus
        .ibus_m2s_o      (m2s[MasterIbus]),
        .ibus_s2m_i      (s2m[MasterIbus]),

        // Data bus
        .dbus_m2s_o      (m2s[MasterDbus]),
        .dbus_s2m_i      (s2m[MasterDbus]),

        // Interrupts
        .irq_software_i  (1'b0),
        .irq_timer_i     (timer_irq),
        .irq_external_i  (1'b0),
        .irq_fast_i      (15'b0),
        .irq_nm_i        (1'b0),

        // CPU control
        .fetch_enable_i  (1'b1),
        .core_sleep_o    (),

        // CPU status / error
        .alert_minor_o          (alert_minor_o),
        .alert_major_internal_o (alert_major_internal_o),
        .alert_major_bus_o      (alert_major_bus_o),
        .double_fault_seen_o    (double_fault_seen_o),
        .crash_dump_o           (crash_dump_o)
    );

    // =========================================================================
    // Wishbone Crossbar
    // =========================================================================

    function automatic logic [NumMasters-1:0][NumSlaves-1:0] get_slave_access();
        logic [NumMasters-1:0][NumSlaves-1:0] access;
        access             = '1;               // default: full connectivity
        access[MasterIbus] = '0;               // ibus: clear all
        access[MasterIbus][SlaveItcm] = 1'b1;  // ibus: ITCM only
        access[MasterEb]  [SlaveItcm] = 1'b0;  // eb:   no ITCM
        return access;
    endfunction

    localparam logic [NumMasters-1:0][NumSlaves-1:0] XbarSlaveAccess = get_slave_access();

    wb_crossbar #(
        .NumMasters  (NumMasters),
        .NumSlaves   (NumSlaves),
        .SlaveAccess (XbarSlaveAccess)
    ) u_crossbar (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),

        .cfg_addr_base_i (cfg_addr_base),
        .cfg_addr_mask_i (cfg_addr_mask),

        // Masters
        .m_i         (m2s),
        .m_o         (s2m),

        // Slaves
        .s_o         (s_m2s),
        .s_i         (s_s2m)
    );

    // =========================================================================
    // ITCM (Instruction Tightly Coupled Memory)
    // =========================================================================

    wb_tcm #(
        .Depth       (ItcmDepth),
        .MemInitFile (ItcmInitFile)
    ) u_itcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .wb_m2s_i  (s_m2s[SlaveItcm]),
        .wb_s2m_o  (s_s2m[SlaveItcm])
    );

    // =========================================================================
    // DTCM (Data Tightly Coupled Memory)
    // =========================================================================

    wb_tcm #(
        .Depth       (DtcmDepth),
        .MemInitFile (DtcmInitFile)
    ) u_dtcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .wb_m2s_i  (s_m2s[SlaveDtcm]),
        .wb_s2m_o  (s_s2m[SlaveDtcm])
    );

    // =========================================================================
    // Timer
    // =========================================================================

    wb_timer u_timer (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .wb_m2s_i    (s_m2s[SlaveTimer]),
        .wb_s2m_o    (s_s2m[SlaveTimer]),
        .timer_irq_o (timer_irq)
    );

    // =========================================================================
    // Simulation Control (printf + halt for Verilator)
    // =========================================================================

    wb_sim_ctrl u_sim_ctrl (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .wb_m2s_i     (s_m2s[SlaveSimCtrl]),
        .wb_s2m_o     (s_s2m[SlaveSimCtrl]),
        .sim_halt_o   (sim_halt_o),
        .char_valid_o (sim_char_valid_o),
        .char_data_o  (sim_char_data_o)
    );

endmodule
