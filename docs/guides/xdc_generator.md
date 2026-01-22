# XDC Generator

A FuseSoC generator that creates Xilinx XDC constraint files by combining board pin definitions (YAML) with SystemVerilog port declarations.

## Overview

The XDC generator solves the problem of maintaining constraints separately from RTL by:
1. Defining board pins once in a YAML file
2. Parsing the toplevel SV module to discover ports
3. Automatically matching SV ports to board pins
4. Generating XDC with proper PACKAGE_PIN, IOSTANDARD, timing constraints, etc.

## Architecture

```
hw/boards/<board>/board.yaml  ───┐
                                 ├──► xdc_generator.py ──► constraints.xdc
hw/projects/<proj>/rtl/top.sv ───┘
```

### Components

| File | Purpose |
|------|---------|
| `mono/tools/xdc/__init__.py` | Package exports |
| `mono/tools/xdc/board.py` | Board YAML parsing and data structures |
| `mono/tools/xdc/sv_parser.py` | **SystemVerilog port extraction (needs pyslang rewrite)** |
| `mono/tools/xdc/generator.py` | XDC generation logic and port matching |
| `hw/generators/xdc_generator.py` | FuseSoC generator entry point |

## Board YAML Schema

```yaml
device: xc7a35tfgg484-2

clocks:
  clk100:
    pin: H4
    frequency: 100e6
    iostandard: LVCMOS33

pins:
  # Simple pin
  reset_n:
    pin: A1
    iostandard: LVCMOS33
    pullup: true

  # Array of pins (indexed like user_led[0], user_led[1])
  user_led:
    - { pin: Y6, iostandard: LVCMOS33 }
    - { pin: AB5, iostandard: LVCMOS33 }

  # Bus with subsignals
  usb_fifo:
    clk:
      pin: W19
      iostandard: LVCMOS33
    data:
      pins: [N13, N14, N15, ...]  # Multi-bit bus
      iostandard: LVCMOS33
      slew: FAST
    rxf_n:
      pin: AB8
      iostandard: LVCMOS33

timing:
  usb_fifo:
    clk: usb_fifo.clk
    input_delay:
      min: 6.5
      max: 7.0
      ports: [data, rxf_n, txe_n]
    output_delay:
      min: 4.8
      max: 1.0
      ports: [data, be, rd_n, wr_n]

  false_paths:
    - { from: clk100, to: usb_fifo.clk }

bitstream:
  CFGBVS: Vcco
  CONFIG_VOLTAGE: "3.3"
```

## Data Structures (board.py)

```python
@dataclass
class BoardPin:
    pin: str           # Package pin (e.g., "H4")
    iostandard: str    # IO standard (e.g., "LVCMOS33")
    slew: str | None   # SLOW/FAST
    pullup: bool
    pulldown: bool
    drive: int | None  # Drive strength

@dataclass
class BoardBus:
    pins: list[str]    # Multiple pins for vector signals
    iostandard: str
    slew: str | None
    # ... same attributes as BoardPin

@dataclass
class BoardClock:
    pin: str
    frequency: float
    iostandard: str
    name: str | None

@dataclass
class Board:
    device: str
    clocks: dict[str, BoardClock]
    pins: dict[str, BoardPin | list[BoardPin] | dict[str, BoardPin | BoardBus]]
    timing: dict[str, TimingConstraint]
    false_paths: list[FalsePath]
    bitstream: dict[str, str]
```

## SV Port Parser (sv_parser.py) - NEEDS REWRITE WITH PYSLANG

The current implementation uses regex, which is fragile. It needs to be rewritten using pyslang.

### Current Interface

```python
@dataclass
class SVPort:
    name: str          # Port name
    direction: str     # "input", "output", "inout"
    width: int         # 1 for scalar, >1 for vector
    msb: int | None    # For [msb:lsb] vectors
    lsb: int | None

def parse_sv_ports(sv_file: Path) -> list[SVPort]:
    """Parse SV file and return list of port declarations."""
    ...
```

### What the Parser Must Handle

