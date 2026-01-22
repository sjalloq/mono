# Combinational Logic

## always_comb

Use `always_comb` for combinational logic. Use blocking assignments (`=`).

```systemverilog
always_comb begin
  result = a + b;
end
```

## Prefer assign

Use `assign` statements where practical:

```systemverilog
assign result = condition ? value_a : value_b;
assign sum = a + b;
assign masked = data & mask;
```

## Case Statements

Use `unique case` with a `default`:

```systemverilog
always_comb begin
  unique case (select)
    2'b00:   out = a;
    2'b01:   out = b;
    2'b10:   out = c;
    2'b11:   out = d;
    default: out = '0;
  endcase
end
```

### Default Values Pattern

Set defaults before the case statement:

```systemverilog
always_comb begin
  // Defaults
  out_a = '0;
  out_b = '0;
  out_c = '0;

  unique case (state_q)
    StateA: out_a = foo;
    StateB: out_b = bar;
    StateC: out_c = baz;
    default: ;  // Empty default OK with defaults above
  endcase
end
```

### Wildcards

- Use `case` for exact matching
- Use `case inside` for wildcards (preferred)
- Use `casez` for Verilog-2001 compatibility
- Never use `casex`

```systemverilog
// Preferred
always_comb begin
  unique case (opcode) inside
    4'b0???: result = alu_result;
    4'b1000: result = load_result;
    default: result = '0;
  endcase
end
```

## Ternary Expressions

Parenthesize nested ternaries in the true condition:

```systemverilog
// Good - parentheses clarify
assign foo = cond_a ? (cond_b ? x : y) : z;

// Good - formatting shows priority
assign foo = cond_a ? a :
             cond_b ? b :
             cond_c ? c : default_val;

// Bad - ambiguous
assign foo = cond_a ? cond_b ? x : y : z;
```

## Signal Widths

Be explicit about widths:

```systemverilog
// Good
localparam logic [3:0] VALUE = 4'd4;
assign foo = 8'd2;

// Bad
localparam logic [3:0] VALUE = 4;
assign foo = 2;
```

### Width Matching

Match widths explicitly:

```systemverilog
// Good
my_module i_mod (
  .wide_input({16'd0, narrow_signal})
);

// Bad - implicit extension
my_module i_mod (
  .wide_input(narrow_signal)
);
```

### Multi-bit in Boolean Context

Don't use multi-bit signals directly in boolean context:

```systemverilog
logic [3:0] a;

// Good
if (a != '0) ...
assign valid = (count != '0);

// Bad
if (a) ...
assign valid = count;
```

## Don't Use X

Don't assign `X` to indicate don't care. Use assertions instead:

```systemverilog
// Bad
assign out = valid ? data : 'x;

// Good
assign out = valid ? data : '0;
`ASSERT(OutValidWhenUsed, use_out |-> valid)
```

## Generate Constructs

Always name generated blocks:

```systemverilog
// Conditional
if (UseFeature) begin : gen_feature
  // ...
end else begin : gen_no_feature
  // ...
end

// Loop
for (genvar i = 0; i < N; i++) begin : gen_instances
  my_mod #(.Index(i)) u_inst (...);
end
```

Do not use `generate`/`endgenerate` keywords.
