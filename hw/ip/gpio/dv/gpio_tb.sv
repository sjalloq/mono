// SPDX-License-Identifier: BSD-2-Clause
// GPIO Testbench
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Verification of GPIO peripheral:
// - Direct OUT write and read-back
// - Per-bit SET, CLEAR, TOGGLE
// - Input synchronization and read
// - Output enable
// - Edge and level interrupts with W1C clearing

module gpio_tb
    import wb_pkg::*;
;

    // =========================================================================
    // Parameters
    // =========================================================================

    parameter int CLK_PERIOD = 10;  // 100MHz

    // CSR offsets
    localparam logic [31:0] GPIO_OUT_ADDR    = 32'h00;
    localparam logic [31:0] GPIO_OE_ADDR     = 32'h04;
    localparam logic [31:0] GPIO_IN_ADDR     = 32'h08;
    localparam logic [31:0] GPIO_IE_ADDR     = 32'h0C;
    localparam logic [31:0] IRQ_STATUS_ADDR  = 32'h10;
    localparam logic [31:0] IRQ_ENABLE_ADDR  = 32'h14;
    localparam logic [31:0] IRQ_EDGE_ADDR    = 32'h18;
    localparam logic [31:0] IRQ_TYPE_ADDR    = 32'h1C;

    // Per-bit base addresses
    localparam logic [31:0] SET_BASE    = 32'h100;
    localparam logic [31:0] CLR_BASE    = 32'h180;
    localparam logic [31:0] TOGGLE_BASE = 32'h200;

    // =========================================================================
    // Signals
    // =========================================================================

    logic        clk;
    logic        rst_n;

    // Wishbone
    wb_m2s_t     wb_m2s;
    wb_s2m_t     wb_s2m;

    // GPIO pins
    logic [31:0] gpio_i;
    logic [31:0] gpio_o;
    logic [31:0] gpio_oe;

    // IRQ
    logic        irq;

    // Test tracking
    int pass_count;
    int fail_count;

    // =========================================================================
    // DUT
    // =========================================================================

    gpio #(
        .NumGpio (32)
    ) dut (
        .clk_i      (clk),
        .rst_ni     (rst_n),
        .wb_m2s_i   (wb_m2s),
        .wb_s2m_o   (wb_s2m),
        .gpio_i     (gpio_i),
        .gpio_o     (gpio_o),
        .gpio_oe_o  (gpio_oe),
        .irq_o      (irq)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Wishbone Tasks
    // =========================================================================

    task automatic wb_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        wb_m2s.cyc <= 1;
        wb_m2s.stb <= 1;
        wb_m2s.we  <= 1;
        wb_m2s.adr <= addr;
        wb_m2s.dat <= data;
        wb_m2s.sel <= 4'hF;
        @(posedge clk);
        while (!wb_s2m.ack) @(posedge clk);
        wb_m2s.cyc <= 0;
        wb_m2s.stb <= 0;
        wb_m2s.we  <= 0;
    endtask

    task automatic wb_read(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        wb_m2s.cyc <= 1;
        wb_m2s.stb <= 1;
        wb_m2s.we  <= 0;
        wb_m2s.adr <= addr;
        wb_m2s.sel <= 4'hF;
        @(posedge clk);
        while (!wb_s2m.ack) @(posedge clk);
        data = wb_s2m.dat;
        wb_m2s.cyc <= 0;
        wb_m2s.stb <= 0;
    endtask

    // =========================================================================
    // Check helpers
    // =========================================================================

    task automatic check(input string name, input [31:0] actual, input [31:0] expected);
        if (actual === expected) begin
            $display("  PASS: %s = 0x%08x", name, actual);
            pass_count++;
        end else begin
            $display("  FAIL: %s = 0x%08x, expected 0x%08x", name, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_signal(input string name, input logic actual, input logic expected);
        if (actual === expected) begin
            $display("  PASS: %s = %0d", name, actual);
            pass_count++;
        end else begin
            $display("  FAIL: %s = %0d, expected %0d", name, actual, expected);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================

    logic [31:0] read_data;

    initial begin
        $display("=== GPIO Testbench ===");
        pass_count = 0;
        fail_count = 0;

        // Initialize
        rst_n      = 0;
        wb_m2s.cyc = 0;
        wb_m2s.stb = 0;
        wb_m2s.we  = 0;
        wb_m2s.adr = 0;
        wb_m2s.dat = 0;
        wb_m2s.sel = 0;
        gpio_i     = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // -----------------------------------------------------------------
        // Test 1: Direct GPIO_OUT write and read-back
        // -----------------------------------------------------------------
        $display("\n[Test 1] Direct GPIO_OUT write and read-back");

        wb_write(GPIO_OUT_ADDR, 32'hDEADBEEF);
        wb_read(GPIO_OUT_ADDR, read_data);
        check("GPIO_OUT", read_data, 32'hDEADBEEF);
        check("gpio_o pin", gpio_o, 32'hDEADBEEF);

        // -----------------------------------------------------------------
        // Test 2: Per-bit SET
        // -----------------------------------------------------------------
        $display("\n[Test 2] Per-bit SET");

        // Clear output first
        wb_write(GPIO_OUT_ADDR, 32'h0);
        // SET bit 0
        wb_write(SET_BASE + 0*4, 32'h0);
        // SET bit 5
        wb_write(SET_BASE + 5*4, 32'h0);

        wb_read(GPIO_OUT_ADDR, read_data);
        check("GPIO_OUT after SET 0,5", read_data, 32'h00000021);

        // -----------------------------------------------------------------
        // Test 3: Per-bit CLEAR
        // -----------------------------------------------------------------
        $display("\n[Test 3] Per-bit CLEAR");

        // CLEAR bit 0
        wb_write(CLR_BASE + 0*4, 32'h0);

        wb_read(GPIO_OUT_ADDR, read_data);
        check("GPIO_OUT after CLR 0", read_data, 32'h00000020);

        // -----------------------------------------------------------------
        // Test 4: Per-bit TOGGLE
        // -----------------------------------------------------------------
        $display("\n[Test 4] Per-bit TOGGLE");

        // TOGGLE bit 5 (was 1, should become 0)
        wb_write(TOGGLE_BASE + 5*4, 32'h0);
        wb_read(GPIO_OUT_ADDR, read_data);
        check("GPIO_OUT after TOGGLE 5 (off)", read_data, 32'h00000000);

        // TOGGLE bit 5 again (was 0, should become 1)
        wb_write(TOGGLE_BASE + 5*4, 32'h0);
        wb_read(GPIO_OUT_ADDR, read_data);
        check("GPIO_OUT after TOGGLE 5 (on)", read_data, 32'h00000020);

        // -----------------------------------------------------------------
        // Test 5: Output enable
        // -----------------------------------------------------------------
        $display("\n[Test 5] Output enable");

        wb_write(GPIO_OE_ADDR, 32'hFF00FF00);
        repeat (2) @(posedge clk);
        check("gpio_oe pin", gpio_oe, 32'hFF00FF00);

        // -----------------------------------------------------------------
        // Test 6: Input read with sync delay
        // -----------------------------------------------------------------
        $display("\n[Test 6] Input read with sync delay");

        // Enable all inputs
        wb_write(GPIO_IE_ADDR, 32'hFFFFFFFF);

        // Drive input pins
        gpio_i = 32'hCAFEBABE;

        // Wait for 2-stage synchronizer + 1 cycle
        repeat (4) @(posedge clk);

        wb_read(GPIO_IN_ADDR, read_data);
        check("GPIO_IN", read_data, 32'hCAFEBABE);

        // -----------------------------------------------------------------
        // Test 7: Input enable masking
        // -----------------------------------------------------------------
        $display("\n[Test 7] Input enable masking");

        wb_write(GPIO_IE_ADDR, 32'h0000FFFF);
        repeat (2) @(posedge clk);

        wb_read(GPIO_IN_ADDR, read_data);
        check("GPIO_IN masked", read_data, 32'h0000BABE);

        // -----------------------------------------------------------------
        // Test 8: Rising edge interrupt
        // -----------------------------------------------------------------
        $display("\n[Test 8] Rising edge interrupt");

        // Reset state
        gpio_i = 32'h0;
        repeat (4) @(posedge clk);

        // Configure: bit 0 = edge triggered, rising
        wb_write(IRQ_TYPE_ADDR, 32'h00000001);    // bit 0 = edge
        wb_write(IRQ_EDGE_ADDR, 32'h00000001);    // bit 0 = rising
        wb_write(IRQ_ENABLE_ADDR, 32'h00000001);  // bit 0 enabled
        // Clear any pending status
        wb_write(IRQ_STATUS_ADDR, 32'hFFFFFFFF);

        repeat (2) @(posedge clk);
        check_signal("irq before edge", irq, 1'b0);

        // Generate rising edge on bit 0
        gpio_i[0] = 1'b1;
        // Wait for sync (2) + edge detect (1) + status update (1)
        repeat (5) @(posedge clk);

        check_signal("irq after rising edge", irq, 1'b1);

        // Read status
        wb_read(IRQ_STATUS_ADDR, read_data);
        check("IRQ_STATUS bit 0 set", read_data & 32'h1, 32'h1);

        // W1C: clear bit 0
        wb_write(IRQ_STATUS_ADDR, 32'h00000001);
        repeat (2) @(posedge clk);

        // Status should clear (input is still high, but edge is gone)
        wb_read(IRQ_STATUS_ADDR, read_data);
        check("IRQ_STATUS after W1C", read_data & 32'h1, 32'h0);
        check_signal("irq after W1C", irq, 1'b0);

        // -----------------------------------------------------------------
        // Test 9: Level interrupt (active high)
        // -----------------------------------------------------------------
        $display("\n[Test 9] Level interrupt (active high)");

        gpio_i = 32'h0;
        repeat (4) @(posedge clk);

        // Configure: bit 2 = level triggered, active high
        wb_write(IRQ_TYPE_ADDR, 32'h00000000);     // bit 2 = level
        wb_write(IRQ_EDGE_ADDR, 32'h00000004);     // bit 2 = active high
        wb_write(IRQ_ENABLE_ADDR, 32'h00000004);   // bit 2 enabled
        wb_write(IRQ_STATUS_ADDR, 32'hFFFFFFFF);   // clear all

        repeat (2) @(posedge clk);
        check_signal("irq before level", irq, 1'b0);

        // Drive bit 2 high
        gpio_i[2] = 1'b1;
        repeat (5) @(posedge clk);

        check_signal("irq with level high", irq, 1'b1);

        // W1C clear, but level is still active so it should re-assert
        wb_write(IRQ_STATUS_ADDR, 32'h00000004);
        repeat (3) @(posedge clk);

        wb_read(IRQ_STATUS_ADDR, read_data);
        check("IRQ_STATUS re-asserts (level)", read_data & 32'h4, 32'h4);

        // Remove the level stimulus
        gpio_i[2] = 1'b0;
        repeat (5) @(posedge clk);

        // Clear again
        wb_write(IRQ_STATUS_ADDR, 32'h00000004);
        repeat (3) @(posedge clk);

        wb_read(IRQ_STATUS_ADDR, read_data);
        check("IRQ_STATUS stays clear", read_data & 32'h4, 32'h0);
        check_signal("irq after level removed", irq, 1'b0);

        // -----------------------------------------------------------------
        // Done
        // -----------------------------------------------------------------
        $display("\n=== Tests Complete: %0d passed, %0d failed ===",
                 pass_count, fail_count);
        if (fail_count > 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");

        repeat (10) @(posedge clk);
        $finish;
    end

    // =========================================================================
    // Timeout
    // =========================================================================

    initial begin
        #500000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
