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