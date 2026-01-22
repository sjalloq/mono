// SPDX-License-Identifier: BSD-2-Clause
// Tightly Coupled Memory with Wishbone Pipelined Interface
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Single-cycle read/write TCM for instruction and data memory.
// Supports optional initialization from hex file.

module wb_tcm #(
    parameter int unsigned SIZE      = 16384,  // Size in bytes
    parameter int unsigned AW        = 32,     // Address width
    parameter int unsigned DW        = 32,     // Data width
    parameter string       INIT_FILE = ""      // Optional hex init file
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone pipelined slave interface
    input  logic             wb_cyc_i,
    input  logic             wb_stb_i,
    input  logic             wb_we_i,
    input  logic [AW-1:0]    wb_adr_i,   // Byte address
    input  logic [DW/8-1:0]  wb_sel_i,
    input  logic [DW-1:0]    wb_dat_i,
    output logic [DW-1:0]    wb_dat_o,
    output logic             wb_ack_o,
    output logic             wb_err_o,
    output logic             wb_stall_o
);

    // Internal parameters
    localparam int unsigned DEPTH    = SIZE / (DW / 8);
    localparam int unsigned AW_LOCAL = $clog2(DEPTH);

    // Memory array
    logic [DW-1:0] mem [DEPTH];

    // Word address from byte address
    logic [AW_LOCAL-1:0] word_addr;
    assign word_addr = wb_adr_i[$clog2(DW/8) +: AW_LOCAL];

    // Valid access check
    logic valid_access;
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Address range check
    logic addr_in_range;
    assign addr_in_range = (wb_adr_i[$clog2(DW/8) +: AW_LOCAL] < DEPTH);

    // Pipelined: never stall (single-cycle access)
    assign wb_stall_o = 1'b0;

    // Error on out-of-range access
    assign wb_err_o = valid_access && !addr_in_range;

    // Registered outputs
    logic wb_ack_d, wb_ack_q;
    logic [DW-1:0] wb_dat_d, wb_dat_q;

    // Memory write enable per byte lane
    logic mem_we;
    logic [DW-1:0] mem_wdata;

    // Combinational logic
    always_comb begin
        wb_ack_d = valid_access && addr_in_range;
        wb_dat_d = mem[word_addr];

        // Memory write data with byte enables
        mem_we = valid_access && addr_in_range && wb_we_i;
        mem_wdata = mem[word_addr];
        for (int i = 0; i < DW/8; i++) begin
            if (wb_sel_i[i]) begin
                mem_wdata[i*8 +: 8] = wb_dat_i[i*8 +: 8];
            end
        end
    end

    // Registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wb_ack_q <= 1'b0;
            wb_dat_q <= '0;
        end else begin
            wb_ack_q <= wb_ack_d;
            wb_dat_q <= wb_dat_d;
        end
    end

    // Memory write
    always_ff @(posedge clk_i) begin
        if (mem_we) begin
            mem[word_addr] <= mem_wdata;
        end
    end

    // Output assignments
    assign wb_ack_o = wb_ack_q;
    assign wb_dat_o = wb_dat_q;

    // Optional memory initialization
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

`ifdef FORMAL
    // Formal verification properties

    // ACK must only be asserted for one cycle per transaction
    property ack_single_cycle;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_ack_o |=> !wb_ack_o || (wb_cyc_i && wb_stb_i);
    endproperty
    assert property (ack_single_cycle);

    // ERR and ACK are mutually exclusive
    property err_ack_exclusive;
        @(posedge clk_i) disable iff (!rst_ni)
        !(wb_ack_o && wb_err_o);
    endproperty
    assert property (err_ack_exclusive);

    // No ACK without CYC and STB in previous cycle
    property ack_requires_request;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_ack_o |-> $past(wb_cyc_i && wb_stb_i);
    endproperty
    assert property (ack_requires_request);
`endif

endmodule
