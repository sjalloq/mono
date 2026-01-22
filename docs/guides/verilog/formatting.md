# Formatting

## Line Length

Maximum 100 characters per line.

## Indentation

- Two spaces per level
- Four spaces for line continuation
- No tabs

## Begin/End

Use `begin`/`end` unless the whole statement fits on one line:

```systemverilog
// Multi-line requires begin/end
always_ff @(posedge clk) begin
  q <= d;
end

// Single line may omit
always_ff @(posedge clk) q <= d;

// Wrapped without begin/end is WRONG
always_ff @(posedge clk)
  q <= d;  // Bad
```

`begin` on same line as keyword, `end` on its own line:

```systemverilog
if (condition) begin
  foo = bar;
end else begin
  foo = baz;
end
```

## Spacing

### Operators

Space around binary operators:

```systemverilog
assign a = ((addr & mask) == My_addr) ? b[1] : ~b[0];
```

### Commas

Space after commas:

```systemverilog
bus = {addr, parity, data};
my_module u_inst (.a(a), .b(b));
```

### Keywords

Space after keywords:

```systemverilog
if (condition) begin
always_ff @(posedge clk) begin
```

### No Space Before Function Calls

```systemverilog
process_packet(pkt);   // Good
process_packet (pkt);  // Bad
```

## Line Wrapping

Four-space continuation indent:

```systemverilog
assign result = condition_a &&
    condition_b &&
    condition_c;

assign addr = function_with_many_params(
    param1, param2, param3,
    param4, param5
);
```

Or align with opening delimiter:

```systemverilog
assign result = condition_a &&
                condition_b &&
                condition_c;
```

## Tabular Alignment

Align similar declarations:

```systemverilog
logic [7:0]  my_interface_data;
logic [15:0] my_interface_address;
logic        my_interface_enable;

logic       another_signal;
logic [7:0] something_else;
```

## Comments

C++ style preferred:

```systemverilog
// This comment describes the following code
module foo;
  // ...
endmodule

localparam bit Val = 1;  // Describes this line
```

Section headers:

```systemverilog
////////////////
// Controller //
////////////////

///////////////////////
// Main ALU Datapath //
///////////////////////
```

## Case Items

No space before colon, space after:

```systemverilog
unique case (state)
  StInit:   foo = bar;
  StError:  foo = baz;
  default: begin
    foo = qux;
  end
endcase
```

## Labels

Space around colons in labels:

```systemverilog
begin : my_block
end : my_block
```
