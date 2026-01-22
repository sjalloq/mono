# SPDX-License-Identifier: BSD-2-Clause
"""XDC constraint file generator."""

import re
from dataclasses import dataclass, field
from pathlib import Path

from .board import Board, BoardBus, BoardClock, BoardPin
from .sv_parser import SVPort, parse_sv_ports


@dataclass
class PinMapping:
    """Mapping between SV port and board pin."""

    sv_port: str
    sv_bit: int | None
    board_pin: str
    iostandard: str
    slew: str | None = None
    pullup: bool = False
    pulldown: bool = False
    drive: int | None = None


@dataclass
class XDCGenerator:
    """Generate XDC constraints from board YAML and SV ports."""

    board: Board
    sv_ports: list[SVPort] = field(default_factory=list)
    pin_mappings: list[PinMapping] = field(default_factory=list)
    unmapped_ports: list[str] = field(default_factory=list)

    @classmethod
    def from_files(
        cls, board_yaml: Path | str, sv_file: Path | str | None = None
    ) -> "XDCGenerator":
        """Create generator from board YAML and optional SV file."""
        board = Board.from_yaml(board_yaml)
        sv_ports = parse_sv_ports(sv_file) if sv_file else []
        return cls(board=board, sv_ports=sv_ports)

    def map_ports(self, pin_overrides: dict[str, str] | None = None) -> None:
        """Map SV ports to board pins.

        Args:
            pin_overrides: Optional dict mapping SV port names to board pin paths
                          (e.g., {"usb_data": "usb_fifo.data"})
        """
        pin_overrides = pin_overrides or {}
        self.pin_mappings = []
        self.unmapped_ports = []

        for port in self.sv_ports:
            mapped = False

            # Check for override first
            if port.name in pin_overrides:
                mapped = self._map_with_override(port, pin_overrides[port.name])
            else:
                # Try automatic mapping
                mapped = self._auto_map_port(port)

            if not mapped:
                self.unmapped_ports.append(port.name)

    def _map_with_override(self, port: SVPort, board_path: str) -> bool:
        """Map port using explicit override path."""
        if "." in board_path:
            # Subsignal reference (e.g., usb_fifo.data)
            bus_name, sig_name = board_path.split(".", 1)
            subsig = self.board.get_subsignal(bus_name, sig_name)
            if subsig:
                return self._map_to_pin_def(port, subsig)
        else:
            # Direct pin reference
            if board_path in self.board.clocks:
                clock = self.board.clocks[board_path]
                self.pin_mappings.append(
                    PinMapping(
                        sv_port=port.name,
                        sv_bit=None,
                        board_pin=clock.pin,
                        iostandard=clock.iostandard,
                    )
                )
                return True
            pin = self.board.get_pin(board_path)
            if pin:
                self.pin_mappings.append(
                    PinMapping(
                        sv_port=port.name,
                        sv_bit=None,
                        board_pin=pin.pin,
                        iostandard=pin.iostandard,
                        slew=pin.slew,
                        pullup=pin.pullup,
                        pulldown=pin.pulldown,
                        drive=pin.drive,
                    )
                )
                return True
        return False

    def _auto_map_port(self, port: SVPort) -> bool:
        """Try to automatically map port to board pin by name matching."""
        # Try direct match with clocks
        if port.name in self.board.clocks:
            clock = self.board.clocks[port.name]
            self.pin_mappings.append(
                PinMapping(
                    sv_port=port.name,
                    sv_bit=None,
                    board_pin=clock.pin,
                    iostandard=clock.iostandard,
                )
            )
            return True

        # Try direct match with pins
        if port.name in self.board.pins:
            pin_data = self.board.pins[port.name]
            return self._map_to_pin_def(port, pin_data)

        # Try matching with underscores converted (e.g., usb_fifo_data -> usb_fifo.data)
        for bus_name, bus_data in self.board.pins.items():
            if isinstance(bus_data, dict):
                for sig_name, sig_data in bus_data.items():
                    # Match patterns like: usb_fifo_data, usb_fifo_clk
                    expected_name = f"{bus_name}_{sig_name}"
                    if port.name == expected_name:
                        return self._map_to_pin_def(port, sig_data)

        # Try array matching (e.g., user_led[0] -> user_led array index 0)
        array_match = re.match(r"(\w+)\[(\d+)\]", port.name)
        if array_match:
            base_name = array_match.group(1)
            index = int(array_match.group(2))
            pin = self.board.get_pin(base_name, index)
            if pin:
                self.pin_mappings.append(
                    PinMapping(
                        sv_port=port.name,
                        sv_bit=None,
                        board_pin=pin.pin,
                        iostandard=pin.iostandard,
                        slew=pin.slew,
                        pullup=pin.pullup,
                        pulldown=pin.pulldown,
                        drive=pin.drive,
                    )
                )
                return True

        return False

    def _map_to_pin_def(
        self, port: SVPort, pin_def: BoardPin | BoardBus | list[BoardPin] | dict
    ) -> bool:
        """Map port to a pin definition."""
        if isinstance(pin_def, BoardPin):
            self.pin_mappings.append(
                PinMapping(
                    sv_port=port.name,
                    sv_bit=None,
                    board_pin=pin_def.pin,
                    iostandard=pin_def.iostandard,
                    slew=pin_def.slew,
                    pullup=pin_def.pullup,
                    pulldown=pin_def.pulldown,
                    drive=pin_def.drive,
                )
            )
            return True

        elif isinstance(pin_def, BoardBus):
            # Map vector port to bus pins
            if port.width != len(pin_def.pins):
                return False
            for i, pin in enumerate(pin_def.pins):
                bit = port.lsb + i if port.lsb is not None else i
                self.pin_mappings.append(
                    PinMapping(
                        sv_port=port.name,
                        sv_bit=bit,
                        board_pin=pin,
                        iostandard=pin_def.iostandard,
                        slew=pin_def.slew,
                        pullup=pin_def.pullup,
                        pulldown=pin_def.pulldown,
                        drive=pin_def.drive,
                    )
                )
            return True

        elif isinstance(pin_def, list):
            # Array of pins
            if port.width != len(pin_def):
                return False
            for i, pin in enumerate(pin_def):
                bit = port.lsb + i if port.lsb is not None else i
                self.pin_mappings.append(
                    PinMapping(
                        sv_port=port.name,
                        sv_bit=bit,
                        board_pin=pin.pin,
                        iostandard=pin.iostandard,
                        slew=pin.slew,
                        pullup=pin.pullup,
                        pulldown=pin.pulldown,
                        drive=pin.drive,
                    )
                )
            return True

        return False

    def generate(self, output: Path | str | None = None) -> str:
        """Generate XDC content."""
        lines = []

        # Header
        lines.append("# Auto-generated XDC constraints")
        lines.append(f"# Device: {self.board.device}")
        lines.append("")

        # Bitstream settings
        if self.board.bitstream:
            lines.append("# Bitstream Configuration")
            for key, value in self.board.bitstream.items():
                lines.append(f"set_property {key} {value} [current_design]")
            lines.append("")

        # Clock constraints
        lines.append("# Clock Constraints")
        for name, clock in self.board.clocks.items():
            period_ns = 1e9 / clock.frequency
            lines.append(
                f"create_clock -period {period_ns:.3f} -name {clock.name or name} "
                f"[get_ports {{{name}}}]"
            )
        lines.append("")

        # Pin assignments
        lines.append("# Pin Assignments")
        for mapping in self.pin_mappings:
            port_ref = (
                f"{mapping.sv_port}[{mapping.sv_bit}]"
                if mapping.sv_bit is not None
                else mapping.sv_port
            )
            lines.append(
                f"set_property PACKAGE_PIN {mapping.board_pin} "
                f"[get_ports {{{port_ref}}}]"
            )
            lines.append(
                f"set_property IOSTANDARD {mapping.iostandard} "
                f"[get_ports {{{port_ref}}}]"
            )
            if mapping.slew:
                lines.append(
                    f"set_property SLEW {mapping.slew} [get_ports {{{port_ref}}}]"
                )
            if mapping.pullup:
                lines.append(f"set_property PULLUP TRUE [get_ports {{{port_ref}}}]")
            if mapping.pulldown:
                lines.append(f"set_property PULLDOWN TRUE [get_ports {{{port_ref}}}]")
            if mapping.drive:
                lines.append(
                    f"set_property DRIVE {mapping.drive} [get_ports {{{port_ref}}}]"
                )
        lines.append("")

        # Timing constraints
        if self.board.timing:
            lines.append("# Timing Constraints")
            for name, timing in self.board.timing.items():
                clk_name = self.board.resolve_clock_ref(timing.clk)
                if timing.input_delay:
                    for port in timing.input_delay.get("ports", []):
                        port_ref = self._resolve_port_ref(name, port)
                        min_delay = timing.input_delay.get("min", 0)
                        max_delay = timing.input_delay.get("max", 0)
                        lines.append(
                            f"set_input_delay -clock {clk_name} -min {min_delay} "
                            f"[get_ports {{{port_ref}}}]"
                        )
                        lines.append(
                            f"set_input_delay -clock {clk_name} -max {max_delay} "
                            f"[get_ports {{{port_ref}}}]"
                        )
                if timing.output_delay:
                    for port in timing.output_delay.get("ports", []):
                        port_ref = self._resolve_port_ref(name, port)
                        min_delay = timing.output_delay.get("min", 0)
                        max_delay = timing.output_delay.get("max", 0)
                        lines.append(
                            f"set_output_delay -clock {clk_name} -min {min_delay} "
                            f"[get_ports {{{port_ref}}}]"
                        )
                        lines.append(
                            f"set_output_delay -clock {clk_name} -max {max_delay} "
                            f"[get_ports {{{port_ref}}}]"
                        )
            lines.append("")

        # False paths
        if self.board.false_paths:
            lines.append("# False Paths / Clock Domain Crossings")
            for fp in self.board.false_paths:
                from_clk = self.board.resolve_clock_ref(fp.from_clk)
                to_clk = self.board.resolve_clock_ref(fp.to_clk)
                lines.append(
                    f"set_false_path -from [get_clocks {from_clk}] "
                    f"-to [get_clocks {to_clk}]"
                )
            lines.append("")

        content = "\n".join(lines)

        if output:
            Path(output).write_text(content)

        return content

    def _resolve_port_ref(self, bus_name: str, sig_name: str) -> str:
        """Resolve a timing constraint port reference to SV port name."""
        # Try to find matching SV port
        expected_name = f"{bus_name}_{sig_name}"
        for port in self.sv_ports:
            if port.name == expected_name:
                if port.is_vector:
                    return f"{port.name}[*]"
                return port.name
        return f"{bus_name}_{sig_name}"
