# SPDX-License-Identifier: BSD-2-Clause
"""XDC constraint generation library."""

from .board import Board, BoardPin, BoardClock, BoardBus, TimingConstraint
from .sv_parser import parse_sv_ports, SVPort
from .generator import XDCGenerator

__all__ = [
    "Board",
    "BoardPin",
    "BoardClock",
    "BoardBus",
    "TimingConstraint",
    "parse_sv_ports",
    "SVPort",
    "XDCGenerator",
]
