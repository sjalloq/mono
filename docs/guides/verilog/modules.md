# Module Declaration and Instantiation

## Module Declaration

Use Verilog-2001 full port declaration style:

```systemverilog
module my_module #(
  parameter int unsigned Width = 8,
  parameter int unsigned Depth = 16
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] data_i,
  input  logic             valid_i,
  output logic [Width-1:0] data_o,
  output logic             ready_o
);
  // ...
endmodule
```

Rules:
- Opening parenthesis on same line as `module`
- First port on following line
- Closing parenthesis on its own line, column zero
- Clock ports first, then resets
- Two-space indentation

## Without Parameters

```systemverilog
module simple (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic [7:0] data_i,
  output logic [7:0] data_o
);
```

## With Parameters

```systemverilog
module parameterized #(
  parameter int unsigned Width = 8,
  localparam int unsigned Aw = $clog2(Width)  // Derived
) (
  input  logic [Width-1:0] data_i,
  output logic [Aw-1:0]    addr_o
);
```

## Module Instantiation

Use named ports. All ports must be connected explicitly:

```systemverilog
my_module #(
  .Width(16),
  .Depth(32)
) u_my_module (
  .clk_i   (clk_i),
  .rst_ni  (rst_ni),
  .data_i  (input_data),
  .valid_i (input_valid),
  .data_o  (output_data),
  .ready_o (output_ready)
);
```

### Port Connection Shortcuts

If signal name matches port name:

```systemverilog
my_module u_inst (
  .clk_i,           // Same as .clk_i(clk_i)
  .rst_ni,
  .data_i (transformed_data),  // Different name
  .data_o
);
```

### Unconnected Ports

- Unused outputs: `.port_o()`
- Unused inputs: `.port_i('0)` or `.port_i(WIDTH'd0)`

```systemverilog
my_module u_inst (
  .clk_i,
  .rst_ni,
  .data_i  (8'd0),     // Tied to zero
  .data_o  (),         // Unconnected output
  .valid_o ()
);
```

## Alignment

Align port expressions:

```systemverilog
my_module u_inst (
  .clk_i,
  .rst_ni,
  .short_i     (sig_a),
  .longer_name (sig_b),
  .very_long_signal_name(sig_c)  // No space before (
);
```

No whitespace inside parentheses:

```systemverilog
// Good
.port(signal)

// Bad
.port( signal )
```

## Forbidden

- `.*` wildcard connections
- Positional port connections
- `defparam`
- Recursive instantiation