1. **ANSI-style ports** (declarations in module header):
   ```systemverilog
   module top (
       input  logic        clk,
       input  logic [31:0] data_i,
       output logic [7:0]  result_o,
       inout  wire  [15:0] bidir
   );
   ```

2. **Parameterized widths** (evaluate if possible, or flag as unknown):
   ```systemverilog
   module top #(parameter WIDTH = 32) (
       input  logic [WIDTH-1:0] data
   );
   ```

3. **Non-ANSI style** (declarations in module body):
   ```systemverilog
   module top (clk, data, result);
       input        clk;
       input [31:0] data;
       output [7:0] result;
   endmodule
   ```

4. **Interface ports** (may need special handling or skip):
   ```systemverilog
   module top (
       axi_if.master m_axi,
       input logic   clk
   );
   ```

### Suggested pyslang Implementation

```python
import pyslang

def parse_sv_ports(sv_file: Path) -> list[SVPort]:
    """Parse SV file using pyslang and extract port declarations."""
    tree = pyslang.SyntaxTree.fromFile(str(sv_file))
    compilation = pyslang.Compilation()
    compilation.addSyntaxTree(tree)

    ports = []
    # Find module definition
    # Iterate over ports
    # Extract name, direction, width
    # Handle parameters if needed

    return ports
```

## Port Matching Logic (generator.py)

The `XDCGenerator.map_ports()` method matches SV ports to board pins:

1. **Explicit overrides** via `pin_map` parameter
2. **Direct name match**: `clk100` SV port → `clk100` board clock/pin
3. **Subsignal expansion**: `usb_fifo_data` SV port → `usb_fifo.data` board bus
4. **Array matching**: `user_led[0]` → `user_led` array index 0
5. **Width validation**: Vector port width must match bus pin count

```python
gen = XDCGenerator.from_files(board_yaml, sv_file)
gen.map_ports(pin_overrides={"custom_name": "usb_fifo.clk"})
gen.generate("output.xdc")
```

## FuseSoC Integration

### Generator Registration (hw/generators/generators.core)

```yaml
generators:
  xdc_generator:
    interpreter: python3
    command: xdc_generator.py
    description: Generate XDC constraints from board YAML and SV ports
```

### Usage in Project Core File

```yaml
generate:
  xdc:
    generator: xdc_generator
    parameters:
      board: board.yaml        # Path to board definition
      toplevel: rtl/top.sv     # Path to toplevel SV file
      output: project.xdc      # Output filename
      pin_map:                 # Optional explicit mappings
        my_clock: clk100
        my_data: usb_fifo.data
```

## Generated XDC Output

```tcl
# Auto-generated XDC constraints
# Device: xc7a35tfgg484-2

# Bitstream Configuration
set_property CFGBVS Vcco [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Clock Constraints
create_clock -period 10.000 -name clk100 [get_ports {clk100}]

# Pin Assignments
set_property PACKAGE_PIN H4 [get_ports {clk100}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk100}]
set_property PACKAGE_PIN N13 [get_ports {usb_fifo_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {usb_fifo_data[0]}]
set_property SLEW FAST [get_ports {usb_fifo_data[0]}]
# ... more pins ...

# Timing Constraints
set_input_delay -clock usb_fifo_clk -min 6.5 [get_ports {usb_fifo_data[*]}]
set_input_delay -clock usb_fifo_clk -max 7.0 [get_ports {usb_fifo_data[*]}]

# False Paths
set_false_path -from [get_clocks clk100] -to [get_clocks usb_fifo_clk]
```

## Task for Parallel Agent

**Rewrite `mono/tools/xdc/sv_parser.py` using pyslang:**

1. Keep the same interface: `parse_sv_ports(sv_file: Path) -> list[SVPort]`
2. Keep the `SVPort` dataclass unchanged
3. Use pyslang to properly parse SV syntax
4. Handle ANSI and non-ANSI port styles
5. Handle parameterized widths (evaluate constants, flag unknowns)
6. Skip or flag interface ports appropriately
7. Add proper error handling for parse failures

The rest of the XDC generator (`board.py`, `generator.py`) should work unchanged once the parser returns correct `SVPort` objects.
