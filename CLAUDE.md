# Project: mono

## Quick Commands

```bash
source sourceme           # Activate venv (creates if needed)
source sourceme --clean   # Recreate venv from scratch
make docs                 # Build Sphinx documentation
```

## Directory Structure

- `docs/source/` - Sphinx functional specification
- `docs/guides/` - Markdown guides (testbenches, tools)
- `docs/plans/` - Implementation plans and tasks

## Key Docs

- Functional spec: `docs/source/`
- SV conversion strategy: `docs/source/sv_conversion.rst`

## Conventions

- Hand-written SystemVerilog: `.sv` extension
- Generated Verilog (from Migen): `.v` extension
- Fusesoc core files: `.core` (YAML format)

## Tools

- **fusesoc**: HDL package manager and build system
- **uv**: Python package manager (used for venv)
- **verilator**: Preferred simulator

Tools are normally loaded via Environment Modules.

## Migen Netlister

FuseSoC generator for converting Migen/LiteX modules to Verilog with clean port names.

**Key files:**
- `hw/generators/migen_netlister.py` - FuseSoC generator
- `mono/migen/netlister.py` - `MigenWrapper` base class with `wrap_endpoint()`
- `mono/gateware/wrappers/` - Wrapper implementations

**Usage in core files:**
```yaml
generate:
  netlist:
    generator: migen_netlister
    parameters:
      module: mono.gateware.wrappers.usb_core
      class: USBCoreWrapper
      name: usb_core
      args:                    # Passed to wrapper __init__
        num_ports: 2
        clk_freq: 100000000
```

**Creating wrappers:**
```python
from mono.migen import MigenWrapper

class MyWrapper(MigenWrapper):
    def __init__(self, some_param=default):
        super().__init__()
        self.submodules.inner = SomeMigenModule(some_param)
        self.wrap_endpoint(self.inner.sink, "sink", direction="sink")
        self.wrap_endpoint(self.inner.source, "source", direction="source")
```

Run with: `fusesoc run --target=default --tool=verilator <core-vlnv>`