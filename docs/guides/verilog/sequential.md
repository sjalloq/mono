# Sequential Logic

## Blocking vs Non-blocking

- **Sequential logic**: Use non-blocking assignments (`<=`)
- **Combinational logic**: Use blocking assignments (`=`)
- Never mix assignment types within a block

## Register Template

```systemverilog
logic [7:0] foo_d, foo_q;

// Combinational: compute next value
always_comb begin
  foo_d = some_computation;
end

// Sequential: just the register
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    foo_q <= '0;
  end else begin
    foo_q <= foo_d;
  end
end
```

## Register with Enable

```systemverilog
logic [7:0] foo_d, foo_q;
logic       foo_en;

always_comb begin
  foo_d  = new_value;
  foo_en = should_update;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    foo_q <= '0;
  end else if (foo_en) begin
    foo_q <= foo_d;
  end
end
```

## Reset Style

Use asynchronous active-low reset:

```systemverilog
// Preferred style
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    q <= '0;
  end else begin
    q <= d;
  end
end
```

Use `or` not comma in sensitivity list (both legal, `or` preferred).

## No Logic in always_ff

Keep `always_ff` blocks simple. Move logic to `always_comb`:

```systemverilog
// BAD
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    count_q <= '0;
  end else begin
    count_q <= enable ? count_q + 1 : count_q;  // Logic in always_ff
  end
end

// GOOD
always_comb begin
  count_d = enable ? count_q + 1 : count_q;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    count_q <= '0;
  end else begin
    count_q <= count_d;
  end
end
```

## Multiple Registers

Group related registers:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= StIdle;
    addr_q  <= '0;
    data_q  <= '0;
    valid_q <= '0;
  end else begin
    state_q <= state_d;
    addr_q  <= addr_d;
    data_q  <= data_d;
    valid_q <= valid_d;
  end
end
```

## Latches

Avoid latches. Use flip-flops instead.

If a latch is absolutely necessary:
```systemverilog
always_latch begin
  if (enable) begin
    q <= d;
  end
end
```

## Delays

Do not use `#delay` in synthesizable code. No `#0`, no `#1`.

## Pipeline Example

```systemverilog
logic [31:0] data_d, data_q, data_q2, data_q3;

assign data_d = input_data;

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    data_q  <= '0;
    data_q2 <= '0;
    data_q3 <= '0;
  end else begin
    data_q  <= data_d;
    data_q2 <= data_q;
    data_q3 <= data_q2;
  end
end

assign output_data = data_q3;  // 3-cycle latency
```
