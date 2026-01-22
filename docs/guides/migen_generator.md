# FuseSoC Migen Generators

## Generators

A FuseSoC generator allows core files to be generated at build time, along with their artifacts, which  are fed into the FuseSoC dependency tree.

See https://fusesoc.readthedocs.io/en/stable/_sources/user/build_system/generators.rst.txt

## A Migen Netlister

The use case for this generator is to convert Migen source code to Verilog in order to use it within a standard Verilog/SV toplevel.

### Requirements

1. Must accept a dotted Python package path for the parent module.
2. Must accept a class name as the netlister target.
3. Must generate the netlist in a temporary directory, preferably under the repo root, with command line options to keep it for debug purposes.
4. Must construct the relevant FuseSoC metadata and call the relevant generator methods to hand off.

### Migen Issues

In order to avoid Migen renaming toplevel ports, each module that is to be netlisted must be wrapped and should provide helper methods for collecting IO ports.

The Migen `verilog.convert()` method is called to write out a Verilog netlist and it can accept a list of IO ports.  If the netlist wrapper has suitably named methods, `get_io_ports()` or similar, then the wrapper takes on most of the netlisting logic.  In fact, if the wrapper class just has a `netlist()` method, then the generator just has to pass a Path object for the output file name or directory.

As an example, a Migen wrapper might look like:

```python

from package import migen_module
from migen.fhdl.verilog import convert
from migen import Module, Signal

class MigenWrapper(Module):
    def __init__(self):
        self.submodules += mod = migen_module(args)

        # Use Signals as top level IO so they don't get renamed
        self.sig_a = Signal()
        self.sig_b = Signal()

        # Assign submodule signals to top level iO
        self.comb += [
            self.sig_a.eq(mod.sig_a),
            self.sig_b.eq(mod.submod.sig_b),
        ]

    def ios(self):
        '''Return the list or set of signals that convert expects'''
        return [self.sig_a, self.sig_b]

    def netlist(self, name: str, path: Path):
        '''As a first pass grab the ConvOutput object and call the write() method.
        We may have to handle $readmemh init files more intelligently later.'''
        conv = convert(self, ios=self.ios(), name=name)
        vlog = path / f"{name}".v
        conv.write(vlog)

```

I leave it as an exercise for the reader to suggest some suitable Python abstractions that make this nice.  We have an empty Python package in this repo under `<root>/mono/` where we could create any helpful `mono/migen/netlister.py` classes or helpers.

An alternative is that the IO list lives in the core file as part of the spec.  So something like:

```yaml

generate:
    migen_netlist:
        generator: migen_netlister
        parameters:
            module: litex.something.whatever
            class: MyAmazeballsModule
            ios:
                - sig_a
                - sig_b
```

### Writing The Generator

FuseSoC provides a `Generator` base class that handles the boilerplate. The generator script:

1. Receives a YAML config file path as `sys.argv[1]`
2. Processes parameters and generates files
3. Outputs a `.core` file describing the generated artifacts

#### Input Format

FuseSoC creates a YAML config file with this structure:

```yaml
gapi: '1.0'
files_root: /path/to/core/files    # Where source files live
vlnv: ::generated-migen-module:0   # Identifier for generated core
parameters:                         # From the generate: section
  module: litex.something.whatever
  class: MyAmazeballsModule
  ios:
    - sig_a
    - sig_b
```

#### Generator Implementation

```python
#!/usr/bin/env python3
"""Migen to Verilog netlister for FuseSoC."""

from fusesoc.capi2.generator import Generator
from pathlib import Path
import importlib
import sys

class MigenNetlister(Generator):
    def run(self):
        # Extract parameters
        module_path = self.config.get('module')
        class_name = self.config.get('class')
        ios = self.config.get('ios', [])

        if not module_path or not class_name:
            print("Error: 'module' and 'class' parameters required")
            sys.exit(1)

        # Import the module and get the class
        try:
            module = importlib.import_module(module_path)
            wrapper_class = getattr(module, class_name)
        except (ImportError, AttributeError) as e:
            print(f"Error importing {module_path}.{class_name}: {e}")
            sys.exit(1)

        # Instantiate the wrapper
        wrapper = wrapper_class()

        # Generate the netlist
        output_name = class_name.lower()
        output_file = f"{output_name}.v"

        if hasattr(wrapper, 'netlist'):
            # Wrapper handles its own netlisting
            wrapper.netlist(output_name, Path('.'))
        else:
            # Fall back to manual conversion
            from migen.fhdl.verilog import convert

            if hasattr(wrapper, 'ios'):
                io_signals = wrapper.ios()
            elif ios:
                # Get signals by name from parameters
                io_signals = [getattr(wrapper, name) for name in ios]
            else:
                print("Error: No IO signals specified")
                sys.exit(1)

            conv = convert(wrapper, ios=io_signals, name=output_name)
            conv.write(output_file)

        # Register the generated file with FuseSoC
        self.add_files([{output_file: {'file_type': 'verilogSource'}}])


if __name__ == '__main__':
    g = MigenNetlister()
    g.run()
    g.write()
```

#### Registering the Generator

Create a `.core` file that defines the generator (e.g., `migen_netlister.core`):

```yaml
CAPI=2:
name: mono:utils:migen_netlister:0.1.0
description: Migen to Verilog netlister

generators:
  migen_netlister:
    interpreter: python3
    command: generators/migen_netlister.py
    description: Convert Migen modules to Verilog
```

#### Using the Generator

In a consuming core file:

```yaml
CAPI=2:
name: mycompany:ip:ft601:1.0.0
description: FT601 USB3 PHY

filesets:
  rtl:
    depend:
      - mono:utils:migen_netlister

generate:
  ft601_netlist:
    generator: migen_netlister
    parameters:
      module: mono.wrappers.ft601
      class: FT601Wrapper

targets:
  default:
    generate: [ft601_netlist]
    filesets: [rtl]
    toplevel: ft601wrapper
```

#### Output

The generator produces a `.core` file in the working directory:

```yaml
CAPI=2:
name: ::generated-ft601_netlist:0

filesets:
  rtl:
    files:
      - ft601wrapper.v: {file_type: verilogSource}

targets:
  default:
    filesets: [rtl]
```

This generated core is automatically added to the dependency tree, making `ft601wrapper.v` available to downstream builds.

#### Error Handling

The generator should exit with non-zero status on failure:

- Missing required parameters
- Import errors (module not found)
- Migen conversion errors
- File write errors

FuseSoC will report the failure and abort the build.
