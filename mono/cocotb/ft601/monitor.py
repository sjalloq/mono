"""FT601 monitor - passive bus observer.

This monitor observes the FT601 bus and records all transactions without
driving any signals. Useful for verification and protocol checking.
"""

from dataclasses import dataclass
from enum import Enum, auto
from typing import Optional

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb_bus.monitors import BusMonitor

from .bus import FT601Bus


class FT601Direction(Enum):
    """Direction of data transfer on the FT601 bus."""
    RX = auto()  # FT601 -> FPGA (FPGA reading)
    TX = auto()  # FPGA -> FT601 (FPGA writing)


@dataclass
class FT601Transaction:
    """Represents a single data transfer on the FT601 bus.

    Attributes:
        direction: RX (FT601->FPGA) or TX (FPGA->FT601).
        data: 32-bit data word.
        be: 4-bit byte enables.
        timestamp: Simulation time when captured.
    """
    direction: FT601Direction
    data: int
    be: int
    timestamp: int


class FT601Monitor(BusMonitor):
    """Passive observer for FT601 bus transactions.

    The monitor watches the control signals and captures data transfers
    in both directions without driving any signals.

    Transactions are recorded in the internal _recvQ list and can also
    be processed via a callback function.

    Example:
        >>> bus = FT601Bus(dut, name="ft601")
        >>> monitor = FT601Monitor(bus)
        >>> # Run test...
        >>> for txn in monitor.transactions:
        ...     print(f"{txn.direction}: 0x{txn.data:08X}")
    """

    _signals = FT601Bus._signals
    _optional_signals = FT601Bus._optional_signals

    def __init__(self, entity, name=None, clock=None, callback=None, **kwargs):
        """Initialize the FT601 monitor.

        Args:
            entity: The DUT entity containing the FT601 signals.
            name: Optional signal name prefix.
            clock: Clock signal (defaults to bus.clk).
            callback: Optional function called for each transaction.
            **kwargs: Additional arguments passed to BusMonitor.
        """
        super().__init__(entity, name, clock, callback=callback, **kwargs)

        if clock is None:
            self.clock = self.bus.clk
        else:
            self.clock = clock

        # Transaction storage
        self._transactions = []

        # Protocol checking state
        self._last_oe_n = 1
        self._last_rd_n = 1
        self._last_wr_n = 1
        self._in_rx_transaction = False
        self._in_tx_transaction = False

        # Start the monitor coroutine
        self._monitor_coroutine = cocotb.start_soon(self._monitor_recv())

    async def _monitor_recv(self):
        """Main monitor coroutine - observe bus and capture transactions."""
        while True:
            await RisingEdge(self.clock)
            await ReadOnly()  # Sample signals after they settle

            oe_n = int(self.bus.oe_n.value)
            rd_n = int(self.bus.rd_n.value)
            wr_n = int(self.bus.wr_n.value)
            rxf_n = int(self.bus.rxf_n.value)
            txe_n = int(self.bus.txe_n.value)

            # Detect RX transaction (FT601 -> FPGA)
            # Data valid when oe_n=0, rd_n=0, and rxf_n=0
            if oe_n == 0 and rd_n == 0 and rxf_n == 0:
                data = int(self.bus.data.value)
                be = int(self.bus.be.value) if hasattr(self.bus, 'be') else 0xF

                txn = FT601Transaction(
                    direction=FT601Direction.RX,
                    data=data,
                    be=be,
                    timestamp=cocotb.utils.get_sim_time('ns'),
                )
                self._recv(txn)
                self._transactions.append(txn)

            # Detect TX transaction (FPGA -> FT601)
            # Data valid when wr_n=0 and txe_n=0
            elif wr_n == 0 and txe_n == 0:
                data = int(self.bus.data.value)
                be = int(self.bus.be.value) if hasattr(self.bus, 'be') else 0xF

                txn = FT601Transaction(
                    direction=FT601Direction.TX,
                    data=data,
                    be=be,
                    timestamp=cocotb.utils.get_sim_time('ns'),
                )
                self._recv(txn)
                self._transactions.append(txn)

            # Update state for edge detection
            self._last_oe_n = oe_n
            self._last_rd_n = rd_n
            self._last_wr_n = wr_n

    @property
    def transactions(self):
        """List of all captured transactions."""
        return self._transactions

    @property
    def rx_transactions(self):
        """List of RX transactions (FT601 -> FPGA)."""
        return [t for t in self._transactions if t.direction == FT601Direction.RX]

    @property
    def tx_transactions(self):
        """List of TX transactions (FPGA -> FT601)."""
        return [t for t in self._transactions if t.direction == FT601Direction.TX]

    def clear(self):
        """Clear all recorded transactions."""
        self._transactions.clear()

    def wait_for_transaction(self, direction: Optional[FT601Direction] = None, timeout_ns: int = 10000):
        """Wait for a transaction to occur.

        Args:
            direction: Optional filter for RX or TX only.
            timeout_ns: Maximum time to wait in nanoseconds.

        Returns:
            The captured transaction.

        Raises:
            TimeoutError: If no transaction occurs within timeout.
        """
        # Implementation would use cocotb Events - simplified for now
        raise NotImplementedError("Use callback mechanism for async notification")
