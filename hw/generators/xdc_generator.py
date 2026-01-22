#!/usr/bin/env python3
#
# XDC Constraint Generator for FuseSoC
#
# Copyright (c) 2025-2026 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# A FuseSoC generator that creates XDC constraints from board YAML
# and SystemVerilog port definitions.
#

import sys
from pathlib import Path

from fusesoc.capi2.generator import Generator


class XDCGenerator(Generator):
    """
    FuseSoC generator for creating XDC constraint files.

    Parameters (from core file):
        board: Path to board YAML file (relative to core file or absolute)
        toplevel: Path to toplevel SystemVerilog file (optional, for port parsing)
        output: Output XDC filename (default: constraints.xdc)
        pin_map: Optional dict mapping SV port names to board pin paths
                 (e.g., {"usb_data": "usb_fifo.data"})

    Example core file usage:
        generate:
          constraints:
            generator: xdc_generator
            parameters:
              board: board.yaml
              toplevel: rtl/top.sv
              output: project.xdc
              pin_map:
                usb_data: usb_fifo.data
                usb_clk: usb_fifo.clk
    """

    def run(self):
        board_path = self.config.get("board")
        toplevel_path = self.config.get("toplevel")
        output_name = self.config.get("output", "constraints.xdc")
        pin_map = self.config.get("pin_map", {})

        if not board_path:
            print("Error: 'board' parameter is required", file=sys.stderr)
            sys.exit(1)

        # Resolve paths relative to files root if provided
        files_root = Path(self.config.get("files_root", "."))
        board_file = files_root / board_path
        if not board_file.exists():
            # Try as absolute path
            board_file = Path(board_path)
            if not board_file.exists():
                print(f"Error: Board file not found: {board_path}", file=sys.stderr)
                sys.exit(1)

        toplevel_file = None
        if toplevel_path:
            toplevel_file = files_root / toplevel_path
            if not toplevel_file.exists():
                toplevel_file = Path(toplevel_path)
                if not toplevel_file.exists():
                    print(f"Error: Toplevel file not found: {toplevel_path}", file=sys.stderr)
                    sys.exit(1)

        # Import the XDC library
        try:
            from mono.tools.xdc import XDCGenerator as XDCGen
        except ImportError as e:
            print(f"Error: Failed to import mono.tools.xdc: {e}", file=sys.stderr)
            print("Make sure the mono package is installed", file=sys.stderr)
            sys.exit(1)

        # Generate constraints
        try:
            gen = XDCGen.from_files(board_file, toplevel_file)
            gen.map_ports(pin_map)
            gen.generate(output_name)
        except Exception as e:
            print(f"Error: Failed to generate XDC: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            sys.exit(1)

        # Report unmapped ports
        if gen.unmapped_ports:
            print(f"Warning: Unmapped ports: {', '.join(gen.unmapped_ports)}", file=sys.stderr)

        # Register the generated file with FuseSoC
        self.add_files([{output_name: {"file_type": "xdc"}}])

        print(f"Generated: {output_name}")


def main():
    g = XDCGenerator()
    g.run()
    g.write()


if __name__ == "__main__":
    main()
