# SPDX-License-Identifier: BSD-2-Clause
"""SystemVerilog port parser for XDC generation.

Uses pyslang for robust parsing of SystemVerilog, including support for
parameterized widths evaluated with default parameter values.
"""

import warnings
from dataclasses import dataclass
from pathlib import Path

import pyslang


@dataclass
class SVPort:
    """SystemVerilog port declaration."""

    name: str
    direction: str  # input, output, inout
    width: int  # 1 for scalar, >1 for vector
    msb: int | None = None  # For vectors: [msb:lsb]
    lsb: int | None = None

    @property
    def is_vector(self) -> bool:
        return self.width > 1

    def bit_name(self, bit: int) -> str:
        """Get the port name for a specific bit."""
        if self.is_vector:
            return f"{self.name}[{bit}]"
        return self.name


def parse_sv_ports(sv_file: Path | str) -> list[SVPort]:
    """Parse SystemVerilog file and extract port declarations.

    Uses pyslang for robust parsing, including evaluation of parameterized
    widths using default parameter values.
    """
    sv_file = Path(sv_file)

    if not sv_file.exists():
        raise FileNotFoundError(f"SystemVerilog file not found: {sv_file}")

    tree = pyslang.SyntaxTree.fromFile(str(sv_file))
    compilation = pyslang.Compilation()
    compilation.addSyntaxTree(tree)

    root = compilation.getRoot()
    if not root.topInstances:
        raise ValueError(f"No module found in {sv_file}")

    # Use first module
    body = root.topInstances[0].body

    ports = []
    for symbol in body.portList:
        if symbol.kind == pyslang.SymbolKind.Port:
            ports.append(_extract_port(symbol))
        elif symbol.kind == pyslang.SymbolKind.InterfacePort:
            warnings.warn(f"Skipping interface port '{symbol.name}'")

    return ports


def _extract_port(port_sym) -> SVPort:
    """Extract port information from a pyslang Port symbol."""
    name = port_sym.name
    direction = _direction_to_string(port_sym.direction)
    width, msb, lsb = _extract_width_info(port_sym.type)
    return SVPort(name=name, direction=direction, width=width, msb=msb, lsb=lsb)


def _direction_to_string(direction) -> str:
    """Convert pyslang ArgumentDirection to string."""
    mapping = {
        pyslang.ArgumentDirection.In: "input",
        pyslang.ArgumentDirection.Out: "output",
        pyslang.ArgumentDirection.InOut: "inout",
    }
    return mapping.get(direction, "input")


def _extract_width_info(port_type) -> tuple[int, int | None, int | None]:
    """Extract width, msb, and lsb from a pyslang type.

    Returns:
        Tuple of (width, msb, lsb). For scalar ports, msb and lsb are None.
    """
    if not port_type.isIntegral:
        return (1, None, None)

    width = port_type.bitWidth
    if width <= 0:
        warnings.warn(f"Could not determine width for type {port_type}")
        return (1, None, None)

    if width == 1:
        # pyslang returns [0:0] for scalars, but we want None/None
        return (1, None, None)

    if port_type.hasFixedRange:
        r = port_type.fixedRange
        return (width, r.left, r.right)

    return (width, width - 1, 0)
