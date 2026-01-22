// SPDX-License-Identifier: BSD-2-Clause
// Ibex SoC Control/Status Registers
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Simple CSR block for basic SoC control. Can be expanded with
// SystemRDL-generated registers later.
//
// Register Map:
//   0x00: ID          (RO)  - SoC identifier (0x1BEX5000)
//   0x04: VERSION     (RO)  - Version (major.minor.patch)
//   0x08: SCRATCH     (RW)  - Scratch register
//   0x0C: CONTROL     (RW)  - Control register
//         [0]: CPU reset
//         [1]: LED0
//         [2]: LED1
//   0x10: STATUS      (RO)  - Status register
//         [0]: Switch 0
//         [1]: Switch 1
//   0x14: IRQ_STATUS  (RO)  - Interrupt status
//   0x18: IRQ_ENABLE  (RW)  - Interrupt enable
//   0x1C: IRQ_PENDING (RW1C) - Interrupt pending (write 1 to clear)

module ibex_soc_csr #(
    parameter int unsigned AW = 32,
    parameter int unsigned DW = 32,
    parameter logic [31:0] SOC_ID = 32'h1BEX_5000,
    parameter logic [31:0] VERSION = 32'h0001_0000  // v0.1.0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone slave interface
    input  logic             wb_cyc_i,
    input  logic             wb_stb_i,
    input  logic             wb_we_i,
    input  logic [AW-1:0]    wb_adr_i,
    input  logic [DW/8-1:0]  wb_sel_i,
    input  logic [DW-1:0]    wb_dat_i,
    output logic [DW-1:0]    wb_dat_o,
    output logic             wb_ack_o,
    output logic             wb_err_o,
    output logic             wb_stall_o,

    // External I/O
    output logic [1:0]       led_o,
    input  logic [1:0]       sw_i,

    // CPU control
    output logic             cpu_rst_o,

    // Interrupt interface
    input  logic [15:0]      irq_src_i,
    output logic             irq_o
);

    // Register addresses
    localparam logic [5:0] REG_ID          = 6'h00;
    localparam logic [5:0] REG_VERSION     = 6'h01;
    localparam logic [5:0] REG_SCRATCH     = 6'h02;
    localparam logic [5:0] REG_CONTROL     = 6'h03;
    localparam logic [5:0] REG_STATUS      = 6'h04;
    localparam logic [5:0] REG_IRQ_STATUS  = 6'h05;
    localparam logic [5:0] REG_IRQ_ENABLE  = 6'h06;
    localparam logic [5:0] REG_IRQ_PENDING = 6'h07;

    // Registers
    logic [31:0] scratch_d, scratch_q;
    logic [31:0] control_d, control_q;
    logic [15:0] irq_enable_d, irq_enable_q;
    logic [15:0] irq_pending_d, irq_pending_q;
    logic [DW-1:0] wb_dat_d, wb_dat_q;
    logic          wb_ack_d, wb_ack_q;

    // Address decode
    logic [5:0] reg_addr;
    assign reg_addr = wb_adr_i[7:2];

    // Valid access
    logic valid_access;
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Pipelined: never stall
    assign wb_stall_o = 1'b0;
    assign wb_err_o = 1'b0;

    // Control outputs
    assign cpu_rst_o = control_q[0];
    assign led_o = control_q[2:1];

    // Interrupt logic
    logic [15:0] irq_status;
    assign irq_status = irq_src_i;
    assign irq_o = |(irq_pending_q & irq_enable_q);

    // Combinational logic
    always_comb begin
        // Default: hold values
        scratch_d = scratch_q;
        control_d = control_q;
        irq_enable_d = irq_enable_q;
        irq_pending_d = irq_pending_q;
        wb_dat_d = wb_dat_q;
        wb_ack_d = 1'b0;

        // IRQ pending: Set on rising edge of interrupt source
        for (int i = 0; i < 16; i++) begin
            if (irq_src_i[i]) begin
                irq_pending_d[i] = 1'b1;
            end
        end

        // Write logic
        if (valid_access && wb_we_i) begin
            case (reg_addr)
                REG_SCRATCH: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) scratch_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                REG_CONTROL: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) control_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                REG_IRQ_ENABLE: begin
                    for (int i = 0; i < 2; i++) begin
                        if (wb_sel_i[i]) irq_enable_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                REG_IRQ_PENDING: begin
                    // Write 1 to clear
                    for (int i = 0; i < 16; i++) begin
                        if (wb_sel_i[i/8] && wb_dat_i[i]) begin
                            irq_pending_d[i] = 1'b0;
                        end
                    end
                end
                default: ;
            endcase
        end

        // Read logic
        wb_ack_d = valid_access;

        if (valid_access && !wb_we_i) begin
            case (reg_addr)
                REG_ID:          wb_dat_d = SOC_ID;
                REG_VERSION:     wb_dat_d = VERSION;
                REG_SCRATCH:     wb_dat_d = scratch_q;
                REG_CONTROL:     wb_dat_d = control_q;
                REG_STATUS:      wb_dat_d = {30'b0, sw_i};
                REG_IRQ_STATUS:  wb_dat_d = {16'b0, irq_status};
                REG_IRQ_ENABLE:  wb_dat_d = {16'b0, irq_enable_q};
                REG_IRQ_PENDING: wb_dat_d = {16'b0, irq_pending_q};
                default:         wb_dat_d = '0;
            endcase
        end
    end

    // Sequential logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            scratch_q <= '0;
            control_q <= '0;
            irq_enable_q <= '0;
            irq_pending_q <= '0;
            wb_dat_q <= '0;
            wb_ack_q <= 1'b0;
        end else begin
            scratch_q <= scratch_d;
            control_q <= control_d;
            irq_enable_q <= irq_enable_d;
            irq_pending_q <= irq_pending_d;
            wb_dat_q <= wb_dat_d;
            wb_ack_q <= wb_ack_d;
        end
    end

    // Output assignments
    assign wb_dat_o = wb_dat_q;
    assign wb_ack_o = wb_ack_q;

endmodule
