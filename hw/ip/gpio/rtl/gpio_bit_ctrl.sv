// SPDX-License-Identifier: BSD-2-Clause
// GPIO Per-Bit Control
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Manages the GPIO output register with support for:
// - Direct write from CSR bus (GPIO_OUT register)
// - Per-bit SET/CLEAR/TOGGLE via address-decoded writes
//
// Per-bit address decode:
//   bank = addr[9:7]: 010=SET, 011=CLR, 100=TOGGLE
//   gpio_idx = addr[6:2]: selects which GPIO bit

module gpio_bit_ctrl #(
    parameter int unsigned NumGpio = 32,
    parameter int unsigned DW      = 32
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    // Direct write from CSR bus (GPIO_OUT register write)
    input  logic             direct_we_i,
    input  logic [DW-1:0]    direct_wdata_i,

    // Per-bit access bus signals (addr bits [9:2] from bus address)
    input  logic             perbit_we_i,
    input  logic [9:2]       perbit_addr_i,

    // GPIO output value
    output logic [NumGpio-1:0] gpio_out_o
);

    // =========================================================================
    // Per-bit address decode
    // =========================================================================

    logic [2:0] bank;
    logic [4:0] gpio_idx;

    assign bank     = perbit_addr_i[9:7];
    assign gpio_idx = perbit_addr_i[6:2];

    // Bank encodings
    localparam logic [2:0] BANK_SET    = 3'b010;  // 0x100..0x17C
    localparam logic [2:0] BANK_CLR    = 3'b011;  // 0x180..0x1FC
    localparam logic [2:0] BANK_TOGGLE = 3'b100;  // 0x200..0x27C

    logic perbit_valid;
    // When NumGpio==32 all 5-bit indices are valid; otherwise check range
    assign perbit_valid = perbit_we_i && (NumGpio >= 32 || gpio_idx < NumGpio[4:0]);

    // =========================================================================
    // GPIO Output Register
    // =========================================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_out_o <= '0;
        end else if (direct_we_i) begin
            // Direct write takes priority (full 32-bit write)
            gpio_out_o <= direct_wdata_i[NumGpio-1:0];
        end else if (perbit_valid) begin
            case (bank)
                BANK_SET:    gpio_out_o[gpio_idx] <= 1'b1;
                BANK_CLR:    gpio_out_o[gpio_idx] <= 1'b0;
                BANK_TOGGLE: gpio_out_o[gpio_idx] <= ~gpio_out_o[gpio_idx];
                default:     ; // ignore invalid banks
            endcase
        end
    end

endmodule
