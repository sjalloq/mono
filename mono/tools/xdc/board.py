# SPDX-License-Identifier: BSD-2-Clause
"""Board YAML parsing and data structures."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import yaml


@dataclass
class BoardPin:
    """Single pin definition."""

    pin: str
    iostandard: str
    slew: str | None = None
    pullup: bool = False
    pulldown: bool = False
    drive: int | None = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "BoardPin":
        return cls(
            pin=d["pin"],
            iostandard=d.get("iostandard", "LVCMOS33"),
            slew=d.get("slew"),
            pullup=d.get("pullup", False),
            pulldown=d.get("pulldown", False),
            drive=d.get("drive"),
        )


@dataclass
class BoardBus:
    """Multi-pin bus definition."""

    pins: list[str]
    iostandard: str
    slew: str | None = None
    pullup: bool = False
    pulldown: bool = False
    drive: int | None = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "BoardBus":
        return cls(
            pins=d["pins"],
            iostandard=d.get("iostandard", "LVCMOS33"),
            slew=d.get("slew"),
            pullup=d.get("pullup", False),
            pulldown=d.get("pulldown", False),
            drive=d.get("drive"),
        )


@dataclass
class BoardClock:
    """Clock input definition."""

    pin: str
    frequency: float
    iostandard: str
    name: str | None = None

    @classmethod
    def from_dict(cls, name: str, d: dict[str, Any]) -> "BoardClock":
        return cls(
            pin=d["pin"],
            frequency=float(d["frequency"]),
            iostandard=d.get("iostandard", "LVCMOS33"),
            name=d.get("name", name),
        )


@dataclass
class TimingConstraint:
    """Timing constraint definition."""

    clk: str
    input_delay: dict[str, Any] | None = None
    output_delay: dict[str, Any] | None = None

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "TimingConstraint":
        return cls(
            clk=d["clk"],
            input_delay=d.get("input_delay"),
            output_delay=d.get("output_delay"),
        )


@dataclass
class FalsePath:
    """False path constraint."""

    from_clk: str
    to_clk: str

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "FalsePath":
        return cls(from_clk=d["from"], to_clk=d["to"])


@dataclass
class Board:
    """Board definition parsed from YAML."""

    device: str
    clocks: dict[str, BoardClock] = field(default_factory=dict)
    pins: dict[str, BoardPin | list[BoardPin] | dict[str, BoardPin | BoardBus]] = field(
        default_factory=dict
    )
    timing: dict[str, TimingConstraint] = field(default_factory=dict)
    false_paths: list[FalsePath] = field(default_factory=list)
    bitstream: dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_yaml(cls, path: Path | str) -> "Board":
        """Load board definition from YAML file."""
        path = Path(path)
        with open(path) as f:
            data = yaml.safe_load(f)

        board = cls(device=data["device"])

        # Parse clocks
        for name, clock_data in data.get("clocks", {}).items():
            board.clocks[name] = BoardClock.from_dict(name, clock_data)

        # Parse pins
        for name, pin_data in data.get("pins", {}).items():
            board.pins[name] = cls._parse_pin_entry(pin_data)

        # Parse timing constraints
        for name, timing_data in data.get("timing", {}).items():
            if name == "false_paths":
                for fp in timing_data:
                    board.false_paths.append(FalsePath.from_dict(fp))
            else:
                board.timing[name] = TimingConstraint.from_dict(timing_data)

        # Parse bitstream settings
        board.bitstream = data.get("bitstream", {})

        return board

    @classmethod
    def _parse_pin_entry(
        cls, data: Any
    ) -> BoardPin | list[BoardPin] | dict[str, BoardPin | BoardBus]:
        """Parse a pin entry which can be a single pin, array, or bus with subsignals."""
        if isinstance(data, list):
            # Array of pins (e.g., user_led[0], user_led[1])
            return [BoardPin.from_dict(d) for d in data]
        elif isinstance(data, dict):
            if "pin" in data:
                # Single pin
                return BoardPin.from_dict(data)
            elif "pins" in data:
                # Bus (multi-pin)
                return BoardBus.from_dict(data)
            else:
                # Subsignal group (e.g., usb_fifo.data, usb_fifo.clk)
                result = {}
                for subname, subdata in data.items():
                    if isinstance(subdata, dict):
                        if "pins" in subdata:
                            result[subname] = BoardBus.from_dict(subdata)
                        elif "pin" in subdata:
                            result[subname] = BoardPin.from_dict(subdata)
                return result
        raise ValueError(f"Invalid pin entry format: {data}")

    def get_pin(self, name: str, index: int | None = None) -> BoardPin | None:
        """Get a pin by name, optionally with array index."""
        if name not in self.pins:
            return None
        pin_data = self.pins[name]
        if isinstance(pin_data, list):
            if index is not None and 0 <= index < len(pin_data):
                return pin_data[index]
            return None
        elif isinstance(pin_data, BoardPin):
            return pin_data
        return None

    def get_subsignal(self, name: str, subsignal: str) -> BoardPin | BoardBus | None:
        """Get a subsignal from a bus (e.g., usb_fifo.data)."""
        if name not in self.pins:
            return None
        pin_data = self.pins[name]
        if isinstance(pin_data, dict) and subsignal in pin_data:
            return pin_data[subsignal]
        return None

    def resolve_clock_ref(self, ref: str) -> str | None:
        """Resolve a clock reference like 'usb_fifo.clk' to actual clock name."""
        if "." in ref:
            bus, sig = ref.split(".", 1)
            subsig = self.get_subsignal(bus, sig)
            if isinstance(subsig, BoardPin):
                return f"{bus}_{sig}"
        elif ref in self.clocks:
            return ref
        return ref
