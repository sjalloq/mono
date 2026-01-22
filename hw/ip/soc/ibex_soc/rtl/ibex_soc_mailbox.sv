// SPDX-License-Identifier: BSD-2-Clause
// Ibex SoC Mailbox
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Simple mailbox for host<->CPU bidirectional communication.
// Provides message passing with interrupt notification.
//
// Register Map:
//   0x00: HOST_TO_CPU_DATA  (RW) - Data from host to CPU
//   0x04: HOST_TO_CPU_CTRL  (RW) - Control/status
//         [0]: Valid - set by host, cleared by CPU on read
//         [1]: Full - set when valid, cleared by CPU
//   0x08: CPU_TO_HOST_DATA  (RW) - Data from CPU to host
//   0x0C: CPU_TO_HOST_CTRL  (RW) - Control/status
//         [0]: Valid - set by CPU, cleared by host on read
//         [1]: Full - set when valid, cleared by host
//   0x10-0x7F: Message buffer (32 words)

module ibex_soc_mailbox #(
    parameter int unsigned AW = 32,
    parameter int unsigned DW = 32,
    parameter int unsigned BUFFER_WORDS = 32
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

    // Interrupt outputs
    output logic             irq_host_to_cpu_o,  // Notify CPU: message from host
    output logic             irq_cpu_to_host_o   // Notify host: message from CPU
);

    // Register addresses
    localparam logic [6:0] REG_H2C_DATA = 7'h00;
    localparam logic [6:0] REG_H2C_CTRL = 7'h01;
    localparam logic [6:0] REG_C2H_DATA = 7'h02;
    localparam logic [6:0] REG_C2H_CTRL = 7'h03;
    localparam logic [6:0] REG_BUFFER_BASE = 7'h04;

    // Mailbox registers
    logic [31:0] h2c_data_d, h2c_data_q;
    logic        h2c_valid_d, h2c_valid_q;
    logic [31:0] c2h_data_d, c2h_data_q;
    logic        c2h_valid_d, c2h_valid_q;

    // Message buffer
    logic [31:0] buffer [BUFFER_WORDS];

    // Buffer write control
    logic        buffer_we;
    logic [31:0] buffer_wdata;
    logic [$clog2(BUFFER_WORDS)-1:0] buffer_waddr;

    // Wishbone output registers
    logic [DW-1:0] wb_dat_d, wb_dat_q;
    logic          wb_ack_d, wb_ack_q;

    // Address decode
    logic [6:0] reg_addr;
    assign reg_addr = wb_adr_i[8:2];

    // Valid access
    logic valid_access;
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Pipelined: never stall
    assign wb_stall_o = 1'b0;
    assign wb_err_o = 1'b0;

    // Interrupt outputs
    assign irq_host_to_cpu_o = h2c_valid_q;
    assign irq_cpu_to_host_o = c2h_valid_q;

    // Combinational logic
    always_comb begin
        // Default: hold values
        h2c_data_d = h2c_data_q;
        h2c_valid_d = h2c_valid_q;
        c2h_data_d = c2h_data_q;
        c2h_valid_d = c2h_valid_q;
        wb_dat_d = wb_dat_q;
        wb_ack_d = 1'b0;

        // Buffer write defaults
        buffer_we = 1'b0;
        buffer_wdata = wb_dat_i;
        buffer_waddr = reg_addr[$clog2(BUFFER_WORDS)-1:0] - REG_BUFFER_BASE[$clog2(BUFFER_WORDS)-1:0];

        // Write logic
        if (valid_access && wb_we_i) begin
            case (reg_addr)
                REG_H2C_DATA: begin
                    // Host writes data to CPU
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) h2c_data_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                    h2c_valid_d = 1'b1;
                end
                REG_H2C_CTRL: begin
                    // Write to control clears valid (CPU acknowledges)
                    if (wb_sel_i[0] && wb_dat_i[0] == 1'b0) begin
                        h2c_valid_d = 1'b0;
                    end
                end
                REG_C2H_DATA: begin
                    // CPU writes data to host
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) c2h_data_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                    c2h_valid_d = 1'b1;
                end
                REG_C2H_CTRL: begin
                    // Write to control clears valid (host acknowledges)
                    if (wb_sel_i[0] && wb_dat_i[0] == 1'b0) begin
                        c2h_valid_d = 1'b0;
                    end
                end
                default: begin
                    // Buffer write
                    if (reg_addr >= REG_BUFFER_BASE && reg_addr < REG_BUFFER_BASE + BUFFER_WORDS) begin
                        buffer_we = 1'b1;
                        // Apply byte enables to write data
                        buffer_wdata = buffer[buffer_waddr];
                        for (int i = 0; i < 4; i++) begin
                            if (wb_sel_i[i]) begin
                                buffer_wdata[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                            end
                        end
                    end
                end
            endcase
        end

        // Read logic
        wb_ack_d = valid_access;

        if (valid_access && !wb_we_i) begin
            case (reg_addr)
                REG_H2C_DATA: wb_dat_d = h2c_data_q;
                REG_H2C_CTRL: wb_dat_d = {30'b0, h2c_valid_q, h2c_valid_q};
                REG_C2H_DATA: wb_dat_d = c2h_data_q;
                REG_C2H_CTRL: wb_dat_d = {30'b0, c2h_valid_q, c2h_valid_q};
                default: begin
                    if (reg_addr >= REG_BUFFER_BASE && reg_addr < REG_BUFFER_BASE + BUFFER_WORDS) begin
                        wb_dat_d = buffer[buffer_waddr];
                    end else begin
                        wb_dat_d = '0;
                    end
                end
            endcase
        end
    end

    // Sequential logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            h2c_data_q <= '0;
            h2c_valid_q <= 1'b0;
            c2h_data_q <= '0;
            c2h_valid_q <= 1'b0;
            wb_dat_q <= '0;
            wb_ack_q <= 1'b0;
        end else begin
            h2c_data_q <= h2c_data_d;
            h2c_valid_q <= h2c_valid_d;
            c2h_data_q <= c2h_data_d;
            c2h_valid_q <= c2h_valid_d;
            wb_dat_q <= wb_dat_d;
            wb_ack_q <= wb_ack_d;
        end
    end

    // Buffer memory write (separate always_ff for memory)
    always_ff @(posedge clk_i) begin
        if (buffer_we) begin
            buffer[buffer_waddr] <= buffer_wdata;
        end
    end

    // Output assignments
    assign wb_dat_o = wb_dat_q;
    assign wb_ack_o = wb_ack_q;

endmodule
