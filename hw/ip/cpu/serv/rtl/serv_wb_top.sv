// SPDX-License-Identifier: BSD-2-Clause
// SERV RISC-V Core with Pipelined Wishbone Interface
//
// Copyright (c) 2026 Shareef Jalloq
//
// Wraps Olof Kindgren's serv_rf_top with:
//   1. I/D bus arbiter (combinational, ibus priority)
//   2. Classic-to-pipelined Wishbone bridge
//
// Provides a single pipelined Wishbone master port using wb_m2s_t/wb_s2m_t.

module serv_wb_top
    import wb_pkg::*;
#(
    parameter logic [31:0] RESET_PC       = 32'h0000_0000,
    parameter [0:0]        COMPRESSED     = 0,
    parameter [0:0]        MDU            = 0,
    parameter              PRE_REGISTER   = 1,
    parameter              RESET_STRATEGY = "MINI",
    parameter              WITH_CSR       = 1,
    parameter              W              = 1
) (
    input  logic      clk_i,
    input  logic      rst_ni,

    // Single pipelined Wishbone master
    output wb_m2s_t   wb_m2s_o,
    input  wb_s2m_t   wb_s2m_i,

    // Timer interrupt
    input  logic      timer_irq_i
);

    // =========================================================================
    // Reset polarity conversion (active-low repo convention -> active-high SERV)
    // =========================================================================

    logic rst;
    assign rst = ~rst_ni;

    // =========================================================================
    // SERV CPU (serv_rf_top) signals
    // =========================================================================

    // Instruction bus (classic Wishbone, read-only)
    logic [31:0] ibus_adr;
    logic        ibus_cyc;
    logic [31:0] ibus_rdt;
    logic        ibus_ack;

    // Data bus (classic Wishbone, read/write)
    logic [31:0] dbus_adr;
    logic [31:0] dbus_dat;
    logic [3:0]  dbus_sel;
    logic        dbus_we;
    logic        dbus_cyc;
    logic [31:0] dbus_rdt;
    logic        dbus_ack;

    serv_rf_top #(
        .RESET_PC       (RESET_PC),
        .COMPRESSED     (COMPRESSED),
        .ALIGN          (COMPRESSED),
        .MDU            (MDU),
        .PRE_REGISTER   (PRE_REGISTER),
        .RESET_STRATEGY (RESET_STRATEGY),
        .WITH_CSR       (WITH_CSR),
        .W              (W)
    ) u_cpu (
        .clk          (clk_i),
        .i_rst        (rst),
        .i_timer_irq  (timer_irq_i),

        // Instruction bus
        .o_ibus_adr   (ibus_adr),
        .o_ibus_cyc   (ibus_cyc),
        .i_ibus_rdt   (ibus_rdt),
        .i_ibus_ack   (ibus_ack),

        // Data bus
        .o_dbus_adr   (dbus_adr),
        .o_dbus_dat   (dbus_dat),
        .o_dbus_sel   (dbus_sel),
        .o_dbus_we    (dbus_we),
        .o_dbus_cyc   (dbus_cyc),
        .i_dbus_rdt   (dbus_rdt),
        .i_dbus_ack   (dbus_ack),

        // Extension interface (unused)
        .o_ext_rs1    (ext_rs1),
        .o_ext_rs2    (ext_rs2),
        .o_ext_funct3 (ext_funct3),
        .i_ext_rd     (32'h0),
        .i_ext_ready  (1'b0),

        // MDU (unused)
        .o_mdu_valid  (mdu_valid)
    );

    // Tie off unused extension/MDU outputs
    logic [31:0] ext_rs1, ext_rs2;
    logic [2:0]  ext_funct3;
    logic        mdu_valid;
    logic        unused;
    assign unused = &{ext_rs1, ext_rs2, ext_funct3, mdu_valid};

    // =========================================================================
    // I/D Arbiter (combinational, ibus priority)
    // =========================================================================
    //
    // SERV never issues ibus and dbus requests simultaneously, so this is
    // a simple mux with ibus priority (same logic as servile_arbiter).

    logic [31:0] arb_adr;
    logic [31:0] arb_dat;
    logic [3:0]  arb_sel;
    logic        arb_we;
    logic        arb_cyc;
    logic [31:0] arb_rdt;
    logic        arb_ack;

    assign arb_adr = ibus_cyc ? ibus_adr : dbus_adr;
    assign arb_dat = dbus_dat;
    assign arb_sel = ibus_cyc ? 4'hF    : dbus_sel;
    assign arb_we  = dbus_we & ~ibus_cyc;
    assign arb_cyc = ibus_cyc | dbus_cyc;

    // Route ack/data back to the correct bus
    assign ibus_rdt = arb_rdt;
    assign ibus_ack = arb_ack &  ibus_cyc;
    assign dbus_rdt = arb_rdt;
    assign dbus_ack = arb_ack & ~ibus_cyc;

    // =========================================================================
    // Classic-to-Pipelined Wishbone Bridge
    // =========================================================================
    //
    // SERV's classic WB: cyc held until ack, stb=cyc (always).
    // Pipelined WB B4: stb accepted when !stall, deasserted after; ack later.
    //
    // FSM: IDLE -> ADDR (assert stb until !stall) -> DATA (wait ack) -> IDLE
    //
    // Pattern follows ibex_obi2wb.sv adapted for classic WB input.

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ADDR,
        ST_DATA
    } bridge_state_e;

    bridge_state_e state_q, state_d;

    // Registered address-phase signals (latched when classic cyc rises)
    logic [31:0] adr_q;
    logic [31:0] dat_q;
    logic [3:0]  sel_q;
    logic        we_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            adr_q   <= '0;
            dat_q   <= '0;
            sel_q   <= '0;
            we_q    <= 1'b0;
        end else begin
            state_q <= state_d;
            if (state_q == ST_IDLE && arb_cyc) begin
                adr_q <= arb_adr;
                dat_q <= arb_dat;
                sel_q <= arb_sel;
                we_q  <= arb_we;
            end
        end
    end

    always_comb begin
        state_d = state_q;
        case (state_q)
            ST_IDLE: begin
                if (arb_cyc) begin
                    state_d = ST_ADDR;
                end
            end
            ST_ADDR: begin
                if (!wb_s2m_i.stall) begin
                    state_d = ST_DATA;
                end
            end
            ST_DATA: begin
                if (wb_s2m_i.ack || wb_s2m_i.err) begin
                    state_d = ST_IDLE;
                end
            end
            default: state_d = ST_IDLE;
        endcase
    end

    // Pipelined WB master outputs
    assign wb_m2s_o.cyc = (state_q == ST_ADDR) || (state_q == ST_DATA);
    assign wb_m2s_o.stb = (state_q == ST_ADDR);
    assign wb_m2s_o.we  = we_q;
    assign wb_m2s_o.adr = adr_q;
    assign wb_m2s_o.sel = sel_q;
    assign wb_m2s_o.dat = dat_q;

    // Classic WB response (ack from pipelined side back to arbiter)
    assign arb_ack = wb_s2m_i.ack || wb_s2m_i.err;
    assign arb_rdt = wb_s2m_i.dat;

endmodule
