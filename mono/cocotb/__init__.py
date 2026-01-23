"""Cocotb verification components for the mono project.

This package follows the cocotbext organizational style with Bus/Driver/Monitor
patterns.

Subpackages:
    ft601: FT601 USB 3.0 FIFO bridge verification IP
    wishbone: Wishbone B4 pipelined bus verification IP
"""

from .ft601 import FT601Bus, FT601Driver, FT601Monitor
from .wishbone import WishboneMaster, WishboneSlave, WBResponse

__all__ = [
    # FT601
    "FT601Bus",
    "FT601Driver",
    "FT601Monitor",
    # Wishbone
    "WishboneMaster",
    "WishboneSlave",
    "WBResponse",
]
