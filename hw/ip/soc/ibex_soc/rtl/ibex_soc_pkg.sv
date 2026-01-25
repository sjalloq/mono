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

    // Number of masters and slaves
    parameter int unsigned NumMasters = 3;  // I-bus, D-bus, Etherbone
    parameter int unsigned NumSlaves  = 3;  // ITCM, DTCM, Timer

    // Master indices
    parameter int unsigned MasterIbus = 0;
    parameter int unsigned MasterDbus = 1;
    parameter int unsigned MasterEb   = 2;

    // Slave indices
    parameter int unsigned SlaveItcm  = 0;
    parameter int unsigned SlaveDtcm  = 1;
    parameter int unsigned SlaveTimer = 2;

    // Memory map
    // Region: Base address and size
    parameter logic [AddrWidth-1:0] ItcmBase = 32'h0001_0000;
    parameter logic [AddrWidth-1:0] ItcmSize = 32'h0000_4000;  // 16KB
    parameter logic [AddrWidth-1:0] ItcmMask = 32'hFFFF_C000;

    parameter logic [AddrWidth-1:0] DtcmBase = 32'h0002_0000;
    parameter logic [AddrWidth-1:0] DtcmSize = 32'h0000_4000;  // 16KB
    parameter logic [AddrWidth-1:0] DtcmMask = 32'hFFFF_C000;

    parameter logic [AddrWidth-1:0] TimerBase = 32'h1000_0000;
    parameter logic [AddrWidth-1:0] TimerSize = 32'h0000_1000;  // 4KB
    parameter logic [AddrWidth-1:0] TimerMask = 32'hFFFF_F000;

    // Boot address (start of ITCM)
    parameter logic [AddrWidth-1:0] BootAddr = ItcmBase;

    // Debug addresses (within ITCM)
    parameter logic [AddrWidth-1:0] DmHaltAddr = ItcmBase;
    parameter logic [AddrWidth-1:0] DmExceptionAddr = ItcmBase + 4;

    // Slave base and mask arrays for crossbar
    function automatic logic [NumSlaves-1:0][AddrWidth-1:0] getSlaveAddrs();
        logic [NumSlaves-1:0][AddrWidth-1:0] addrs;
        addrs[SlaveItcm]  = ItcmBase;
        addrs[SlaveDtcm]  = DtcmBase;
        addrs[SlaveTimer] = TimerBase;
        return addrs;
    endfunction

    function automatic logic [NumSlaves-1:0][AddrWidth-1:0] getSlaveMasks();
        logic [NumSlaves-1:0][AddrWidth-1:0] masks;
        masks[SlaveItcm]  = ItcmMask;
        masks[SlaveDtcm]  = DtcmMask;
        masks[SlaveTimer] = TimerMask;
        return masks;
    endfunction

endpackage
