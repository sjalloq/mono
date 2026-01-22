# Naming Conventions

## Summary

| Construct | Style |
|-----------|-------|
| Modules, packages, interfaces | `lower_snake_case` |
| Instance names | `lower_snake_case` |
| Signals (nets and ports) | `lower_snake_case` |
| Variables, functions, tasks | `lower_snake_case` |
| Named code blocks | `lower_snake_case` |
| \`define macros | `ALL_CAPS` |
| Module parameters | `UpperCamelCase` |
| Constants (localparam) | `ALL_CAPS` or `UpperCamelCase` |
| Enumeration types | `lower_snake_case_e` |
| Other typedef types | `lower_snake_case_t` |
| Enumeration values (states) | `UpperCamelCase` |

## Suffixes

| Suffix | Arena | Meaning |
|--------|-------|---------|
| `_e` | typedef | Enumerated type |
| `_t` | typedef | Other typedefs |
| `_n` | signal | Active low |
| `_n`, `_p` | signal | Differential pair |
| `_d`, `_q` | signal | Input/output of register |
| `_q2`, `_q3` | signal | Pipelined (2, 3 cycles delay) |
| `_i`, `_o`, `_io` | signal | Module input, output, bidirectional |

### Combining Suffixes

- No extra underscores between suffixes: `_ni` not `_n_i`
- Active low `_n` comes first
- Direction `_i`, `_o`, `_io` comes last
- `_d` and `_q` don't need to propagate to module boundaries

Examples:
```systemverilog
input  logic rst_ni,       // Active-low reset input
output logic rd_no,        // Active-low read output
input  logic data_valid_i, // Data valid input
output logic ready_o,      // Ready output
```

## Module Port Example

```systemverilog
module example (
  input  logic        clk_i,
  input  logic        rst_ni,         // Active low reset

  // Writer interface
  input  logic [15:0] data_i,
  input  logic        valid_i,
  output logic        ready_o,

  // Bidirectional bus
  inout  logic [7:0]  driver_io,

  // Differential pair
  output logic        lvds_po,        // Positive
  output logic        lvds_no         // Negative (active low naming)
);
```

## Internal Signal Naming

```systemverilog
logic valid_d, valid_q;           // Register input/output
logic valid_q2, valid_q3;         // Pipelined versions

assign valid_d = valid_i;

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    valid_q  <= '0;
    valid_q2 <= '0;
    valid_q3 <= '0;
  end else begin
    valid_q  <= valid_d;
    valid_q2 <= valid_q;
    valid_q3 <= valid_q2;
  end
end
```

## Clocks

- Main clock: `clk` or `clk_i`
- Additional clocks: `clk_<domain>` (e.g., `clk_dram`, `clk_axi`)
- Signals in a clock domain share a prefix: `dram_data`, `dram_valid`

## Resets

- Active-low, asynchronous by default
- Main reset: `rst_n` or `rst_ni`
- Domain-specific: `rst_<domain>_n` (e.g., `rst_dram_n`)

## Prefixes

Use common prefixes for signal groups:

```systemverilog
// AXI-Stream interface
logic        foo_valid;
logic        foo_ready;
logic [31:0] foo_data;

// Memory interface
logic [7:0]  mem_addr;
logic [15:0] mem_wdata;
logic        mem_we;
logic [15:0] mem_rdata;
```

## Enumerations

```systemverilog
// State machine states
typedef enum logic [1:0] {
  StIdle,
  StProcess,
  StDone
} state_e;

// Opcode constants
typedef enum logic [7:0] {
  OP_ADD  = 8'h01,
  OP_SUB  = 8'h02,
  OP_LOAD = 8'h10
} opcode_e;
```

## Constants

```systemverilog
// Package-level constants
package my_pkg;
  parameter int unsigned NUM_CORES = 4;
  parameter int unsigned ADDR_WIDTH = 32;
endpackage

// Module-level constants
localparam int unsigned FIFO_DEPTH = 16;
localparam int unsigned COUNTER_MAX = 1000;

// Include units in name
localparam int unsigned TIMEOUT_CYCLES = 1000;
localparam int unsigned BUFFER_SIZE_BYTES = 4096;
```

## Parameters

```systemverilog
module fifo #(
  parameter int unsigned Depth = 16,      // UpperCamelCase
  parameter int unsigned Width = 8,
  localparam int unsigned Aw = $clog2(Depth)  // Derived
) (
  // ...
);
```
