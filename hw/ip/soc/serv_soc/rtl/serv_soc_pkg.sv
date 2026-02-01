// SPDX-License-Identifier: BSD-2-Clause
// SERV SoC Package
//
// Copyright (c) 2026 Shareef Jalloq
//
// Memory map definitions and configuration parameters for the SERV AON SoC.

package serv_soc_pkg;

    // Bus parameters
    parameter int unsigned AddrWidth = 32;
    parameter int unsigned DataWidth = 32;

    // Number of masters
    parameter int unsigned NumMasters = 1;  // SERV only
    parameter int unsigned MasterServ = 0;

    // Memory slaves
    parameter int unsigned NumMemSlaves = 1;  // Unified TCM
    parameter int unsigned SlaveTcm = 0;

    // Peripheral base (fixed 4K windows from PeriphBase)
    parameter logic [AddrWidth-1:0] PeriphBase = 32'h1000_0000;
    parameter logic [AddrWidth-1:0] PeriphMask = 32'hFFFF_F000;

    // Internal peripheral slot indices (relative to PeriphBase)
    parameter int unsigned NumIntPeriphs = 2;   // Timer, SimCtrl
    parameter int unsigned PeriphTimer   = 0;
    parameter int unsigned PeriphSimCtrl = 1;

    // Total internal slaves
    parameter int unsigned NumIntSlaves = NumMemSlaves + NumIntPeriphs;  // 3

    // Crossbar slave indices (memories first, then peripherals)
    parameter int unsigned SlaveTimer   = NumMemSlaves + PeriphTimer;    // 1
    parameter int unsigned SlaveSimCtrl = NumMemSlaves + PeriphSimCtrl;  // 2

    // Memory map: TCM (unified I+D)
    parameter logic [AddrWidth-1:0] TcmBase  = 32'h0000_0000;
    parameter int unsigned          TcmDepth = 2048;  // 8KB (2048 x 32-bit)
    parameter logic [AddrWidth-1:0] TcmMask  = 32'hFFFF_E000;

    // Derived peripheral base addresses (for HAL/SW headers)
    parameter logic [AddrWidth-1:0] TimerBase   = PeriphBase + PeriphTimer   * 32'h1000;
    parameter logic [AddrWidth-1:0] SimCtrlBase = PeriphBase + PeriphSimCtrl * 32'h1000;

    // Boot address (start of TCM)
    parameter logic [AddrWidth-1:0] BootAddr = TcmBase;

endpackage
