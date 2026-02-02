########
Ibex SoC
########

The Ibex SoC is a minimal RISC-V system built around the lowRISC Ibex core,
intended for embedded control and hardware validation.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   memory_map
   c_toolchain

**********
Components
**********

* **Ibex CPU** - 32-bit RISC-V core (RV32IMC)
* **ITCM** - 16KB instruction tightly-coupled memory
* **DTCM** - 16KB data tightly-coupled memory
* **Timer** - RISC-V standard mtime/mtimecmp
* **SimCtrl** - Simulation control (printf + halt for Verilator)
* **Etherbone** - USB host interface for register access

************
Architecture
************

.. code-block:: text

   ┌────────────────────────────────────────────────────────────┐
   │                        ibex_soc_top                        │
   │                                                            │
   │  ┌─────────────────────┐                                   │
   │  │    ibex_wb_top      │                                   │
   │  │  ┌───────────────┐  │                                   │
   │  │  │   ibex_top    │  │   ┌───────────────┐               │
   │  │  └───────────────┘  │   │ Etherbone     │               │
   │  │    │           │    │   │ (USB host)    │               │
   │  │  ibus        dbus   │   └──────┬────────┘               │
   │  └────┼───────────┼────┘          │                        │
   │       │           │               │                        │
   │       │  Master 0 │  Master 1     │ Master 2               │
   │       ▼           ▼               ▼                        │
   │  ┌──────────────────────────────────────────────────────┐  │
   │  │                   wb_crossbar (3x4)                  │  │
   │  └──────┬─────────────────┬────────────┬────────┬───────┘  │
   │         │                 │            │        │          │
   │     Slave 0           Slave 1      Slave 2   Slave 3       │
   │         ▼                 ▼            ▼        ▼          │
   │  ┌──────────┐      ┌─────────┐   ┌───────┐ ┌─────────┐     │
   │  │   ITCM   │      │   DTCM  │   │ Timer │ │ SimCtrl │     │
   │  │  16KB    │      │  16KB   │   │       │ │         │     │
   │  └──────────┘      └─────────┘   └───────┘ └─────────┘     │
   └────────────────────────────────────────────────────────────┘

***********
Source Code
***********

===============  ================================================
Component        Location
===============  ================================================
SoC Package      ``hw/ip/soc/ibex_soc/rtl/ibex_soc_pkg.sv``
SoC Top          ``hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv``
C Toolchain      ``sw/device/ibex_soc/``
===============  ================================================
