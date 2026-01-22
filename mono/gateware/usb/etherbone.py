#
# USB Etherbone - Wishbone over USB using Etherbone Protocol
#
# Copyright (c) 2025-2026 Shareef Jalloq
# SPDX-License-Identifier: BSD-2-Clause
#
# Re-exports from etherbone_adapter.py which uses LiteEth's Etherbone
# protocol components with a USB transport layer.
#

from .etherbone_adapter import USBEtherbone, USBEtherbonePacketTX, USBEtherbonePacketRX

# Backward compatibility alias
Etherbone = USBEtherbone

__all__ = ['USBEtherbone', 'Etherbone', 'USBEtherbonePacketTX', 'USBEtherbonePacketRX']
