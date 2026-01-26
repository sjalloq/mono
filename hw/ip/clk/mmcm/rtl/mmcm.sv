// SPDX-License-Identifier: BSD-2-Clause
// MMCM Wrapper
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Parameterized Xilinx MMCM wrapper.
// Generates up to 4 output clocks from a single input.

module mmcm #(
    // Input clock period in nanoseconds
    parameter real CLK_IN_PERIOD_NS = 10.0,         // 100 MHz default

    // VCO configuration
    // VCO_freq = CLK_IN_freq * VCO_MULT / VCO_DIV
    // VCO must be 600-1200 MHz for 7-series (speed grade dependent)
    parameter real VCO_MULT = 10.0,                 // VCO multiplier (2.0-64.0)
    parameter int  VCO_DIV  = 1,                    // VCO input divider (1-106)

    // Output clock dividers
    // CLKOUTn_freq = VCO_freq / CLKOUTn_DIV
    parameter real CLKOUT0_DIV = 16.0,              // 62.5 MHz (supports fractional)
    parameter int  CLKOUT1_DIV = 8,                 // 125 MHz
    parameter int  CLKOUT2_DIV = 4,                 // 250 MHz
    parameter int  CLKOUT3_DIV = 1,                 // Unused by default

    // Output clock phase shifts (degrees)
    parameter real CLKOUT0_PHASE = 0.0,
    parameter real CLKOUT1_PHASE = 0.0,
    parameter real CLKOUT2_PHASE = 0.0,
    parameter real CLKOUT3_PHASE = 0.0,

    // Enable outputs (active high)
    parameter bit CLKOUT0_EN = 1'b1,
    parameter bit CLKOUT1_EN = 1'b1,
    parameter bit CLKOUT2_EN = 1'b1,
    parameter bit CLKOUT3_EN = 1'b0
) (
    // Input clock and reset
    input  logic clk_i,
    input  logic rst_i,

    // Output clocks
    output logic clkout0_o,
    output logic clkout1_o,
    output logic clkout2_o,
    output logic clkout3_o,

    // MMCM status
    output logic locked_o
);

  // ---------------------------------------------------------------------------
  // Frequency Calculations (for documentation/verification)
  // ---------------------------------------------------------------------------
  localparam real CLK_IN_FREQ_MHZ  = 1000.0 / CLK_IN_PERIOD_NS;
  localparam real VCO_FREQ_MHZ     = CLK_IN_FREQ_MHZ * VCO_MULT / VCO_DIV;
  localparam real CLKOUT0_FREQ_MHZ = VCO_FREQ_MHZ / CLKOUT0_DIV;
  localparam real CLKOUT1_FREQ_MHZ = VCO_FREQ_MHZ / real'(CLKOUT1_DIV);
  localparam real CLKOUT2_FREQ_MHZ = VCO_FREQ_MHZ / real'(CLKOUT2_DIV);
  localparam real CLKOUT3_FREQ_MHZ = VCO_FREQ_MHZ / real'(CLKOUT3_DIV);

  // VCO range check (7-series: 600-1200 MHz typical)
  initial begin
    if (VCO_FREQ_MHZ < 600.0 || VCO_FREQ_MHZ > 1200.0) begin
      $error("MMCM: VCO frequency %.2f MHz out of range [600-1200 MHz]", VCO_FREQ_MHZ);
    end
    $display("MMCM Configuration:");
    $display("  Input:   %.3f MHz", CLK_IN_FREQ_MHZ);
    $display("  VCO:     %.3f MHz (MULT=%.1f, DIV=%0d)", VCO_FREQ_MHZ, VCO_MULT, VCO_DIV);
    $display("  CLKOUT0: %.3f MHz (DIV=%.1f) %s", CLKOUT0_FREQ_MHZ, CLKOUT0_DIV,
             CLKOUT0_EN ? "ENABLED" : "disabled");
    $display("  CLKOUT1: %.3f MHz (DIV=%0d) %s", CLKOUT1_FREQ_MHZ, CLKOUT1_DIV,
             CLKOUT1_EN ? "ENABLED" : "disabled");
    $display("  CLKOUT2: %.3f MHz (DIV=%0d) %s", CLKOUT2_FREQ_MHZ, CLKOUT2_DIV,
             CLKOUT2_EN ? "ENABLED" : "disabled");
    $display("  CLKOUT3: %.3f MHz (DIV=%0d) %s", CLKOUT3_FREQ_MHZ, CLKOUT3_DIV,
             CLKOUT3_EN ? "ENABLED" : "disabled");
  end

  // ---------------------------------------------------------------------------
  // MMCM Instance
  // ---------------------------------------------------------------------------

  logic clkout0_unbuf;
  logic clkout1_unbuf;
  logic clkout2_unbuf;
  logic clkout3_unbuf;
  logic clk_fb;
  logic clk_fb_buf;

  MMCME2_BASE #(
      .BANDWIDTH         ("OPTIMIZED"),
      .CLKFBOUT_MULT_F   (VCO_MULT),
      .CLKFBOUT_PHASE    (0.0),
      .CLKIN1_PERIOD     (CLK_IN_PERIOD_NS),
      .DIVCLK_DIVIDE     (VCO_DIV),
      .REF_JITTER1       (0.01),
      .STARTUP_WAIT      ("FALSE"),
      .CLKOUT0_DIVIDE_F  (CLKOUT0_DIV),
      .CLKOUT0_DUTY_CYCLE(0.5),
      .CLKOUT0_PHASE     (CLKOUT0_PHASE),
      .CLKOUT1_DIVIDE    (CLKOUT1_DIV),
      .CLKOUT1_DUTY_CYCLE(0.5),
      .CLKOUT1_PHASE     (CLKOUT1_PHASE),
      .CLKOUT2_DIVIDE    (CLKOUT2_DIV),
      .CLKOUT2_DUTY_CYCLE(0.5),
      .CLKOUT2_PHASE     (CLKOUT2_PHASE),
      .CLKOUT3_DIVIDE    (CLKOUT3_DIV),
      .CLKOUT3_DUTY_CYCLE(0.5),
      .CLKOUT3_PHASE     (CLKOUT3_PHASE),
      .CLKOUT4_CASCADE   ("FALSE"),
      .CLKOUT4_DIVIDE    (1),
      .CLKOUT4_DUTY_CYCLE(0.5),
      .CLKOUT4_PHASE     (0.0),
      .CLKOUT5_DIVIDE    (1),
      .CLKOUT5_DUTY_CYCLE(0.5),
      .CLKOUT5_PHASE     (0.0),
      .CLKOUT6_DIVIDE    (1),
      .CLKOUT6_DUTY_CYCLE(0.5),
      .CLKOUT6_PHASE     (0.0)
  ) u_mmcm (
      .CLKIN1  (clk_i),
      .CLKFBIN (clk_fb_buf),
      .RST     (rst_i),
      .PWRDWN  (1'b0),

      .CLKOUT0 (clkout0_unbuf),
      .CLKOUT1 (clkout1_unbuf),
      .CLKOUT2 (clkout2_unbuf),
      .CLKOUT3 (clkout3_unbuf),
      .CLKOUT4 (),
      .CLKOUT5 (),
      .CLKOUT6 (),
      .CLKOUT0B(),
      .CLKOUT1B(),
      .CLKOUT2B(),
      .CLKOUT3B(),
      .CLKFBOUT (clk_fb),
      .CLKFBOUTB(),
      .LOCKED  (locked_o)
  );

  // ---------------------------------------------------------------------------
  // Clock Buffers
  // ---------------------------------------------------------------------------

  BUFG u_bufg_fb (
      .I(clk_fb),
      .O(clk_fb_buf)
  );

  if (CLKOUT0_EN) begin : gen_bufg0
    BUFG u_bufg (
        .I(clkout0_unbuf),
        .O(clkout0_o)
    );
  end else begin : gen_no_bufg0
    assign clkout0_o = 1'b0;
  end

  if (CLKOUT1_EN) begin : gen_bufg1
    BUFG u_bufg (
        .I(clkout1_unbuf),
        .O(clkout1_o)
    );
  end else begin : gen_no_bufg1
    assign clkout1_o = 1'b0;
  end

  if (CLKOUT2_EN) begin : gen_bufg2
    BUFG u_bufg (
        .I(clkout2_unbuf),
        .O(clkout2_o)
    );
  end else begin : gen_no_bufg2
    assign clkout2_o = 1'b0;
  end

  if (CLKOUT3_EN) begin : gen_bufg3
    BUFG u_bufg (
        .I(clkout3_unbuf),
        .O(clkout3_o)
    );
  end else begin : gen_no_bufg3
    assign clkout3_o = 1'b0;
  end

endmodule
