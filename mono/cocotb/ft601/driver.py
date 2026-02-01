"""FT601 driver - simulates the FT601 chip (host side).

This driver acts as the FT601 USB FIFO bridge from the host perspective,
providing data for the FPGA to read (RX) and accepting data written by
the FPGA (TX).

Based on timing specifications in docs/source/usb/ft601_phy.rst.
"""

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly
from cocotb.queue import Queue
from cocotb_bus.drivers import BusDriver

from .bus import FT601Bus


class FT601Driver(BusDriver):
    """Host-side BFM that simulates the FT601 chip.

    The driver manages two queues:
        - tx_queue: Data to send TO the FPGA (FPGA reads via rd_n)
        - rx_queue: Data received FROM the FPGA (FPGA writes via wr_n)

    The FT601 protocol uses active-low signals:
        - rxf_n=0: FT601 has data available for FPGA to read
        - txe_n=0: FT601 can accept data from FPGA
        - oe_n=0: FT601 drives the data bus (FPGA is reading)
        - rd_n=0: FPGA is reading data
        - wr_n=0: FPGA is writing data

    Example:
        >>> bus = FT601Bus(dut, name="ft601")
        >>> driver = FT601Driver(bus)
        >>> await driver.send_to_fpga([0xDEADBEEF, 0xCAFEBABE])
        >>> received = await driver.receive_from_fpga(count=2)
    """

    _signals = FT601Bus._signals
    _optional_signals = FT601Bus._optional_signals

    def __init__(self, entity, name=None, clock=None, **kwargs):
        """Initialize the FT601 driver.

        Args:
            entity: The DUT entity containing the FT601 signals.
            name: Optional signal name prefix.
            clock: Clock signal (defaults to bus.clk).
            **kwargs: Additional arguments passed to BusDriver.
        """
        super().__init__(entity, name, clock, **kwargs)

        # Queues for data transfer
        self._tx_queue = Queue()  # Data to send to FPGA
        self._rx_queue = Queue()  # Data received from FPGA

        # Use bus clock if not specified
        if clock is None:
            self.clock = self.bus.clk
        else:
            self.clock = clock

        # Initialize outputs (active high = deasserted for active-low signals)
        self.bus.rxf_n.value = 1  # No data available
        self.bus.txe_n.value = 0  # Ready to accept data

        # Start the RX and TX handlers
        self._rx_coroutine = cocotb.start_soon(self._rx_handler())
        self._tx_coroutine = cocotb.start_soon(self._tx_handler())

    async def send_to_fpga(self, data):
        """Queue data to be read by the FPGA.

        Args:
            data: Single word or list of 32-bit words to send.
        """
        if isinstance(data, int):
            data = [data]

        for word in data:
            self.log.info(f"Putting {hex(word)} into queue")
            await self._tx_queue.put(word)

    async def receive_from_fpga(self):
        """Receive a complete packet written by the FPGA.

        The RX handler accumulates all words from a single wr_n burst
        and enqueues them as one packet.

        Returns:
            List of (data, be) tuples for the packet.
        """
        return await self._rx_queue.get()

    async def _tx_handler(self):
        """Handle TX path: FT601 sending data to FPGA.

        This coroutine monitors the queue and asserts rxf_n when data
        is available, then drives data onto the bus when the FPGA asserts
        oe_n. The FT601 enables its output drivers on OE_N going LOW;
        RD_N going LOW one cycle later is the read strobe indicating the
        bus turnaround is complete and the FPGA will begin capturing data.
        """
        while True:
            # Wait for data to be queue
            data = await self._tx_queue.get()

            # Assert rxf_n (data available)
            self.bus.rxf_n.value = 0
            await RisingEdge(self.clock)

            # Wait for FPGA to assert oe_n (request to read)
            while self.bus.oe_n.value == 1:
                await RisingEdge(self.clock)

            # Drive first data word immediately — the real FT601 enables its
            # output drivers as soon as OE_N goes LOW.
            self.bus.data.value = data
            await RisingEdge(self.clock)

            # Wait for FPGA to assert rd_n (bus turnaround complete)
            while self.bus.rd_n.value == 1:
                await RisingEdge(self.clock)

            # Stream remaining data: advance each cycle while rd_n is LOW
            while self.bus.rd_n.value == 0:

                if not self._tx_queue.empty():
                    data = self._tx_queue.get_nowait()
                    self.bus.data.value = data
                else:
                    # No more data, deassert rxf_n
                    self.bus.rxf_n.value = 1
                    break

                await RisingEdge(self.clock)

            # Deassert rxf_n when done
            self.bus.rxf_n.value = 1

    async def _rx_handler(self):
        """Handle RX path: FPGA sending data to FT601.

        This coroutine monitors wr_n and captures data written by the FPGA.
        Words are accumulated for the duration of a single wr_n LOW burst
        and enqueued as a complete packet when wr_n goes HIGH.

        The real FT601 captures data on the rising edge where wr_n is already
        LOW. Since wr_n and data_o are both registered (updated on the rising
        edge), we sample on the falling edge where both have settled from the
        previous rising edge.
        """
        while True:
            await FallingEdge(self.clock)

            # Wait for start of a write burst
            if self.bus.wr_n.value == 0 and self.bus.txe_n.value == 0:
                packet = []

                # Accumulate words for the entire burst
                while self.bus.wr_n.value == 0 and self.bus.txe_n.value == 0:
                    data = int(self.bus.data_o.value)
                    be = int(self.bus.be.value)
                    packet.append((data, be))
                    await FallingEdge(self.clock)

                # Enqueue the complete packet
                await self._rx_queue.put(packet)

    def set_tx_ready(self, ready=True):
        """Control whether FT601 can accept data from FPGA.

        Args:
            ready: If True, txe_n=0 (can accept). If False, txe_n=1 (busy).
        """
        self.bus.txe_n.value = 0 if ready else 1

    @property
    def tx_queue_depth(self):
        """Number of words waiting to be sent to FPGA."""
        return self._tx_queue.qsize()

    @property
    def rx_queue_depth(self):
        """Number of packets received from FPGA."""
        return self._rx_queue.qsize()
