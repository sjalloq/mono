"""Pipelined Wishbone B4 bus verification components.

Provides a master driver and slave responder for Wishbone B4 pipelined
transactions. Both use concurrent address/data phase loops for true pipelining.

Default signal naming follows crossbar convention:
- Master: drives _i signals (cyc_i, stb_i, ...), receives _o signals (ack_o, dat_o)
- Slave: receives _o signals (cyc_o, stb_o, ...), drives _i signals (ack_i, dat_i)

Components:
    WishboneMaster: Pipelined master driver for initiating transactions.
    WishboneSlave: Callback-based or memory-backed slave responder.
    WBResponse: Transaction result from master operations.
    WBRequest: Captured request (for debugging).

Example:
    from mono.cocotb.wishbone import WishboneMaster, WishboneSlave

    # Crossbar testing - defaults just work
    master = WishboneMaster(dut, "m0", dut.clk)
    slave = WishboneSlave(dut, "s0", dut.clk, size=0x10000)

    resp = await master.read(0x1000)
    await master.write(0x2000, 0xDEADBEEF)

Reference: Wishbone B4 Specification
    https://cdn.opencores.org/downloads/wbspec_b4.pdf
"""

from .wb_master import WishboneMaster, WBResponse, WBTransaction
from .wb_slave import WishboneSlave, WBRequest

__all__ = [
    "WishboneMaster",
    "WBResponse",
    "WBTransaction",
    "WishboneSlave",
    "WBRequest",
]
