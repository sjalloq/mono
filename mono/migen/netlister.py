#
# Migen Netlist Utilities
#
# Copyright (c) 2025 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# Provides base classes and utilities for wrapping Migen modules
# to produce clean Verilog netlists with stable port names.
#

from pathlib import Path
from typing import Union

from migen import Module, Signal, Record
from migen.fhdl.verilog import convert


def flatten_endpoint_signals(endpoint, prefix: str = "") -> list[tuple[str, Signal]]:
    """
    Flatten a LiteX stream Endpoint into a list of (name, signal) tuples.

    Stream Endpoints have this structure:
        - valid (1 bit, master->slave)
        - ready (1 bit, slave->master)
        - first (1 bit, master->slave)
        - last (1 bit, master->slave)
        - payload (Record with data fields)
        - param (Record with parameter fields)

    Args:
        endpoint: A LiteX stream.Endpoint instance
        prefix: Optional prefix for signal names (e.g., "sink_" or "source_")

    Returns:
        List of (name, signal) tuples representing all flattened signals
    """
    signals = []
    name_prefix = f"{prefix}_" if prefix else ""

    # Control signals
    for sig_name in ["valid", "ready", "first", "last"]:
        sig = getattr(endpoint, sig_name)
        signals.append((f"{name_prefix}{sig_name}", sig))

    # Flatten payload and param records
    for container_name in ["payload", "param"]:
        container = getattr(endpoint, container_name, None)
        if container is None:
            continue

        # Iterate over the layout to get field names
        # Layout format: [(field_name, bits, direction), ...]
        if hasattr(container, "layout"):
            for item in container.layout:
                if isinstance(item, tuple) and len(item) >= 2:
                    field_name = item[0]
                    sig = getattr(container, field_name, None)
                    if sig is not None:
                        signals.append((f"{name_prefix}{field_name}", sig))

    return signals


class MigenWrapper(Module):
    """
    Base class for wrapping Migen/LiteX modules for netlist generation.

    Subclasses should:
    1. Instantiate the target module as a submodule
    2. Create top-level Signal instances for all ports
    3. Connect submodule signals to top-level signals using comb
    4. Call register_io() for each top-level signal

    Example:
        class MyWrapper(MigenWrapper):
            def __init__(self):
                super().__init__()
                self.submodules.inner = MyModule()

                # Create top-level signals
                self.data_in = Signal(32)
                self.data_out = Signal(32)

                # Connect
                self.comb += [
                    self.inner.input.eq(self.data_in),
                    self.data_out.eq(self.inner.output),
                ]

                # Register as IO
                self.register_io(self.data_in, self.data_out)
    """

    def __init__(self):
        super().__init__()
        self._io_signals = []

    def register_io(self, *signals: Signal) -> None:
        """Register signals as top-level IO ports."""
        self._io_signals.extend(signals)

    def ios(self) -> set[Signal]:
        """Return the set of IO signals for Verilog conversion."""
        return set(self._io_signals)

    def wrap_endpoint(
        self,
        endpoint,
        prefix: str,
        direction: str = "auto"
    ) -> dict[str, Signal]:
        """
        Create top-level signals for a stream Endpoint and connect them.

        This method creates new Signal instances at the wrapper level,
        connects them to the endpoint's signals, and registers them as IO.

        Args:
            endpoint: A LiteX stream.Endpoint instance
            prefix: Prefix for signal names (e.g., "sink" or "source")
            direction: "sink", "source", or "auto" to determine signal directions.
                       For "sink" endpoints: valid/first/last/data are inputs, ready is output
                       For "source" endpoints: valid/first/last/data are outputs, ready is input

        Returns:
            Dictionary mapping signal names to the created Signal instances
        """
        created_signals = {}
        port_prefix = prefix

        # Determine which signals are inputs vs outputs based on endpoint direction
        # For a SINK endpoint (data flows IN): valid, first, last, payload, param are inputs; ready is output
        # For a SOURCE endpoint (data flows OUT): valid, first, last, payload, param are outputs; ready is input
        is_sink = direction == "sink" or (direction == "auto" and "sink" in prefix.lower())

        # Process control signals
        for sig_name in ["valid", "ready", "first", "last"]:
            orig_sig = getattr(endpoint, sig_name)
            new_sig = Signal(len(orig_sig), name=f"{port_prefix}_{sig_name}")
            created_signals[f"{port_prefix}_{sig_name}"] = new_sig
            setattr(self, f"{port_prefix}_{sig_name}", new_sig)

            # Connect based on direction
            if sig_name == "ready":
                # ready flows opposite to data
                if is_sink:
                    self.comb += new_sig.eq(orig_sig)  # output from wrapper
                else:
                    self.comb += orig_sig.eq(new_sig)  # input to wrapper
            else:
                # valid, first, last flow with data
                if is_sink:
                    self.comb += orig_sig.eq(new_sig)  # input to wrapper
                else:
                    self.comb += new_sig.eq(orig_sig)  # output from wrapper

            self.register_io(new_sig)

        # Process payload signals
        if hasattr(endpoint, "payload"):
            self._wrap_record(endpoint.payload, port_prefix, is_sink, created_signals)

        # Process param signals
        if hasattr(endpoint, "param"):
            self._wrap_record(endpoint.param, port_prefix, is_sink, created_signals)

        return created_signals

    def _wrap_record(
        self,
        record: Record,
        prefix: str,
        is_sink: bool,
        created_signals: dict
    ) -> None:
        """Helper to wrap signals from a Record (payload or param)."""
        # Iterate over the layout to get field names and access signals
        # Layout format: [(field_name, bits, direction), ...]
        for item in record.layout:
            if isinstance(item, tuple) and len(item) >= 2:
                field_name = item[0]
                sig = getattr(record, field_name, None)
                if sig is None:
                    continue

                full_name = f"{prefix}_{field_name}"
                new_sig = Signal(len(sig), name=full_name)
                created_signals[full_name] = new_sig
                setattr(self, full_name, new_sig)

                if is_sink:
                    self.comb += sig.eq(new_sig)  # input to wrapper
                else:
                    self.comb += new_sig.eq(sig)  # output from wrapper

                self.register_io(new_sig)

    def netlist(self, name: str, path: Union[str, Path]) -> Path:
        """
        Generate a Verilog netlist for this wrapper.

        Args:
            name: Module name for the generated Verilog
            path: Directory path where the .v file will be written

        Returns:
            Path to the generated Verilog file
        """
        path = Path(path)
        path.mkdir(parents=True, exist_ok=True)

        output_file = path / f"{name}.v"
        conv = convert(self, ios=self.ios(), name=name)
        conv.write(str(output_file))

        return output_file
