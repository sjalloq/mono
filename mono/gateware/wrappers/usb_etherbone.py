#
# USB Etherbone Wrapper for Netlist Generation
#
# Copyright (c) 2025-2026 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# Wraps the complete USB subsystem with Etherbone to expose a
# Wishbone master interface for host access to the SoC.
#

from migen import Signal, ClockDomain

from litex.gen import LiteXModule
from litex.soc.interconnect import stream, wishbone
from litex.soc.cores.usb_fifo import phy_description

from mono.migen import MigenWrapper
from mono.gateware.usb.core import (
    USBDepacketizer,
    USBPacketizer,
    USBCrossbar,
)
from mono.gateware.usb.etherbone import USBEtherbone


class USBEtherboneWrapper(MigenWrapper):
    """
    Wrapper for USB with Etherbone Wishbone master.

    Exposes:
        PHY interface (directly active connect to FT601 in SV):
            - phy_rx_*: Stream from PHY (post clock domain crossing)
            - phy_tx_*: Stream to PHY (pre clock domain crossing)

        Wishbone master interface:
            - wb_cyc_o, wb_stb_o, wb_we_o: Control signals
            - wb_adr_o: Address bus
            - wb_sel_o: Byte select
            - wb_dat_o: Write data
            - wb_dat_i: Read data
            - wb_ack_i: Acknowledge
            - wb_err_i: Error

    Args:
        clk_freq: System clock frequency in Hz (default 100MHz)
        timeout: Depacketizer timeout in seconds (default 10)
        etherbone_channel: USB channel ID for Etherbone (default 0)
        buffer_depth: Etherbone record buffer depth (default 4)
    """

    def __init__(
        self,
        clk_freq: int = 100_000_000,
        timeout: int = 10,
        etherbone_channel: int = 0,
        buffer_depth: int = 4,
    ):
        super().__init__()

        # Create USB core components
        self.submodules.depacketizer = USBDepacketizer(clk_freq, timeout)
        self.submodules.packetizer = USBPacketizer()
        self.submodules.crossbar = USBCrossbar()

        # Connect depacketizer -> crossbar (RX path)
        self.comb += self.depacketizer.source.connect(self.crossbar.master.sink)

        # Connect crossbar -> packetizer (TX path)
        self.comb += self.crossbar.master.source.connect(self.packetizer.sink)

        # Add Etherbone on top
        self.submodules.etherbone = USBEtherbone(
            usb_core=self,
            channel_id=etherbone_channel,
            buffer_depth=buffer_depth,
        )

        # Wrap PHY-side interfaces
        self.wrap_endpoint(self.depacketizer.sink, "phy_rx", direction="sink")
        self.wrap_endpoint(self.packetizer.source, "phy_tx", direction="source")

        # Create and expose Wishbone master signals
        # The etherbone.master is a LiteEthEtherboneWishboneMaster with .bus attribute
        wb = self.etherbone.master.bus

        # Output signals (directly active from Etherbone master)
        self.wb_cyc_o = Signal(name="wb_cyc_o")
        self.wb_stb_o = Signal(name="wb_stb_o")
        self.wb_we_o = Signal(name="wb_we_o")
        self.wb_adr_o = Signal(32, name="wb_adr_o")
        self.wb_sel_o = Signal(4, name="wb_sel_o")
        self.wb_dat_o = Signal(32, name="wb_dat_o")

        # Input signals (directly active to Etherbone master)
        self.wb_dat_i = Signal(32, name="wb_dat_i")
        self.wb_ack_i = Signal(name="wb_ack_i")
        self.wb_err_i = Signal(name="wb_err_i")

        # Connect outputs
        self.comb += [
            self.wb_cyc_o.eq(wb.cyc),
            self.wb_stb_o.eq(wb.stb),
            self.wb_we_o.eq(wb.we),
            self.wb_adr_o.eq(wb.adr),
            self.wb_sel_o.eq(wb.sel),
            self.wb_dat_o.eq(wb.dat_w),
        ]

        # Connect inputs
        self.comb += [
            wb.dat_r.eq(self.wb_dat_i),
            wb.ack.eq(self.wb_ack_i),
            wb.err.eq(self.wb_err_i),
        ]

        # Register Wishbone signals as IO
        self.register_io(
            self.wb_cyc_o,
            self.wb_stb_o,
            self.wb_we_o,
            self.wb_adr_o,
            self.wb_sel_o,
            self.wb_dat_o,
            self.wb_dat_i,
            self.wb_ack_i,
            self.wb_err_i,
        )
