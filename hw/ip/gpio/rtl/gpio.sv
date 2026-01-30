// SPDX-License-Identifier: BSD-2-Clause
// GPIO Peripheral
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// General Purpose I/O with:
// - 32-bit output register with per-bit SET/CLEAR/TOGGLE
// - Configurable output enable
// - Synchronized input with input enable
// - Per-pin configurable interrupts (edge/level, polarity)
//
// Address map:
//   0x000..0x01F: CSR block (PeakRDL-generated)
//   0x100..0x17C: Per-bit SET  (write to 0x100+n*4 sets GPIO[n])
//   0x180..0x1FC: Per-bit CLR  (write to 0x180+n*4 clears GPIO[n])
//   0x200..0x27C: Per-bit TOGGLE (write to 0x200+n*4 toggles GPIO[n])

module gpio
    import wb_pkg::*;
    import gpio_csr_reg_pkg::*;
#(
    parameter int unsigned NumGpio = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // =========================================================================
    // Wishbone Slave Interface
    // =========================================================================
    input  wb_m2s_t          wb_m2s_i,
    output wb_s2m_t          wb_s2m_o,

    // =========================================================================
    // GPIO Pins
    // =========================================================================
    input  logic [NumGpio-1:0] gpio_i,
    output logic [NumGpio-1:0] gpio_o,
    output logic [NumGpio-1:0] gpio_oe_o,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output logic             irq_o
);

    // =========================================================================
    // Signal Declarations
    // =========================================================================

    // Simple bus interface (between wb2simple and internal logic)
    logic             reg_we;
    logic             reg_re;
    logic [31:0]      reg_addr;
    logic [31:0]      reg_wdata;
    logic [31:0]      reg_rdata;

    // CSR bus (to generated CSR block)
    logic             csr_we;
    logic             csr_re;
    logic [31:0]      csr_rdata;

    // Hardware interface structs
    gpio_csr_reg2hw_t reg2hw;
    gpio_csr_hw2reg_t hw2reg;

    // GPIO output register (managed by gpio_bit_ctrl)
    logic [NumGpio-1:0] gpio_out;

    // Input synchronization
    logic [NumGpio-1:0] gpio_sync_q1, gpio_sync_q2;

    // Interrupt signals
    logic [NumGpio-1:0] gpio_prev;
    logic [NumGpio-1:0] irq_events;

    // =========================================================================
    // Wishbone to Simple Bus Adapter
    // =========================================================================

    wb2simple u_wb2simple (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .wb_m2s_i   (wb_m2s_i),
        .wb_s2m_o   (wb_s2m_o),
        .reg_we     (reg_we),
        .reg_re     (reg_re),
        .reg_addr   (reg_addr),
        .reg_wdata  (reg_wdata),
        .reg_rdata  (reg_rdata)
    );

    // =========================================================================
    // Address Routing
    // =========================================================================
    // addr[9:8] = 00: CSR block (0x000..0x01F)
    // addr[9:8] != 00: Per-bit region (0x100..0x27C)

    logic is_perbit_region;
    assign is_perbit_region = |reg_addr[9:8];

    // CSR block only gets accesses to the CSR region
    assign csr_we = reg_we && !is_perbit_region;
    assign csr_re = reg_re && !is_perbit_region;

    // Read data mux: CSR region returns CSR data, per-bit region returns 0
    assign reg_rdata = is_perbit_region ? '0 : csr_rdata;

    // =========================================================================
    // CSR Block
    // =========================================================================

    gpio_csr_reg_top #(
        .ResetType (rdl_subreg_pkg::ActiveLowAsync)
    ) u_csr (
        .clk       (clk_i),
        .rst       (rst_ni),
        .reg_we    (csr_we),
        .reg_re    (csr_re),
        .reg_addr  (reg_addr[BlockAw-1:0]),
        .reg_wdata (reg_wdata),
        .reg_rdata (csr_rdata),
        .reg2hw    (reg2hw),
        .hw2reg    (hw2reg)
    );

    // =========================================================================
    // GPIO Output Bit Controller
    // =========================================================================

    // Direct write: CPU writes to GPIO_OUT CSR register
    logic direct_out_we;
    assign direct_out_we = csr_we && (reg_addr[BlockAw-1:0] == GPIO_CSR_GPIO_OUT_OFFSET);

    // Per-bit write: any write to the per-bit region
    logic perbit_we;
    assign perbit_we = reg_we && is_perbit_region;

    gpio_bit_ctrl #(
        .NumGpio (NumGpio)
    ) u_bit_ctrl (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .direct_we_i    (direct_out_we),
        .direct_wdata_i (reg_wdata),
        .perbit_we_i    (perbit_we),
        .perbit_addr_i  (reg_addr[9:2]),
        .gpio_out_o     (gpio_out)
    );

    // Feed GPIO output back to CSR for read-back
    assign hw2reg.gpio_out.d = {{(32-NumGpio){1'b0}}, gpio_out};

    // GPIO output pins
    assign gpio_o = gpio_out;

    // =========================================================================
    // Output Enable
    // =========================================================================

    assign gpio_oe_o = reg2hw.gpio_oe.q[NumGpio-1:0];

    // =========================================================================
    // Input Synchronization (2-stage)
    // =========================================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_sync_q1 <= '0;
            gpio_sync_q2 <= '0;
        end else begin
            gpio_sync_q1 <= gpio_i;
            gpio_sync_q2 <= gpio_sync_q1;
        end
    end

    // Feed synchronized input to CSR (masked by input enable)
    logic [NumGpio-1:0] gpio_ie;
    assign gpio_ie = reg2hw.gpio_ie.q[NumGpio-1:0];
    assign hw2reg.gpio_in.d = {{(32-NumGpio){1'b0}}, gpio_sync_q2 & gpio_ie};

    // =========================================================================
    // Interrupt Event Detection
    // =========================================================================

    // Previous input value for edge detection
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_prev <= '0;
        end else begin
            gpio_prev <= gpio_sync_q2;
        end
    end

    // Per-pin event generation
    logic [NumGpio-1:0] irq_type;   // 1=edge, 0=level
    logic [NumGpio-1:0] irq_edge;   // 1=rising/active-high, 0=falling/active-low
    assign irq_type = reg2hw.irq_type.q[NumGpio-1:0];
    assign irq_edge = reg2hw.irq_edge.q[NumGpio-1:0];

    always_comb begin
        for (int i = 0; i < NumGpio; i++) begin
            if (irq_type[i]) begin
                // Edge-triggered
                if (irq_edge[i])
                    irq_events[i] = gpio_sync_q2[i] && !gpio_prev[i];  // Rising edge
                else
                    irq_events[i] = !gpio_sync_q2[i] && gpio_prev[i];  // Falling edge
            end else begin
                // Level-triggered
                if (irq_edge[i])
                    irq_events[i] = gpio_sync_q2[i];   // Active high
                else
                    irq_events[i] = !gpio_sync_q2[i];  // Active low
            end
        end
    end

    // =========================================================================
    // IRQ Status (Sticky, W1C via PeakRDL)
    // =========================================================================

    // OR-set: feed back current status OR'd with new events
    logic [31:0] irq_status_q;
    assign irq_status_q = reg2hw.irq_status.q;

    assign hw2reg.irq_status.d  = irq_status_q | {{(32-NumGpio){1'b0}}, irq_events};
    assign hw2reg.irq_status.de = |irq_events;

    // IRQ output: OR of (status & enable)
    logic [31:0] irq_enable_q;
    assign irq_enable_q = reg2hw.irq_enable.q;
    assign irq_o = |(irq_status_q & irq_enable_q);

    // =========================================================================
    // Unused Signal Handling
    // =========================================================================

    logic unused;
    assign unused = &{reg_addr[31:10], reg2hw.gpio_out};

endmodule
