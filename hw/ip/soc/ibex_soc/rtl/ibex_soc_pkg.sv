// SPDX-License-Identifier: BSD-2-Clause
// Ibex SoC Package
//
// Copyright (c) 2025-2026 Shareef Jalloq
//
// Memory map definitions and configuration parameters.

package ibex_soc_pkg;

    // Bus parameters
    parameter int unsigned AddrWidth = 32;
    parameter int unsigned DataWidth = 32;

    // Number of masters
    parameter int unsigned NumMasters = 3;  // I-bus, D-bus, Etherbone

    // Master indices
    parameter int unsigned MasterIbus = 0;
    parameter int unsigned MasterDbus = 1;
    parameter int unsigned MasterEb   = 2;

    // Memory slaves (configurable base + mask)
    parameter int unsigned NumMemSlaves = 2;    // ITCM, DTCM
    parameter int unsigned SlaveItcm = 0;
    parameter int unsigned SlaveDtcm = 1;

    // Peripheral base (fixed 4K windows from PeriphBase)
    parameter logic [AddrWidth-1:0] PeriphBase = 32'h1000_0000;
    parameter logic [AddrWidth-1:0] PeriphMask = 32'hFFFF_F000;

    // Internal peripheral slot indices (relative to PeriphBase)
    parameter int unsigned NumIntPeriphs = 2;   // Timer, SimCtrl
    parameter int unsigned PeriphTimer   = 0;
    parameter int unsigned PeriphSimCtrl = 1;

    // Total internal slaves
    parameter int unsigned NumIntSlaves = NumMemSlaves + NumIntPeriphs;  // 4

    // Crossbar slave indices (memories first, then peripherals)
    parameter int unsigned SlaveTimer   = NumMemSlaves + PeriphTimer;    // 2
    parameter int unsigned SlaveSimCtrl = NumMemSlaves + PeriphSimCtrl;  // 3

    // Memory map: memory slaves (configurable size)
    parameter logic [AddrWidth-1:0] ItcmBase  = 32'h0001_0000;
    parameter int unsigned          ItcmDepth = 4096;  // 16KB (4096 x 32-bit)
    parameter logic [AddrWidth-1:0] ItcmMask  = 32'hFFFF_C000;

    parameter logic [AddrWidth-1:0] DtcmBase  = 32'h0002_0000;
    parameter int unsigned          DtcmDepth = 4096;  // 16KB (4096 x 32-bit)
    parameter logic [AddrWidth-1:0] DtcmMask  = 32'hFFFF_C000;

    // Derived peripheral base addresses (for HAL/SW headers)
    parameter logic [AddrWidth-1:0] TimerBase   = PeriphBase + PeriphTimer   * 32'h1000;
    parameter logic [AddrWidth-1:0] SimCtrlBase = PeriphBase + PeriphSimCtrl * 32'h1000;

    // Boot address (start of ITCM)
    parameter logic [AddrWidth-1:0] BootAddr = ItcmBase;

    // Debug addresses (within ITCM)
    parameter logic [AddrWidth-1:0] DmHaltAddr = ItcmBase;
    parameter logic [AddrWidth-1:0] DmExceptionAddr = ItcmBase + 4;

endpackage
