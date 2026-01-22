Etherbone Protocol Adapter
==========================

Overview
--------

Etherbone is a protocol for tunneling Wishbone transactions over a network or
streaming interface. This implementation adapts the LiteEth Etherbone core
to work over USB channels instead of Ethernet.

The adapter sits on USB channel 0 and provides a Wishbone master interface
for accessing FPGA registers and memory.


Protocol Stack
--------------

.. code-block:: text

    ┌─────────────────────────────┐
    │    Wishbone Transactions    │  CSR/memory access
    ├─────────────────────────────┤
    │    LiteEth Etherbone Core   │  Record encoding/decoding
    ├─────────────────────────────┤
    │    USB Etherbone Adapter    │  USB<->Etherbone format
    ├─────────────────────────────┤
    │    USB Packet Protocol      │  Framing, channel routing
    ├─────────────────────────────┤
    │    FT601 PHY                │  USB3 physical interface
    └─────────────────────────────┘


Etherbone Packet Format
-----------------------

**Header (8 bytes):**

.. code-block:: text

    Bytes 0-1:  Magic number (0x4e6f, big-endian)
    Byte 2:     Flags
                  [7:4] Version (0x1)
                  [1]   Probe reply flag
                  [0]   Probe request flag
    Byte 3:     Sizes
                  [7:4] Address size (0x4 = 32-bit)
                  [3:0] Port size (0x4 = 32-bit)
    Bytes 4-7:  Padding (reserved)

**Record Format (variable):**

.. code-block:: text

    Byte 0:     Flags
                  [7] BCA - Bus cycle abort
                  [6] RCA - Read cycle abort
                  [5] RFF - Read FIFO flag
                  [4] Reserved
                  [3] CYC - Cycle flag
                  [2] WCA - Write cycle abort
                  [1] WFF - Write FIFO flag
                  [0] Reserved
    Byte 1:     Byte enable (0x0f for 32-bit)
    Byte 2:     Write count (number of write operations)
    Byte 3:     Read count (number of read operations)
    Bytes 4+:   Base address (4 bytes if read_count > 0 or write_count > 0)
                Write data (4 bytes each, write_count times)
                Read addresses (4 bytes each, read_count times)


Probe Mechanism
---------------

Etherbone supports a probe/discovery mechanism:

**Probe Request:**

* Magic: 0x4e6f
* Flags: probe bit set (0x01)
* No records

**Probe Reply:**

* Magic: 0x4e6f
* Flags: probe_reply bit set (0x02)
* Reports supported address/port sizes


Component Architecture
----------------------

USBEtherbonePacketRX
~~~~~~~~~~~~~~~~~~~~

Receives USB packets and converts to Etherbone format.

**Operation:**

1. Receive packet from USB crossbar (channel 0)
2. Use LiteX Depacketizer to extract Etherbone header
3. Validate magic number (0x4e6f)
4. Route to probe handler or record layer

**Invalid Packet Handling:**

Packets with invalid magic are silently dropped. No error response is generated.

USBEtherbonePacketTX
~~~~~~~~~~~~~~~~~~~~

Converts Etherbone responses to USB format.

**Operation:**

1. Receive Etherbone packet from record layer
2. Use LiteX Packetizer to prepend header
3. Set USB channel ID (0) and packet length
4. Send to USB crossbar

USBEtherbone (Top-Level)
~~~~~~~~~~~~~~~~~~~~~~~~

Integrates all components and provides Wishbone master interface.

.. code-block:: text

    USB Crossbar Port (Ch 0)
           │
           v
    ┌──────────────┐
    │ PacketRX     │──> Probe Handler ──┐
    └──────────────┘                    │
           │                            v
           v                    ┌──────────────┐
    ┌──────────────┐           │ PacketTX     │
    │ Record Layer │──────────>└──────────────┘
    └──────────────┘                    │
           │                            v
           v                    USB Crossbar Port
    ┌──────────────┐
    │ Wishbone     │
    │ Master       │
    └──────────────┘
           │
           v
    System Wishbone Bus


Transaction Examples
--------------------

**Single Read:**

.. code-block:: text

    Request:
      USB Header: preamble, ch=0, len=16
      EB Header:  magic=0x4e6f, version=1, addr_size=4, port_size=4
      Record:     wcount=0, rcount=1, base_addr=0x00000000

    Response:
      USB Header: preamble, ch=0, len=16
      EB Header:  magic=0x4e6f, version=1
      Record:     wcount=1, rcount=0, base_addr=0x00000000, data=0xDEADBEEF

**Single Write:**

.. code-block:: text

    Request:
      USB Header: preamble, ch=0, len=20
      EB Header:  magic=0x4e6f, version=1
      Record:     wcount=1, rcount=0, base_addr=0x00001000, data=0x12345678

    Response:
      (typically no response for writes, or ACK record)


Parameters
----------

+---------------+---------+-------------------------------------------------+
| Parameter     | Default | Description                                     |
+===============+=========+=================================================+
| channel_id    | 0       | USB channel for Etherbone traffic               |
+---------------+---------+-------------------------------------------------+
| buffer_depth  | 4       | Record packet buffer depth                      |
+---------------+---------+-------------------------------------------------+


Wishbone Master Interface
-------------------------

The Etherbone core provides a standard Wishbone master:

.. code-block:: text

    Signal      Width   Description
    ──────────────────────────────────────────
    cyc         1       Bus cycle active
    stb         1       Strobe (valid transfer)
    we          1       Write enable
    adr         32      Address
    dat_w       32      Write data
    dat_r       32      Read data
    ack         1       Transfer acknowledge
    err         1       Error response


SystemVerilog Conversion Notes
------------------------------

**High Complexity - Consider Keeping as Migen:**

The Etherbone adapter heavily depends on LiteEth's Etherbone implementation,
which includes:

* Complex packetizer/depacketizer FSMs
* Record encoding/decoding logic
* Wishbone master with burst support
* Probe handling

**Recommended Approach:**

1. Use Fusesoc generator to auto-convert Migen to Verilog
2. Wrap generated Verilog in SV module for clean interface
3. Alternatively, use existing open-source Etherbone implementations

**If Native SV Needed:**

* Consider simplified subset (single read/write, no bursts)
* Well-documented protocol allows clean-room implementation
* Test against existing Rust software for compatibility
