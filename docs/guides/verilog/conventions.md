# Design Conventions

## Declare All Signals

All signals must be explicitly declared. No inferred nets.

## Use `logic`

Use `logic` for all signals:

```systemverilog
logic [31:0] data;
logic        valid;
```

Exceptions:
- `wire` for bidirectional (`inout`) ports
- `wire` for continuous assignment shorthand

```systemverilog
wire [7:0] sum = a + b;  // Declare + assign (continuous)
```

## Logical vs Bitwise Operators

**Logical** (`!`, `&&`, `||`, `==`, `!=`) for control flow and boolean tests.
**Bitwise** (`~`, `&`, `|`, `^`) for data manipulation.

```systemverilog
// Logical for control
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin          // Logical NOT
    reg_q <= '0;
  end
end

if (bool_a || (bool_b && !bool_c)) begin  // Logical
  x = 1'b1;
end

assign enable = (state_q == StActive) && valid_i;  // Logical

// Bitwise for data
assign masked = data & mask;      // Bitwise AND
assign parity = ^data;            // Reduction XOR
assign inverted = ~data;          // Bitwise NOT
assign combined = (a & ~b) | c;   // Bitwise expression
```

Common mistake:

```systemverilog
// Bad - bitwise in control
if (~rst_ni) begin  // Should be !rst_ni
if (a & b) begin    // Should be a && b for logic

// Bad - logical on data
assign y = (a && !b) || c;  // Should be (a & ~b) | c
```

## Packed Arrays (Little-Endian)

```systemverilog
logic [31:0] word;        // Bit 31 is MSB
logic [7:0][3:0] packed;  // 8 nibbles
```

## Unpacked Arrays (Big-Endian)

```systemverilog
logic [15:0] mem[256];      // 256 entries, index 0 first
logic [15:0] mem[0:255];    // Equivalent
```

## Active-Low Signals

Use `_n` suffix:

```systemverilog
input  logic rst_ni,      // Active-low reset input
output logic chip_sel_no  // Active-low chip select output
```

## Prefer Registered Outputs

Register module outputs when practical for timing closure.

## SystemVerilog Constructs

Prefer:
- `always_comb` over `always @*`
- `always_ff` over `always @(posedge clk)`
- `logic` over `reg` and `wire`
- Parameters over `` `define``

## Functions

- Declare as `automatic`
- Explicit types on all arguments and return
- No `output`, `inout`, or `ref` arguments
- Use `return` statement

```systemverilog
function automatic logic [7:0] add_saturate(
  logic [7:0] a,
  logic [7:0] b
);
  logic [8:0] sum;
  sum = {1'b0, a} + {1'b0, b};
  return (sum[8]) ? 8'hFF : sum[7:0];
endfunction
```

## Avoid

- Interfaces (discouraged)
- `alias` statement
- Hierarchical references in RTL
- `X` assignments (use assertions instead)
- Latches (use flip-flops)
- `#delay` in synthesizable code
- `casex` (use `case inside`)
- `full_case`/`parallel_case` pragmas
