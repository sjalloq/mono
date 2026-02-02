System Overview
===============

Architecture Summary
--------------------

The USB Etherbone Bridge provides a high-speed USB3 interface between a host PC and FPGA-based
systems. It implements a multi-channel architecture where different protocols can share the
same physical USB link.

.. code-block:: text

    Host PC (Rust Software)
         |
         | USB 3.0 (FT601)
         v
    +------------------+
    |   FT601 PHY      |  100MHz USB clock <-> sys clock CDC
    +------------------+
         |
         v
    +------------------+
    | USB Depacketizer |  Strips USB headers, extracts channel routing
    +------------------+
         |
         v
    +------------------+
    |   USB Crossbar   |  Routes packets by channel ID (0-255)
    +------------------+
         |
    +----+----+----+----+
    |    |    |    |
    v    v    v    v
   Ch0  Ch1  Ch2  ...   User Ports
    |    |    |
    v    v    v
   Etherbone  TLP Monitor  USB UART
    |                        |
    v                        v
   Wishbone Bus           CPU printf/REPL


Key Features
------------

* **Multi-channel architecture**: Up to 256 logical channels over single USB link
* **Etherbone protocol**: Standard Wishbone access protocol (channel 0)
* **TLP monitoring**: Non-intrusive PCIe packet capture (channel 1)
* **USB UART**: CPU printf and REPL over USB (channel 2)
* **Clock domain crossing**: Automatic CDC between 100MHz USB and system clocks
* **Extensible**: Easy to add new channel handlers

Channel Allocation
------------------

+---------+-------------+------------------------------------------+
| Channel | Protocol    | Description                              |
+=========+=============+==========================================+
| 0       | Etherbone   | Wishbone read/write access               |
+---------+-------------+------------------------------------------+
| 1       | TLP Monitor | PCIe TLP packet streaming                |
+---------+-------------+------------------------------------------+
| 2       | USB UART    | CPU printf output and REPL input         |
+---------+-------------+------------------------------------------+
| 3-255   | User        | Available for custom protocols           |
+---------+-------------+------------------------------------------+


Data Flow
---------

RX Path (Host to FPGA)
~~~~~~~~~~~~~~~~~~~~~~

1. Host software sends USB packet with channel ID and payload
2. FT601 PHY receives data, crosses to system clock domain
3. Depacketizer detects preamble, extracts header fields
4. Crossbar routes payload to appropriate channel handler
5. Channel handler processes data (e.g., Etherbone executes Wishbone transaction)

TX Path (FPGA to Host)
~~~~~~~~~~~~~~~~~~~~~~

1. Channel handler generates response with channel ID
2. Crossbar arbitrates among active channels
3. Packetizer prepends USB header (preamble, channel, length)
4. FT601 PHY transmits via USB3

Clock Domains
-------------

+-----------+------------+-------------------------------------------+
| Domain    | Frequency  | Usage                                     |
+===========+============+===========================================+
| usb       | 100 MHz    | FT601 PHY, FIFO interface                 |
+-----------+------------+-------------------------------------------+
| sys       | Variable   | Core logic, Etherbone, monitor            |
+-----------+------------+-------------------------------------------+

Async FIFOs (128 entries each) handle the clock domain crossing between USB and system clocks.
