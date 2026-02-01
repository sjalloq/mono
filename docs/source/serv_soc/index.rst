########
SERV SoC
########

The SERV SoC is an area-minimal Always-ON (AON) subsystem built around
`SERV <https://github.com/olofk/serv>`_, Olof Kindgren's bit-serial RISC-V CPU.
It targets low-power housekeeping tasks where gate count matters more than
throughput: watchdog supervision, power sequencing, configuration management.

First board target is Squirrel with USB UART for I/O.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   memory_map
   c_toolchain

**********
Components
**********

* **SERV CPU** - Bit-serial RISC-V core (RV32I, W=1) with CSR support
* **TCM** - 8KB unified instruction + data memory
* **Timer** - RISC-V standard mtime/mtimecmp
* **SimCtrl** - Simulation control (printf + halt for Verilator)
* **USB UART** - External slave for host I/O (on Squirrel board)

************
Architecture
************

.. code-block:: text

                          serv_soc_top
   ┌───────────────────────────────────────────────────────┐
   │                                                       │
   │  ┌──────────────────────┐                             │
   │  │    serv_wb_top       │                             │
   │  │  ┌────────────────┐  │                             │
   │  │  │  serv_rf_top   │  │                             │
   │  │  │  (CPU + RF)    │  │                             │
   │  │  │  ibus   dbus   │  │                             │
   │  │  └───┬───────┬────┘  │                             │
   │  │      │       │       │                             │
   │  │  ┌───┴───────┴────┐  │                             │
   │  │  │  I/D arbiter   │  │                             │
   │  │  │ (combinational)│  │                             │
   │  │  └───────┬────────┘  │                             │
   │  │          │ classic   │                             │
   │  │  ┌───────┴────────┐  │                             │
   │  │  │ classic-to-    │  │                             │
   │  │  │ pipelined      │  │                             │
   │  │  │ bridge         │  │                             │
   │  │  └───────┬────────┘  │                             │
   │  │          │ pipelined │                             │
   │  └──────────┼───────────┘                             │
   │             │ wb_m2s_t / wb_s2m_t                     │
   │  ┌──────────┴───────────────────┐                     │
   │  │   wb_crossbar (1×N)          │                     │
   │  └──┬────────┬────────┬─────┬───┘                     │
   │     │        │        │     │                         │
   │  ┌──┴──┐ ┌──┴───┐ ┌──┴──┐ ┌┴────────┐               │
   │  │ TCM │ │Timer │ │SimCl│ │ext slave│──► USB UART   │
   │  │ I+D │ │      │ │    │ │         │               │
   │  └─────┘ └──────┘ └─────┘ └─────────┘               │
   └───────────────────────────────────────────────────────┘

**********************
How serv_wb_top Works
**********************

SERV's native bus interface is Wishbone *classic*: it holds ``cyc`` until
``ack`` arrives, and it never issues instruction and data requests at the same
time. The ``serv_wb_top`` wrapper converts this into the repo's standard
pipelined Wishbone using ``wb_m2s_t``/``wb_s2m_t`` structs.

I/D Arbiter
===========

Because SERV serializes instruction fetches and data accesses, the arbiter is
a pure combinational mux with instruction-bus priority. It replicates the logic
from ``servile_arbiter.v`` in the upstream SERV repository:

.. code-block:: verilog

   assign arb_adr = ibus_cyc ? ibus_adr : dbus_adr;
   assign arb_we  = dbus_we & ~ibus_cyc;
   assign arb_cyc = ibus_cyc | dbus_cyc;

The merged classic bus feeds into the bridge.

Classic-to-Pipelined Bridge
===========================

The bridge is a three-state FSM that converts a single classic Wishbone
transaction into a pipelined one:

.. code-block:: text

   IDLE ──► ADDR ──► DATA ──► IDLE
            (stb)   (wait     (ack
             held    for       received)
             until   ack)
             !stall)

1. **IDLE:** When the arbiter asserts ``cyc``, the bridge latches address, data,
   sel, and we, then moves to ADDR.

2. **ADDR:** Asserts ``cyc`` + ``stb`` on the pipelined side. When the slave
   deasserts ``stall`` the request is accepted and the bridge moves to DATA.

3. **DATA:** Holds ``cyc`` (``stb`` deasserted) and waits for ``ack`` or
   ``err``. The response is forwarded back to the classic side and the bridge
   returns to IDLE.

This pattern follows ``ibex_obi2wb.sv`` but simplified for SERV's
single-outstanding, non-pipelined request pattern.

**************
Design Choices
**************

No servile
==========

The upstream SERV distribution includes ``servile``, a convenience wrapper that
bundles the CPU with a memory and fixed address decode. We skip it entirely and
build ``serv_wb_top`` around ``serv_rf_top`` directly. This lets the crossbar
handle all address routing, matching the repo's bus conventions.

Everything on the crossbar
==========================

TCM, timer, sim_ctrl, and external slaves all sit behind the crossbar. There is
no separate memory port or address decode inside the CPU wrapper. This means any
future bus master (e.g., Etherbone for host firmware loading) gets TCM access
for free, just by adding another master port to the crossbar.

Single unified TCM
==================

Unlike the Ibex SoC which has separate ITCM and DTCM, the SERV SoC uses a
single unified memory for both code and data. This is simpler and sufficient for
the small programs the AON subsystem will run.

SERV configuration
==================

==================  ========  ============================================
Parameter           Value     Rationale
==================  ========  ============================================
``W``               1         Bit-serial (smallest possible)
``WITH_CSR``        1         Needed for timer interrupt support
``RESET_STRATEGY``  "MINI"    Minimal reset - only resets FFs needed to
                              restart from RESET_PC
``RESET_PC``        0x0       TCM base address
``COMPRESSED``      0         RV32I only (no C extension)
``MDU``             0         No multiply/divide (RV32I only)
==================  ========  ============================================

***********
Source Code
***********

====================  ====================================================
Component             Location
====================  ====================================================
SERV WB Wrapper       ``hw/ip/cpu/serv/rtl/serv_wb_top.sv``
SoC Package           ``hw/ip/soc/serv_soc/rtl/serv_soc_pkg.sv``
SoC Top               ``hw/ip/soc/serv_soc/rtl/serv_soc_top.sv``
Squirrel Board Top    ``hw/projects/squirrel/serv_soc/rtl/squirrel_serv_top.sv``
Squirrel Core         ``hw/projects/squirrel/serv_soc/rtl/core.sv``
C Toolchain           ``sw/device/serv_soc/``
====================  ====================================================
