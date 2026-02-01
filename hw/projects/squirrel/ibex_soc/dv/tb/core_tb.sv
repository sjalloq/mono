// SPDX-License-Identifier: BSD-2-Clause
// Cocotb testbench wrapper for core.sv
//
// Copyright (c) 2026 Shareef Jalloq
//
// Instantiates core DUT and simulates FT601 bidirectional data bus tristate
// behavior. Exposes flat signals for cocotb FT601Driver and clock/reset control.

module core_tb #(
    parameter string ItcmInitFile = "",
    parameter string DtcmInitFile = ""
) (
    // System clock and reset (driven by cocotb)
    input  logic        sys_clk,
    input  logic        sys_rst_n,

    // User LEDs (directly from DUT)
    output logic [1:0]  user_led,

    // User switches
    input  logic [1:0]  user_sw,

    // FT601 USB interface (flat signals for cocotb FT601Driver)
    // Data bus is split into input/output for Verilator 2-state compatibility.
    // V e r i l a t o r cannot resolve tristate (z becomes 0), so inout doesn't work.
    input  logic        usb_clk,
    input  logic        usb_rst_ni,
    input  wire  [31:0] usb_data,       // BFM -> DUT (FT601 drives during FPGA reads)
    output logic [31:0] usb_data_o,     // DUT -> BFM (FPGA drives during writes)
    output logic [3:0]  usb_be,         // DUT -> BFM (byte enables during writes)
    input  logic        usb_rxf_n,
    input  logic        usb_txe_n,
    output logic        usb_rd_n,
    output logic        usb_wr_n,
    output logic        usb_oe_n,
    output logic        usb_siwu_n,
    output logic        usb_rst_n,

    // Simulation control (from Ibex SoC SimCtrl peripheral)
    output logic        sim_halt,
    output logic        sim_char_valid,
    output logic [7:0]  sim_char_data,

    // CPU status / error outputs
    output logic        alert_minor,
    output logic        alert_major_internal,
    output logic        alert_major_bus,
    output logic        double_fault_seen,

    // Crash dump fields (unpacked from ibex_pkg::crash_dump_t for cocotb)
    output logic [31:0] crash_dump_current_pc,
    output logic [31:0] crash_dump_next_pc,
    output logic [31:0] crash_dump_last_data_addr,
    output logic [31:0] crash_dump_exception_pc,
    output logic [31:0] crash_dump_exception_addr
);

    // =========================================================================
    // FT601 tristate bus emulation
    // =========================================================================
    //
    // core.sv has split signals: data_i, data_o, data_oe (from IOBUF split).
    // We emulate the shared bidirectional bus here.

    logic [31:0] usb_data_i;
    logic        usb_data_oe;
    logic [3:0]  usb_be_o;
    logic        usb_be_oe;

    // Crash dump struct from DUT (unpacked to flat signals for cocotb)
    ibex_pkg::crash_dump_t crash_dump;

    assign crash_dump_current_pc    = crash_dump.current_pc;
    assign crash_dump_next_pc       = crash_dump.next_pc;
    assign crash_dump_last_data_addr = crash_dump.last_data_addr;
    assign crash_dump_exception_pc  = crash_dump.exception_pc;
    assign crash_dump_exception_addr = crash_dump.exception_addr;

    // V e r i l a t o r 2-state data bus routing (no tristate)
    // BFM drives usb_data input for FT601-to-FPGA (RX) transfers.
    // DUT output exposed on usb_data_o for FPGA-to-FT601 (TX) transfers.
    assign usb_data_i = usb_data;
    assign usb_be     = usb_be_o;

    // =========================================================================
    // DUT instantiation
    // =========================================================================

    core #(
        .ItcmInitFile (ItcmInitFile),
        .DtcmInitFile (DtcmInitFile)
    ) u_dut (
        .sys_clk      (sys_clk),
        .sys_rst_n    (sys_rst_n),

        .user_led     (user_led),
        .user_sw      (user_sw),

        // FT601 split signals
        .usb_clk_i    (usb_clk),
        .usb_rst_ni   (usb_rst_ni),
        .usb_data_i   (usb_data_i),
        .usb_data_o   (usb_data_o),    // wired to TB output port
        .usb_data_oe  (usb_data_oe),
        .usb_be_o     (usb_be_o),
        .usb_be_oe    (usb_be_oe),
        .usb_rxf_ni   (usb_rxf_n),
        .usb_txe_ni   (usb_txe_n),
        .usb_rd_no    (usb_rd_n),
        .usb_wr_no    (usb_wr_n),
        .usb_oe_no    (usb_oe_n),
        .usb_siwu_no  (usb_siwu_n),
        .usb_rst_no   (usb_rst_n),

        // Simulation control
        .sim_halt_o       (sim_halt),
        .sim_char_valid_o (sim_char_valid),
        .sim_char_data_o  (sim_char_data),

        // CPU status / error
        .alert_minor_o          (alert_minor),
        .alert_major_internal_o (alert_major_internal),
        .alert_major_bus_o      (alert_major_bus),
        .double_fault_seen_o    (double_fault_seen),
        .crash_dump_o           (crash_dump)
    );

    // Unused signals (tristate enables not needed in Verilator 2-state sim)
    logic unused_oe;
    assign unused_oe = &{usb_data_oe, usb_be_oe};

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("core_tb.fst");
            $dumpvars(0, core_tb);
        end
    end

endmodule
