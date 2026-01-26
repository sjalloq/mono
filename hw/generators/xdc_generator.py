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


def find_repo_root(start_path: Path) -> Path | None:
    """
    Find the repository root by walking up from start_path.

    Looks for fusesoc.conf or .git directory as indicators of the repo root.
    """
    current = start_path.resolve()
    while current != current.parent:
        if (current / "fusesoc.conf").exists() or (current / ".git").exists():
            return current
        current = current.parent
    return None


class XDCGenerator(Generator):
    """
    FuseSoC generator for creating XDC constraint files.

    Parameters (from core file):
        board: Board name (e.g., "squirrel"). The generator will look for the
               board definition at <repo_root>/hw/boards/<board>/board.yaml
        toplevel: Path to toplevel SystemVerilog file (relative to core file)
        output: Output XDC filename (default: constraints.xdc)
        pin_map: Optional dict mapping SV port names to board pin paths
                 (e.g., {"usb_data": "usb_fifo.data"})

    Example core file usage:
        generate:
          constraints:
            generator: xdc_generator
            parameters:
              board: squirrel
              toplevel: rtl/top.sv
              output: project.xdc
              pin_map:
                usb_data: usb_fifo.data
                usb_clk: usb_fifo.clk
    """

    def run(self):
        board_name = self.config.get("board")
        toplevel_path = self.config.get("toplevel")
        output_name = self.config.get("output", "constraints.xdc")
        pin_map = self.config.get("pin_map", {})

        if not board_name:
            print("Error: 'board' parameter is required", file=sys.stderr)
            sys.exit(1)

        # Get files_root (the calling core's directory)
        files_root = Path(self.files_root) if hasattr(self, 'files_root') else Path(".")

        # Find the repository root
        repo_root = find_repo_root(files_root)
        if not repo_root:
            print(f"Error: Could not find repository root from {files_root}", file=sys.stderr)
            print("Looking for fusesoc.conf or .git directory", file=sys.stderr)
            sys.exit(1)

        # Resolve board file using convention: hw/boards/<board>/board.yaml
        board_file = repo_root / "hw" / "boards" / board_name / "board.yaml"
        if not board_file.exists():
            print(f"Error: Board file not found: {board_file}", file=sys.stderr)
            print(f"Expected board definition at: hw/boards/{board_name}/board.yaml", file=sys.stderr)
            sys.exit(1)

        # Resolve toplevel file relative to files_root
        toplevel_file = None
        if toplevel_path:
            toplevel_file = files_root / toplevel_path
            if not toplevel_file.exists():
                print(f"Error: Toplevel file not found: {toplevel_file}", file=sys.stderr)
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
