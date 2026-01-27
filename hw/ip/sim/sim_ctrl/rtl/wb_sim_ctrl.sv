// SPDX-License-Identifier: BSD-2-Clause
// Simulation Control Peripheral with Wishbone Pipelined Interface
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Provides simulation control for Verilator testbenches:
// - Character output to log file (printf support)
// - Simulation termination
//
// Register Map (byte addresses):
//   0x00: SIM_OUT  (W)  - Write ASCII char to log file [7:0]
//   0x08: SIM_CTRL (W)  - Write 1 to bit 0 to halt simulation
//
// The 0x08 spacing matches Ibex's simulator_ctrl for software compatibility.

`ifdef VERILATOR

module wb_sim_ctrl #(
    parameter int unsigned AW       = 32,
    parameter int unsigned DW       = 32,
    parameter string       LogName  = "sim_out.log",
    parameter bit          FlushOnChar = 1,
    parameter bit          UseFinish   = 0  // Set to 0 for Cocotb compatibility
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone pipelined slave interface
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

    // Simulation control outputs (directly accessible)
    output logic             sim_halt_o,    // High when software requests halt
    output logic             char_valid_o,  // Pulse when character written
    output logic [7:0]       char_data_o    // Character value
);

    // Register addresses (word address, bits [3:2] of byte address)
    localparam logic [1:0] ADDR_SIM_OUT  = 2'h0;  // 0x00
    localparam logic [1:0] ADDR_SIM_CTRL = 2'h2;  // 0x08

    // Internal signals
    logic [1:0] word_addr;
    logic       valid_access;
    logic [2:0] sim_finish;

    // Log file handle
    integer log_fd;

    // Wishbone output registers
    logic wb_ack_d, wb_ack_q;

    // Character output registers
    logic       char_valid_d, char_valid_q;
    logic [7:0] char_data_d, char_data_q;

    // Output assignments
    assign sim_halt_o   = (sim_finish != 3'b0);
    assign char_valid_o = char_valid_q;
    assign char_data_o  = char_data_q;

    // Address decode (word address from bits [3:2])
    assign word_addr = wb_adr_i[3:2];
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Pipelined: never stall
    assign wb_stall_o = 1'b0;

    // No errors
    assign wb_err_o = 1'b0;

    // Read data always zero (write-only registers)
    assign wb_dat_o = '0;

    // ACK logic
    assign wb_ack_d = valid_access;
    assign wb_ack_o = wb_ack_q;

    // Open log file
    initial begin
        log_fd = $fopen(LogName, "w");
        if (log_fd == 0) begin
            $display("ERROR: Could not open log file: %s", LogName);
        end
    end

    // Close log file
    final begin
        $fclose(log_fd);
    end

    // Main logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wb_ack_q <= 1'b0;
            sim_finish <= 3'b0;
            char_valid_q <= 1'b0;
            char_data_q <= 8'b0;
        end else begin
            wb_ack_q <= wb_ack_d;
            char_valid_q <= char_valid_d;
            char_data_q <= char_data_d;

            // Handle writes
            if (valid_access && wb_we_i) begin
                case (word_addr)
                    ADDR_SIM_OUT: begin
                        // Character output
                        if (wb_sel_i[0]) begin
                            $fwrite(log_fd, "%c", wb_dat_i[7:0]);
                            if (FlushOnChar) begin
                                $fflush(log_fd);
                            end
                        end
                    end
                    ADDR_SIM_CTRL: begin
                        // Simulation halt request
                        if (wb_sel_i[0] && wb_dat_i[0] && (sim_finish == 3'b0)) begin
                            if (UseFinish) $display("Terminating simulation by software request.");
                            sim_finish <= 3'b001;
                        end
                    end
                    default: ;
                endcase
            end

            // Delayed finish to allow final transactions to complete
            if (sim_finish != 3'b0) begin
                sim_finish <= sim_finish + 3'b1;
            end
            if (UseFinish && (sim_finish >= 3'b010)) begin
                $finish;
            end
        end
    end

    // Combinational logic for character output
    always_comb begin
        char_valid_d = 1'b0;
        char_data_d = char_data_q;

        if (valid_access && wb_we_i && (word_addr == ADDR_SIM_OUT) && wb_sel_i[0]) begin
            char_valid_d = 1'b1;
            char_data_d = wb_dat_i[7:0];
        end
    end

endmodule

`else  // !VERILATOR

// Stub module for synthesis - active responses but no functionality
module wb_sim_ctrl #(
    parameter int unsigned AW       = 32,
    parameter int unsigned DW       = 32,
    parameter string       LogName  = "sim_out.log",
    parameter bit          FlushOnChar = 1,
    parameter bit          UseFinish   = 0
) (
    input  logic             clk_i,
    input  logic             rst_ni,

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

    output logic             sim_halt_o,
    output logic             char_valid_o,
    output logic [7:0]       char_data_o
);

    // Synthesis stub: respond to bus transactions but do nothing
    logic wb_ack_q;

    assign wb_stall_o = 1'b0;
    assign wb_err_o = 1'b0;
    assign wb_dat_o = '0;
    assign wb_ack_o = wb_ack_q;

    // Tie off simulation outputs
    assign sim_halt_o = 1'b0;
    assign char_valid_o = 1'b0;
    assign char_data_o = 8'b0;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wb_ack_q <= 1'b0;
        end else begin
            wb_ack_q <= wb_cyc_i && wb_stb_i;
        end
    end

endmodule

`endif
