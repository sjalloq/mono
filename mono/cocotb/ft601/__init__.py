"""FT601 USB 3.0 FIFO bridge verification components.

The FT601 is a USB 3.0 to FIFO bridge IC from FTDI presenting a 32-bit
synchronous FIFO interface running at 100MHz.

Classes:
    FT601Bus: Signal grouping for the FT601 interface
    FT601Driver: Host-side BFM that simulates the FT601 chip
    FT601Monitor: Passive bus observer for transaction recording
"""

from .bus import FT601Bus
from .driver import FT601Driver
from .monitor import FT601Monitor

__all__ = [
    "FT601Bus",
    "FT601Driver",
    "FT601Monitor",
]
