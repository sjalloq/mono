#
# USB Core Wrapper for Netlist Generation
#
# Copyright (c) 2025 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# Wraps USBDepacketizer, USBPacketizer, and USBCrossbar to expose clean
# Verilog ports for integration with an SV FT601 PHY.
#

from migen import Signal

from litex.soc.interconnect import stream

from mono.migen import MigenWrapper
from mono.gateware.usb.core import (
    USBDepacketizer,
    USBPacketizer,
    USBCrossbar,
    usb_phy_description,
)


class USBCoreWrapper(MigenWrapper):
    """
    Wrapper for USB channel multiplexing logic (minus PHY).

    Exposes:
        PHY side (directly connected to FT601 PHY):
            - phy_rx_*: Raw 32-bit stream from PHY (RX from host)
            - phy_tx_*: Raw 32-bit stream to PHY (TX to host)

        User side (one per channel):
            - ch{N}_rx_*: Channel data received from host
            - ch{N}_tx_*: Channel data to send to host

    Args:
        num_ports: Number of channel ports to create (default 2)
        clk_freq: System clock frequency in Hz (default 100MHz)
        timeout: Depacketizer timeout in seconds (default 10)
    """

    def __init__(self, num_ports: int = 2, clk_freq: int = 100_000_000, timeout: int = 10):
        super().__init__()

        # Create the core components
        self.submodules.depacketizer = USBDepacketizer(clk_freq, timeout)
        self.submodules.packetizer = USBPacketizer()
        self.submodules.crossbar = USBCrossbar()

        # Allocate user ports on the crossbar
        self.user_ports = []
        for i in range(num_ports):
            port = self.crossbar.get_port(channel_id=i)
            self.user_ports.append(port)

        # Connect depacketizer -> crossbar (RX path)
        self.comb += self.depacketizer.source.connect(self.crossbar.master.sink)

        # Connect crossbar -> packetizer (TX path)
        self.comb += self.crossbar.master.source.connect(self.packetizer.sink)

        # Wrap PHY-side interfaces
        # RX: data from FT601 PHY enters depacketizer
        self.wrap_endpoint(self.depacketizer.sink, "phy_rx", direction="sink")

        # TX: packetized data sent to FT601 PHY
        self.wrap_endpoint(self.packetizer.source, "phy_tx", direction="source")

        # Wrap user-side interfaces (one per channel)
        for i, port in enumerate(self.user_ports):
            # RX: data received from host for this channel
            self.wrap_endpoint(port.source, f"ch{i}_rx", direction="source")

            # TX: data to send to host from this channel
            self.wrap_endpoint(port.sink, f"ch{i}_tx", direction="sink")
