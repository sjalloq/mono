// SPDX-License-Identifier: BSD-2-Clause
// Tightly Coupled Memory with Wishbone Pipelined Interface
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Single-cycle read/write TCM for instruction and data memory.
// Supports optional initialization from hex file.

module wb_tcm
    import wb_pkg::*;
#(
    parameter int unsigned Depth       = 4096,  // Memory depth in words
    parameter string       MemInitFile = ""     // Optional hex init file
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Wishbone pipelined slave interface
    input  wb_m2s_t          wb_m2s_i,
    output wb_s2m_t          wb_s2m_o
);

    localparam int unsigned Width = 32;

    // Local address width for word addressing
    localparam int unsigned Aw = $clog2(Depth);

    // Memory array
    logic [Width-1:0] mem [Depth];

    // Word address from byte address
    logic [Aw-1:0] word_addr;
    assign word_addr = wb_m2s_i.adr[$clog2(Width/8) +: Aw];

    // Valid access check
    logic valid_access;
    assign valid_access = wb_m2s_i.cyc && wb_m2s_i.stb;

    // Registered outputs
    logic wb_ack_d, wb_ack_q;
    logic [Width-1:0] wb_dat_d, wb_dat_q;

    // Memory write enable per byte lane
    logic mem_we;
    logic [Width-1:0] mem_wdata;

    // Combinational logic
    always_comb begin
        wb_ack_d = valid_access;
        wb_dat_d = mem[word_addr];

        // Memory write data with byte enables
        mem_we = valid_access && wb_m2s_i.we;
        mem_wdata = mem[word_addr];
        for (int i = 0; i < Width/8; i++) begin
            if (wb_m2s_i.sel[i]) begin
                mem_wdata[i*8 +: 8] = wb_m2s_i.dat[i*8 +: 8];
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
    assign wb_s2m_o = '{dat: wb_dat_q, ack: wb_ack_q, err: 1'b0, stall: 1'b0};

    // =========================================================================
    // Simulation Support (DPI backdoor access)
    // =========================================================================
    // Uses lowRISC prim_util_memload.svh for testbench memory access:
    //   - simutil_memload: Load memory from VMEM file
    //   - simutil_set_mem: Write single word (backdoor)
    //   - simutil_get_mem: Read single word (backdoor)
    // Requires Width, Depth, MemInitFile parameters (aliased above).

    `include "prim_util_memload.svh"

`ifdef FORMAL
    // Formal verification properties

    // ACK must only be asserted for one cycle per transaction
    property ack_single_cycle;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_s2m_o.ack |=> !wb_s2m_o.ack || (wb_m2s_i.cyc && wb_m2s_i.stb);
    endproperty
    assert property (ack_single_cycle);

    // ERR and ACK are mutually exclusive
    property err_ack_exclusive;
        @(posedge clk_i) disable iff (!rst_ni)
        !(wb_s2m_o.ack && wb_s2m_o.err);
    endproperty
    assert property (err_ack_exclusive);

    // No ACK without CYC and STB in previous cycle
    property ack_requires_request;
        @(posedge clk_i) disable iff (!rst_ni)
        wb_s2m_o.ack |-> $past(wb_m2s_i.cyc && wb_m2s_i.stb);
    endproperty
    assert property (ack_requires_request);
`endif

endmodule
