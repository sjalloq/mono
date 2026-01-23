"""Pipelined Wishbone B4 slave with callbacks or built-in memory.

Implements a Wishbone B4 slave that uses callbacks for read/write operations,
or a built-in memory model if no callbacks are provided.

Reference: Wishbone B4 Specification
    https://cdn.opencores.org/downloads/wbspec_b4.pdf
"""

import random
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional

import cocotb
from cocotb.triggers import RisingEdge
from cocotb_bus.drivers import BusDriver


@dataclass
class WBRequest:
    """Captured Wishbone request (for debugging/logging)."""

    addr: int
    data: int  # Write data (0 for reads)
    we: bool
    sel: int


class WishboneSlave(BusDriver):
    """Pipelined Wishbone B4 slave with callbacks or built-in memory.

    Uses two coroutines per transaction:
    - Address loop: observes bus, detects completed address phases, spawns data phases
    - Data phase: drives STALL while busy, then ACK and read data

    Can be used with callbacks for custom behavior:
        def on_read(addr, sel):
            return my_memory.get(addr, 0)

        def on_write(addr, data, sel):
            my_memory[addr] = data

        slave = WishboneSlave(dut, "wb", dut.clk,
                              on_read=on_read, on_write=on_write)

    Or with built-in memory model:
        slave = WishboneSlave(dut, "s0", dut.clk, size=0x10000)
        slave.write_word(0x100, 0xDEADBEEF)  # Direct memory access
        data = slave.read_word(0x100)
    """

    # Default signal mapping (crossbar slave port naming)
    _signals = {
        "cyc": "cyc_o",
        "stb": "stb_o",
        "we": "we_o",
        "adr": "adr_o",
        "dat_o": "dat_o",
        "sel": "sel_o",
        "ack": "ack_i",
        "dat_i": "dat_i",
    }
    _optional_signals = {
        "err": "err_i",
        "stall": "stall_i",
    }

    def __init__(
        self,
        entity,
        name: str,
        clock,
        on_read: Optional[Callable[[int, int], int]] = None,
        on_write: Optional[Callable[[int, int, int], None]] = None,
        size: int = 0x10000,
        latency: int = 0,
        stall_prob: float = 0.0,
        signals: Optional[Dict[str, str]] = None,
        **kwargs: Any,
    ):
        """Initialize the Wishbone slave.

        Args:
            entity: DUT entity containing Wishbone signals.
            name: Signal name prefix (e.g., "s0" for "s0_cyc_o").
            clock: Clock signal for synchronization.
            on_read: Callback for reads: (addr, sel) -> data. If None, uses built-in memory.
            on_write: Callback for writes: (addr, data, sel) -> None. If None, uses built-in memory.
            size: Memory size in bytes (for built-in memory and bounds checking).
            latency: Response latency in clock cycles (0 = next cycle).
            stall_prob: Probability of extra stall cycles (0.0 - 1.0).
            signals: Signal name mapping dict. Keys are canonical names,
                     values are the actual signal suffixes.
            **kwargs: Additional arguments passed to BusDriver.
        """
        if signals is not None:
            required_keys = {"cyc", "stb", "we", "adr", "dat_o", "sel", "ack", "dat_i"}
            optional_keys = {"err", "stall"}
            self._signals = {k: v for k, v in signals.items() if k in required_keys}
            self._optional_signals = {k: v for k, v in signals.items() if k in optional_keys}

        super().__init__(entity, name, clock, **kwargs)

        self._size = size
        self._addr_mask = size - 1  # Mask to convert to local address
        self._latency = latency
        self._stall_prob = stall_prob

        # Built-in memory model (sparse dict)
        self._mem: Dict[int, int] = {}

        # Set up callbacks - use built-in memory if not provided
        if on_read is not None:
            self._on_read = on_read
        else:
            self._on_read = self._default_read

        if on_write is not None:
            self._on_write = on_write
        else:
            self._on_write = self._default_write

        # Initialize outputs
        self.bus.ack.value = 0
        self.bus.dat_i.value = 0
        if hasattr(self.bus, "err"):
            self.bus.err.value = 0
        if hasattr(self.bus, "stall"):
            self.bus.stall.value = 0

        cocotb.start_soon(self._run())

    def _default_read(self, addr: int, sel: int) -> int:
        """Built-in memory read callback."""
        local_addr = addr & self._addr_mask & ~0x3
        return self._mem.get(local_addr, 0)

    def _default_write(self, addr: int, data: int, sel: int) -> None:
        """Built-in memory write callback with byte enables."""
        local_addr = addr & self._addr_mask & ~0x3
        current = self._mem.get(local_addr, 0)

        # Apply byte enables
        for byte in range(4):
            if sel & (1 << byte):
                mask = 0xFF << (byte * 8)
                current = (current & ~mask) | (data & mask)

        self._mem[local_addr] = current

    def read_word(self, addr: int) -> int:
        """Direct read from built-in memory (bypasses bus).

        Args:
            addr: Local address (masked by size).

        Returns:
            32-bit data value (0 if uninitialized).
        """
        local_addr = addr & self._addr_mask & ~0x3
        return self._mem.get(local_addr, 0)

    def write_word(self, addr: int, data: int) -> None:
        """Direct write to built-in memory (bypasses bus).

        Args:
            addr: Local address (masked by size).
            data: 32-bit data value.
        """
        local_addr = addr & self._addr_mask & ~0x3
        self._mem[local_addr] = data & 0xFFFFFFFF

    @property
    def mem(self) -> Dict[int, int]:
        """Direct access to memory dict."""
        return self._mem

    async def _run(self):
        """Address phase observer - samples bus, spawns data phases."""
        while True:
            await RisingEdge(self.clock)

            # Check for valid address phase (STB+CYC)
            if not (self.bus.cyc.value and self.bus.stb.value):
                continue

            # Don't capture if stalled (data phase controls stall)
            if hasattr(self.bus, "stall") and self.bus.stall.value:
                continue

            # Address phase accepted - capture transaction
            addr = int(self.bus.adr.value)
            sel = int(self.bus.sel.value)
            we = bool(self.bus.we.value)

            if we:
                wr_data = int(self.bus.dat_o.value)
                self._on_write(addr, wr_data, sel)
                resp_data = 0
            else:
                resp_data = self._on_read(addr, sel)

            # Spawn data phase handler
            cocotb.start_soon(self._data_phase(resp_data))

    async def _data_phase(self, data: int):
        """Data phase - drives STALL, ACK, DAT_I."""
        # Block new address phases while processing
        if hasattr(self.bus, "stall"):
            self.bus.stall.value = 1

        # Calculate wait cycles: base latency + random backpressure
        wait_cycles = self._latency
        while self._stall_prob > 0 and random.random() < self._stall_prob:
            wait_cycles += 1

        for _ in range(wait_cycles):
            await RisingEdge(self.clock)

        # Drive response and release stall
        self.bus.ack.value = 1
        self.bus.dat_i.value = data
        if hasattr(self.bus, "stall"):
            self.bus.stall.value = 0

        await RisingEdge(self.clock)

        # Clear ACK
        self.bus.ack.value = 0

    async def _driver_send(self, transaction: Any, sync: bool = True) -> None:
        """BusDriver interface - not used, we use callbacks instead."""
        pass


__all__ = ["WishboneSlave", "WBRequest"]
