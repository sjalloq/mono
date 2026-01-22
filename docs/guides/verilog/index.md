# SystemVerilog Coding Guidelines

Based on the [lowRISC Verilog Coding Style Guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).

## Critical Rules

These are the most important rules that must be followed:

### FSM Structure (see [fsm.md](fsm.md))

**No logic in `always_ff` blocks except reset.** The register block should only contain:
```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    state_q <= StIdle;
    foo_q   <= '0;
  end else begin
    state_q <= state_d;
    foo_q   <= foo_d;
  end
end
```

All logic must be in `always_comb`:
```systemverilog
always_comb begin
  state_d = state_q;  // Default: hold state
  foo_d   = '0;       // Default values for all outputs

  unique case (state_q)
    StIdle: begin
      // ...
    end
    default: ;
  endcase
end
```

### Signal Naming (see [naming.md](naming.md))

| Suffix | Meaning |
|--------|---------|
| `_i`, `_o`, `_io` | Module input, output, bidirectional |
| `_d`, `_q` | Combinational (next), registered (current) |
| `_n` | Active low |
| `_e` | Enumerated type |
| `_t` | Other typedef |

Combine suffixes without extra underscores: `rst_ni` (active-low input), `rd_no` (active-low output).

### Operators (see [conventions.md](conventions.md))

Use **logical** operators (`!`, `&&`, `||`) for logic/control flow.
Use **bitwise** operators (`~`, `&`, `|`, `^`) for data manipulation.

```systemverilog
// Logical for control
if (!rst_ni) ...
if (valid && ready) ...
assign enable = (state_q == StActive) && !pause;

// Bitwise for data
assign masked_data = data & mask;
assign parity = ^data;
```

## Topic Guides

| File | Contents |
|------|----------|
| [fsm.md](fsm.md) | Finite State Machine structure |
| [naming.md](naming.md) | Signal naming, suffixes, prefixes |
| [sequential.md](sequential.md) | Registers, blocking vs non-blocking |
| [combinational.md](combinational.md) | Combinational logic, case statements |
| [modules.md](modules.md) | Module declaration, instantiation |
| [formatting.md](formatting.md) | Indentation, spacing, comments |
| [conventions.md](conventions.md) | Design conventions, logical vs bitwise |

## Quick Reference

```systemverilog
module example #(
  parameter int unsigned Width = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] data_i,
  input  logic             valid_i,
  output logic [Width-1:0] data_o,
  output logic             valid_o
);

  typedef enum logic [1:0] {
    StIdle,
    StProcess,
    StDone
  } state_e;

  state_e state_q, state_d;
  logic [Width-1:0] data_q, data_d;
  logic valid_q, valid_d;

  // Combinational logic
  always_comb begin
    state_d = state_q;
    data_d  = data_q;
    valid_d = '0;

    unique case (state_q)
      // StIdle: Wait for valid input
      StIdle: begin
        if (valid_i) begin
          data_d  = data_i;
          state_d = StProcess;
        end
      end
      // StProcess: Process data
      StProcess: begin
        state_d = StDone;
      end
      // StDone: Output result
      StDone: begin
        valid_d = '1;
        state_d = StIdle;
      end
      default: state_d = StIdle;
    endcase
  end

  // Registers (no logic except reset)
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

  assign data_o  = data_q;
  assign valid_o = valid_q;

endmodule
```
