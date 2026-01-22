####################
Repository Structure
####################

This repository is organized as a monorepo for FPGA development, containing
hardware designs, host software, and device firmware across multiple boards
and projects.

*********
Top Level
*********

.. code-block:: text

   mono/
   ├── hw/                    # Hardware (gateware)
   │   ├── ip/                # Reusable IP blocks
   │   ├── boards/            # Board support packages
   │   └── projects/          # Top-level integrations
   ├── sw/                    # Software
   │   ├── host/              # PC-side tooling
   │   └── device/            # Embedded firmware
   ├── mono/                  # Python package (Migen/LiteX)
   └── docs/                  # Documentation

********
Hardware
********

The hardware tree is organized to maximize IP reuse across boards and projects.

IP Blocks (``hw/ip/``)
======================

Reusable gateware modules that are board-agnostic:

.. code-block:: text

   hw/ip/
   ├── usb/                   # USB cores (FT601, packetizer)
   ├── pcie/                  # PCIe endpoint, TLP handling
   └── common/                # FIFOs, CDCs, arbiters

Each IP block has its own FuseSoC ``.core`` file defining its interface and
dependencies.

Board Support (``hw/boards/``)
==============================

Board-specific definitions and common constraints:

.. code-block:: text

   hw/boards/
   └── squirrel/
       ├── board.yaml         # Clock frequencies, memory map, capabilities
       ├── pinout.yaml        # All available pins with properties
       ├── common.xdc         # Timing constraints, clock definitions
       └── ip/                # Board-level IP (DDR PHY, clock wizard)

The ``pinout.yaml`` provides a canonical source for pin assignments that can
be consumed by FuseSoC generators to produce project-specific constraint files.

Projects (``hw/projects/``)
===========================

Top-level integrations that combine IP blocks for a specific board:

.. code-block:: text

   hw/projects/
   └── squirrel/
       └── tlp_debug/
           ├── top.sv         # Top-level wrapper
           ├── pins.yaml      # Required pins (subset of board pinout)
           └── project.core   # FuseSoC core file

Projects are intentionally thin - most logic lives in ``hw/ip/``. The project
provides:

- Top-level port mapping
- Tool flow configuration (synthesis, P&R settings)
- Project-specific pin assignments

********
Software
********

Host Software (``sw/host/``)
============================

PC-side tooling for interacting with FPGA designs. Organized by tool/library
rather than by board, since most host tools work across multiple boards:

.. code-block:: text

   sw/host/
   ├── Cargo.toml             # Workspace root
   ├── ft601/                 # FT601 USB bridge library
   │   └── src/
   │       ├── lib.rs         # Bridge API, Etherbone protocol
   │       ├── etherbone.rs   # Etherbone packet encode/decode
   │       └── usb.rs         # Low-level USB communication
   ├── eb/                    # Etherbone CLI (register read/write)
   └── tlp-mon/               # PCIe TLP packet monitor

**Key tools:**

``eb``
   Command-line tool for direct Wishbone register access via Etherbone
   protocol over USB. Supports read, write, dump, and FIFO operations.

``tlp-mon``
   Real-time PCIe TLP packet capture and decode from the USB monitor stream.

Device Firmware (``sw/device/``)
================================

Embedded firmware running on soft or hard CPUs within the FPGA. Organized by
board since firmware is tightly coupled to the hardware memory map:

.. code-block:: text

   sw/device/
   ├── squirrel/
   │   └── tlp_debug/         # Firmware for TLP debug project
   └── libs/                  # Shared embedded libraries (HAL, drivers)

**************
Python Package
**************

The ``mono/`` Python package contains Migen/LiteX modules and utilities:

.. code-block:: text

   mono/
   ├── gateware/              # Migen modules
   │   ├── usb/               # USB gateware (FT601, Etherbone)
   │   └── wrappers/          # MigenWrapper implementations
   ├── migen/                 # Migen utilities (netlister)
   └── utils/                 # General utilities

See :doc:`tools/migen_netlister` for details on the Migen-to-Verilog workflow.

**********
Generators
**********

FuseSoC generators live in ``hw/generators/``:

.. code-block:: text

   hw/generators/
   ├── generators.core        # Generator registration
   ├── migen_netlister.py     # Migen module -> Verilog
   └── xdc_generator.py       # pinout.yaml -> constraints.xdc (planned)

***********
Conventions
***********

File Extensions
===============

- ``.sv`` - Hand-written SystemVerilog
- ``.v`` - Generated Verilog (from Migen)
- ``.core`` - FuseSoC core files (YAML format)

Naming
======

- IP blocks use lowercase with underscores: ``usb_core``, ``axi_crossbar``
- Board names match physical hardware: ``squirrel``, ``kintex_pcie``
- Project names describe function: ``tlp_debug``, ``usb_analyzer``
