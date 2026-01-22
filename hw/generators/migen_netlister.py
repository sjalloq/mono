#!/usr/bin/env python3
#
# Migen to Verilog Netlister for FuseSoC
#
# Copyright (c) 2025 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# A FuseSoC generator that converts Migen/LiteX modules to Verilog netlists.
#

import importlib
import sys
from pathlib import Path

from fusesoc.capi2.generator import Generator


class MigenNetlister(Generator):
    """
    FuseSoC generator for converting Migen modules to Verilog.

    Parameters (from core file):
        module: Dotted Python module path (e.g., "mono.wrappers.usb_packetizer")
        class: Class name within the module (e.g., "USBPacketizerWrapper")
        ios: Optional list of signal names if the wrapper doesn't provide ios() method
        name: Optional output module name (defaults to lowercase class name)
        args: Optional dict of keyword arguments to pass to the wrapper constructor

    Example core file usage:
        generate:
          netlist:
            generator: migen_netlister
            parameters:
              module: mono.gateware.wrappers.usb_core
              class: USBCoreWrapper
              name: usb_core
              args:
                num_ports: 2
                clk_freq: 100000000
    """

    def run(self):
        module_path = self.config.get("module")
        class_name = self.config.get("class")
        ios_list = self.config.get("ios", [])
        output_name = self.config.get("name", class_name.lower() if class_name else None)
        wrapper_args = self.config.get("args", {})

        if not module_path:
            print("Error: 'module' parameter is required", file=sys.stderr)
            sys.exit(1)

        if not class_name:
            print("Error: 'class' parameter is required", file=sys.stderr)
            sys.exit(1)

        # Import the module and get the wrapper class
        try:
            module = importlib.import_module(module_path)
        except ImportError as e:
            print(f"Error: Failed to import module '{module_path}': {e}", file=sys.stderr)
            sys.exit(1)

        try:
            wrapper_class = getattr(module, class_name)
        except AttributeError:
            print(f"Error: Class '{class_name}' not found in module '{module_path}'", file=sys.stderr)
            sys.exit(1)

        # Instantiate the wrapper with optional arguments
        try:
            wrapper = wrapper_class(**wrapper_args)
        except Exception as e:
            print(f"Error: Failed to instantiate {class_name}: {e}", file=sys.stderr)
            sys.exit(1)

        # Generate the Verilog netlist
        output_file = f"{output_name}.v"

        try:
            if hasattr(wrapper, "netlist"):
                # Wrapper provides its own netlist method
                wrapper.netlist(output_name, Path("."))
            else:
                # Fall back to manual conversion
                from migen.fhdl.verilog import convert

                # Get IO signals
                if hasattr(wrapper, "ios") and callable(wrapper.ios):
                    io_signals = wrapper.ios()
                elif ios_list:
                    # Get signals by name from the wrapper
                    io_signals = set()
                    for name in ios_list:
                        sig = getattr(wrapper, name, None)
                        if sig is None:
                            print(f"Warning: Signal '{name}' not found on wrapper", file=sys.stderr)
                        else:
                            io_signals.add(sig)
                else:
                    print("Error: No IO signals specified and wrapper has no ios() method", file=sys.stderr)
                    sys.exit(1)

                conv = convert(wrapper, ios=io_signals, name=output_name)
                conv.write(output_file)

        except Exception as e:
            print(f"Error: Failed to generate netlist: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            sys.exit(1)

        # Register the generated file with FuseSoC
        self.add_files([{output_file: {"file_type": "verilogSource"}}])

        print(f"Generated: {output_file}")


def main():
    g = MigenNetlister()
    g.run()
    g.write()


if __name__ == "__main__":
    main()
