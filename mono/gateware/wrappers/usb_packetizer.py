#
# USB Packetizer Wrapper for Netlist Generation
#
# Copyright (c) 2025 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# Wraps the USBPacketizer module to expose stable port names for Verilog generation.
#

from mono.migen import MigenWrapper
from mono.gateware.usb.core import USBPacketizer


class USBPacketizerWrapper(MigenWrapper):
    """
    Wrapper for USBPacketizer that exposes clean Verilog ports.

    The USBPacketizer has:
        - sink: usb_channel_description(32) - input stream with channel data
            - valid, ready, first, last (control)
            - data (32 bits), error (4 bits) - payload
            - dst (8 bits), length (32 bits) - params
        - source: usb_phy_description(32) - output stream with raw PHY data
            - valid, ready, first, last (control)
            - data (32 bits) - payload

    This wrapper creates stable top-level signals for each port.
    """

    def __init__(self):
        super().__init__()

        # Instantiate the packetizer
        self.submodules.packetizer = USBPacketizer()

        # Wrap the sink endpoint (input to the packetizer)
        self.wrap_endpoint(self.packetizer.sink, "sink", direction="sink")

        # Wrap the source endpoint (output from the packetizer)
        self.wrap_endpoint(self.packetizer.source, "source", direction="source")
