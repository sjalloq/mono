"""Pipelined Wishbone B4 master driver.

Implements a Wishbone B4 master with true pipelining support. Address and data
phases run as separate concurrent loops, allowing multiple transactions in flight.

Reference: Wishbone B4 Specification, Section 3.2.5 (Registered Feedback)
    https://cdn.opencores.org/downloads/wbspec_b4.pdf
"""

from collections import deque
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

import cocotb
from cocotb.triggers import Event, RisingEdge
from cocotb_bus.drivers import BusDriver


@dataclass
class WBResponse:
    """Result of a completed Wishbone transaction."""

    data: int
    ack: bool = True
    err: bool = False


@dataclass
class WBTransaction:
    """Internal transaction tracking."""

    addr: int
    data: int
    we: bool
    sel: int
    event: Event = field(default_factory=Event)
    response: Optional[WBResponse] = None


class WishboneMaster(BusDriver):
    """Pipelined Wishbone B4 master.

    Runs two concurrent loops:
    - Address loop: drives STB/ADR/WE/DAT_O, handles STALL
    - Data loop: watches for ACK/ERR, completes transactions

    Transactions flow: pending -> outstanding -> complete

    Example:
        # Defaults work for crossbar master ports (m0_cyc_i, m0_stb_i, etc.)
        master = WishboneMaster(dut, "m0", dut.clk)

        # Simple blocking operations
        resp = await master.read(0x1000)
        await master.write(0x2000, 0xDEADBEEF)

        # Pipelined (multiple in flight)
        r1 = cocotb.start_soon(master.read(0x1000))
        r2 = cocotb.start_soon(master.read(0x1004))
        r3 = cocotb.start_soon(master.write(0x2000, 0x1234))
        await Combine(r1, r2, r3)

        # Custom signal naming for non-crossbar use
        master = WishboneMaster(dut, "wb", dut.clk, signals={
            "cyc": "cyc_o", "stb": "stb_o", "we": "we_o",
            "adr": "adr_o", "dat_o": "dat_o", "sel": "sel_o",
            "dat_i": "dat_i", "ack": "ack_i",
        })
    """

    # Default signal mapping (crossbar master port convention)
    # Master drives _i signals into crossbar, receives _o signals back
    _signals = {
        "cyc": "cyc_i",
        "stb": "stb_i",
        "we": "we_i",
        "adr": "adr_i",
        "dat_o": "dat_i",
        "sel": "sel_i",
    }
    _optional_signals = {
        "dat_i": "dat_o",
        "ack": "ack_o",
        "err": "err_o",
        "stall": "stall_o",
    }

    def __init__(
        self,
        entity,
        name: str,
        clock,
        signals: Optional[Dict[str, str]] = None,
        **kwargs: Any,
    ):
        """Initialize the Wishbone master.

        Args:
            entity: DUT entity containing Wishbone signals.
            name: Signal name prefix (e.g., "wb" for "wb_cyc").
            clock: Clock signal for synchronization.
            signals: Signal name mapping dict. Keys are canonical names
                     (cyc, stb, we, adr, dat_o, sel, dat_i, ack, err, stall),
                     values are the actual signal suffixes.
            **kwargs: Additional arguments passed to BusDriver.
        """
        if signals is not None:
            # Split into required and optional based on what's provided
            required = {k: v for k, v in signals.items()
                       if k in ("cyc", "stb", "we", "adr", "dat_o", "sel")}
            optional = {k: v for k, v in signals.items()
                       if k in ("dat_i", "ack", "err", "stall")}
            self._signals = required if required else self._signals
            self._optional_signals = optional if optional else self._optional_signals

        super().__init__(entity, name, clock, **kwargs)

        self._addr_queue: deque[WBTransaction] = deque()
        self._data_queue: deque[WBTransaction] = deque()

        # Initialize outputs to idle
        self.bus.cyc.value = 0
        self.bus.stb.value = 0
        self.bus.we.value = 0
        self.bus.adr.value = 0
        self.bus.dat_o.value = 0
        self.bus.sel.value = 0

        cocotb.start_soon(self._address_loop())
        cocotb.start_soon(self._data_loop())

    async def read(self, addr: int, sel: int = 0xF) -> WBResponse:
        """Perform a read transaction.

        Args:
            addr: Read address.
            sel: Byte select mask (default 0xF = all bytes).

        Returns:
            WBResponse with read data and status.
        """
        txn = WBTransaction(addr=addr, data=0, we=False, sel=sel)
        self._addr_queue.append(txn)
        await txn.event.wait()
        return txn.response

    async def write(self, addr: int, data: int, sel: int = 0xF) -> WBResponse:
        """Perform a write transaction.

        Args:
            addr: Write address.
            data: Data to write.
            sel: Byte select mask (default 0xF = all bytes).

        Returns:
            WBResponse with status.
        """
        txn = WBTransaction(addr=addr, data=data, we=True, sel=sel)
        self._addr_queue.append(txn)
        await txn.event.wait()
        return txn.response

    async def _address_loop(self):
        """Drive address phases, handle STALL.

        Consumes from _pending, produces to _outstanding.
        """
        while True:
            # Idle - no pending transactions
            while not self._addr_queue:
                self.bus.cyc.value = 1 if self._data_queue else 0
                self.bus.stb.value = 0
                await RisingEdge(self.clock)

            txn = self._addr_queue[0]

            # Drive address phase
            self.bus.cyc.value = 1
            self.bus.stb.value = 1
            self.bus.adr.value = txn.addr
            self.bus.we.value = 1 if txn.we else 0
            self.bus.dat_o.value = txn.data
            self.bus.sel.value = txn.sel

            await RisingEdge(self.clock)

            # Check STALL - if not stalled, address was accepted
            stall = int(self.bus.stall.value) if hasattr(self.bus, "stall") else 0
            if not stall:
                self._addr_queue.popleft()
                self._data_queue.append(txn)
            # else: loop again, re-present same transaction

    async def _data_loop(self):
        """Watch for ACK/ERR, complete transactions in FIFO order.

        Consumes from _outstanding, signals completion via event.
        """
        while True:
            await RisingEdge(self.clock)

            if not self._data_queue:
                continue

            ack = int(self.bus.ack.value) if hasattr(self.bus, "ack") else 0
            err = int(self.bus.err.value) if hasattr(self.bus, "err") else 0

            if ack:
                txn = self._data_queue.popleft()
                read_data = 0
                if not txn.we and hasattr(self.bus, "dat_i"):
                    read_data = int(self.bus.dat_i.value)
                txn.response = WBResponse(data=read_data, ack=True, err=False)
                txn.event.set()

            elif err:
                txn = self._data_queue.popleft()
                txn.response = WBResponse(data=0, ack=False, err=True)
                txn.event.set()

    async def _driver_send(self, transaction: Any, sync: bool = True) -> None:
        """BusDriver interface - not used, we use read()/write() instead."""
        pass


__all__ = ["WishboneMaster", "WBResponse", "WBTransaction"]
