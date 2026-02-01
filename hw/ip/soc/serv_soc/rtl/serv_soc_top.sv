// SPDX-License-Identifier: BSD-2-Clause
// SERV SoC Top Level
//
// Copyright (c) 2026 Shareef Jalloq
//
// Area-minimal Always-ON subsystem integrating:
// - SERV bit-serial RISC-V CPU with pipelined Wishbone interface
// - Wishbone pipelined crossbar (1xN)
// - Unified TCM (I+D memory)
// - RISC-V timer
// - Simulation control peripheral
// - Parameterized external Wishbone slave ports

module serv_soc_top
    import serv_soc_pkg::*;
    import wb_pkg::*;
#(
    parameter string       TcmInitFile  = "",   // Hex file for TCM initialization
    parameter int unsigned NumExtSlaves = 0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // External Wishbone slave ports
    output wb_m2s_t [NumExtSlaves > 0 ? NumExtSlaves-1 : 0:0] ext_wb_m2s_o,
    input  wb_s2m_t [NumExtSlaves > 0 ? NumExtSlaves-1 : 0:0] ext_wb_s2m_i,

    // Simulation control outputs (directly accessible by testbench)
    output logic             sim_halt_o,
    output logic             sim_char_valid_o,
    output logic [7:0]       sim_char_data_o
);

    // =========================================================================
    // Address map: concatenate internal + external slave address maps
    // =========================================================================

    localparam int unsigned NumSlaves = NumIntSlaves + NumExtSlaves;

    logic [NumSlaves-1:0][AddrWidth-1:0] cfg_addr_base;
    logic [NumSlaves-1:0][AddrWidth-1:0] cfg_addr_mask;

    assign cfg_addr_base[SlaveTcm] = TcmBase;
    assign cfg_addr_mask[SlaveTcm] = TcmMask;

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
    // SERV CPU
    // =========================================================================

    serv_wb_top #(
        .RESET_PC       (BootAddr),
        .WITH_CSR       (1),
        .RESET_STRATEGY ("MINI"),
        .W              (1)
    ) u_cpu (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .wb_m2s_o    (m2s[MasterServ]),
        .wb_s2m_i    (s2m[MasterServ]),
        .timer_irq_i (timer_irq)
    );

    // =========================================================================
    // Wishbone Crossbar (1xN)
    // =========================================================================

    // Single master has access to all slaves
    localparam logic [NumMasters-1:0][NumSlaves-1:0] XbarSlaveAccess = '1;

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
    // TCM (Unified Instruction + Data Memory)
    // =========================================================================

    wb_tcm #(
        .Depth       (TcmDepth),
        .MemInitFile (TcmInitFile)
    ) u_tcm (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .wb_m2s_i  (s_m2s[SlaveTcm]),
        .wb_s2m_o  (s_s2m[SlaveTcm])
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
