# Finite State Machines

State machines use an enum to define states and are implemented with **two process blocks**: a combinational block and a clocked block.

## Structure

Every state machine has three parts:

1. An **enum** that declares the states
2. A **combinational** process block that decodes state to produce next state and outputs
3. A **clocked** process block that updates state from next state

## The Critical Rule

**No logic except reset in the `always_ff` block.**

The clocked block should ONLY contain:
- Reset value assignments
- `signal_q <= signal_d` assignments

All computation, muxing, and conditional logic belongs in `always_comb`.

## Enumerating States

```systemverilog
typedef enum logic [2:0] {
  StIdle,
  StFrameStart,
  StProcess,
  StDone
} my_state_e;

my_state_e state_q, state_d;
```

- Use `typedef enum logic [N:0]` with explicit width
- States use `UpperCamelCase`
- Type name uses `snake_case_e` suffix
- Idle state named `StIdle` or `Idle`
- Prefix states to distinguish multiple FSMs: `StRdIdle`, `StWrIdle`

## Combinational Block

```systemverilog
always_comb begin
  // Default assignments FIRST
  state_d = state_q;  // Hold current state by default
  foo_d   = '0;
  bar_d   = '0;

  unique case (state_q)
    // StIdle: Wait for start signal
    StIdle: begin
      if (start_i) begin
        state_d = StProcess;
        foo_d   = init_value;
      end
    end
    // StProcess: Main processing state
    StProcess: begin
      foo_d = compute_something;
      if (done_condition) begin
        state_d = StDone;
      end
    end
    // StDone: Output results
    StDone: begin
      bar_d   = result;
      state_d = StIdle;
    end
    default: state_d = StIdle;
  endcase
end
```

Rules:
- Set **default values** for ALL outputs before the case statement
- Default for `state_d` is `state_q` (hold state)
- Comment each state describing its function
- Use `unique case`
- Always include `default` case

## Clocked Block

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= StIdle;
    foo_q   <= '0;
    bar_q   <= '0;
  end else begin
    state_q <= state_d;
    foo_q   <= foo_d;
    bar_q   <= bar_d;
  end
end
```

This block should be trivial - just reset values and `_q <= _d` assignments.

## Bad Examples

### Logic in always_ff (WRONG)

```systemverilog
// BAD - logic in clocked block
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    data_q <= '0;
  end else begin
    data_q <= enable ? data_i : data_q;  // WRONG: mux in always_ff
  end
end
```

Should be:

```systemverilog
// GOOD - logic in always_comb
always_comb begin
  data_d = enable ? data_i : data_q;
end

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    data_q <= '0;
  end else begin
    data_q <= data_d;
  end
end
```

### Missing _d signal (WRONG)

```systemverilog
// BAD - direct input to register
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    data_q <= '0;
  end else begin
    data_q <= data_i;  // WRONG: no _d signal
  end
end
```

Should be:

```systemverilog
// GOOD - explicit _d signal
assign data_d = data_i;

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    data_q <= '0;
  end else begin
    data_q <= data_d;
  end
end
```

## Complete Example

```systemverilog
module packet_processor (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [7:0]  data_i,
  input  logic        valid_i,
  output logic [7:0]  data_o,
  output logic        valid_o,
  output logic        ready_o
);

  typedef enum logic [1:0] {
    StIdle,
    StReceive,
    StProcess,
    StOutput
  } state_e;

  state_e state_q, state_d;
  logic [7:0] data_q, data_d;
  logic valid_q, valid_d;
  logic ready;

  // Combinational logic
  always_comb begin
    // Defaults
    state_d = state_q;
    data_d  = data_q;
    valid_d = '0;
    ready   = '0;

    unique case (state_q)
      // StIdle: Wait for input
      StIdle: begin
        ready = '1;
        if (valid_i) begin
          data_d  = data_i;
          state_d = StProcess;
        end
      end
      // StProcess: Transform data
      StProcess: begin
        data_d  = data_q ^ 8'hFF;  // Example: invert
        state_d = StOutput;
      end
      // StOutput: Present result
      StOutput: begin
        valid_d = '1;
        state_d = StIdle;
      end
      default: state_d = StIdle;
    endcase
  end

  // Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
      data_q  <= '0;
      valid_q <= '0;
    end else begin
      state_q <= state_d;
      data_q  <= data_d;
      valid_q <= valid_d;
    end
  end

  // Outputs
  assign data_o  = data_q;
  assign valid_o = valid_q;
  assign ready_o = ready;

endmodule
```
