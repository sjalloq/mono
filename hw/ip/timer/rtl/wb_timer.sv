// SPDX-License-Identifier: BSD-2-Clause
// RISC-V Timer with Wishbone Interface
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Implements RISC-V mtime and mtimecmp registers with timer interrupt.
// 64-bit timer accessed via 32-bit Wishbone interface.
//
// Register Map (word addresses):
//   0x00: mtime_lo     (R/W) - Lower 32 bits of mtime
//   0x04: mtime_hi     (R/W) - Upper 32 bits of mtime
//   0x08: mtimecmp_lo  (R/W) - Lower 32 bits of mtimecmp
//   0x0C: mtimecmp_hi  (R/W) - Upper 32 bits of mtimecmp
//   0x10: prescaler    (R/W) - Clock prescaler (mtime increments every prescaler+1 cycles)

module wb_timer #(
    parameter int unsigned AW = 32,
    parameter int unsigned DW = 32
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

    // Timer interrupt output
    output logic             timer_irq_o
);

    // Register addresses (word aligned)
    localparam logic [3:0] ADDR_MTIME_LO    = 4'h0;
    localparam logic [3:0] ADDR_MTIME_HI    = 4'h1;
    localparam logic [3:0] ADDR_MTIMECMP_LO = 4'h2;
    localparam logic [3:0] ADDR_MTIMECMP_HI = 4'h3;
    localparam logic [3:0] ADDR_PRESCALER   = 4'h4;

    // Timer registers
    logic [63:0] mtime_d, mtime_q;
    logic [63:0] mtimecmp_d, mtimecmp_q;
    logic [31:0] prescaler_d, prescaler_q;
    logic [31:0] prescaler_cnt_d, prescaler_cnt_q;

    // Wishbone output registers
    logic [DW-1:0] wb_dat_d, wb_dat_q;
    logic          wb_ack_d, wb_ack_q;
    logic          wb_err_d, wb_err_q;

    // Word address
    logic [3:0] word_addr;
    assign word_addr = wb_adr_i[5:2];

    // Valid access
    logic valid_access;
    assign valid_access = wb_cyc_i && wb_stb_i;

    // Pipelined: never stall
    assign wb_stall_o = 1'b0;

    // Timer tick (when prescaler counter wraps)
    logic timer_tick;
    assign timer_tick = (prescaler_cnt_q == prescaler_q);

    // Timer interrupt: mtime >= mtimecmp
    assign timer_irq_o = (mtime_q >= mtimecmp_q);

    // Combinational logic
    always_comb begin
        // Default: hold values
        prescaler_cnt_d = prescaler_cnt_q;
        mtime_d = mtime_q;
        mtimecmp_d = mtimecmp_q;
        prescaler_d = prescaler_q;
        wb_dat_d = wb_dat_q;
        wb_ack_d = 1'b0;
        wb_err_d = 1'b0;

        // Prescaler counter logic
        if (timer_tick) begin
            prescaler_cnt_d = '0;
        end else begin
            prescaler_cnt_d = prescaler_cnt_q + 1;
        end

        // mtime counter logic
        if (valid_access && wb_we_i) begin
            case (word_addr)
                ADDR_MTIME_LO: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) mtime_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                ADDR_MTIME_HI: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) mtime_d[32 + i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                default: ;
            endcase
        end else if (timer_tick) begin
            mtime_d = mtime_q + 1;
        end

        // mtimecmp register logic
        if (valid_access && wb_we_i) begin
            case (word_addr)
                ADDR_MTIMECMP_LO: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) mtimecmp_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                ADDR_MTIMECMP_HI: begin
                    for (int i = 0; i < 4; i++) begin
                        if (wb_sel_i[i]) mtimecmp_d[32 + i*8 +: 8] = wb_dat_i[i*8 +: 8];
                    end
                end
                default: ;
            endcase
        end

        // Prescaler register logic
        if (valid_access && wb_we_i && word_addr == ADDR_PRESCALER) begin
            for (int i = 0; i < 4; i++) begin
                if (wb_sel_i[i]) prescaler_d[i*8 +: 8] = wb_dat_i[i*8 +: 8];
            end
        end

        // Wishbone response logic
        wb_ack_d = valid_access;

        if (valid_access && !wb_we_i) begin
            case (word_addr)
                ADDR_MTIME_LO:    wb_dat_d = mtime_q[31:0];
                ADDR_MTIME_HI:    wb_dat_d = mtime_q[63:32];
                ADDR_MTIMECMP_LO: wb_dat_d = mtimecmp_q[31:0];
                ADDR_MTIMECMP_HI: wb_dat_d = mtimecmp_q[63:32];
                ADDR_PRESCALER:   wb_dat_d = prescaler_q;
                default:          wb_dat_d = '0;
            endcase
        end
    end

    // Sequential logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            prescaler_cnt_q <= '0;
            mtime_q <= '0;
            mtimecmp_q <= 64'hFFFF_FFFF_FFFF_FFFF;  // Max value = no interrupt initially
            prescaler_q <= '0;
            wb_dat_q <= '0;
            wb_ack_q <= 1'b0;
            wb_err_q <= 1'b0;
        end else begin
            prescaler_cnt_q <= prescaler_cnt_d;
            mtime_q <= mtime_d;
            mtimecmp_q <= mtimecmp_d;
            prescaler_q <= prescaler_d;
            wb_dat_q <= wb_dat_d;
            wb_ack_q <= wb_ack_d;
            wb_err_q <= wb_err_d;
        end
    end

    // Output assignments
    assign wb_dat_o = wb_dat_q;
    assign wb_ack_o = wb_ack_q;
    assign wb_err_o = wb_err_q;

endmodule
