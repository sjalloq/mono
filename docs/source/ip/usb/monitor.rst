TLP Monitor Subsystem
=====================

Overview
--------

The TLP Monitor provides non-intrusive capture of PCIe Transaction Layer Packets
(TLPs) for debugging and analysis. Captured packets are streamed to the host
via USB channel 1.

Architecture
------------

.. code-block:: text

    PCIe Core
    ┌─────────────────────────────────────┐
    │  RX Request  │  RX Completion       │
    │  RX Compl.   │  TX Request          │
    └──────┬───────┴────────┬─────────────┘
           │                │
           v                v
    ┌──────────────┐ ┌──────────────┐
    │ Pipeline Reg │ │ Pipeline Reg │  (1 cycle latency)
    └──────┬───────┘ └──────┬───────┘
           │                │
           v                v
    ┌──────────────┐ ┌──────────────┐
    │ TLP Capture  │ │ TLP Capture  │
    │ Engine (RX)  │ │ Engine (TX)  │
    └──────┬───────┘ └──────┬───────┘
           │                │
    ┌──────┴────┐    ┌──────┴────┐
    │Hdr  │Pyld │    │Hdr  │Pyld │
    │FIFO │FIFO │    │FIFO │FIFO │
    └──┬──┴──┬──┘    └──┬──┴──┬──┘
       │     │          │     │
       v     v          v     v
    ┌─────────────────────────────────────┐
    │       Monitor Packet Arbiter        │
    └──────────────────┬──────────────────┘
                       │
                       v
                 USB Channel 1


Supported TLP Types
-------------------

+------+----------+--------------------------------+
| Code | Type     | Description                    |
+======+==========+================================+
| 0x0  | MRd      | Memory Read Request            |
+------+----------+--------------------------------+
| 0x1  | MWr      | Memory Write Request           |
+------+----------+--------------------------------+
| 0x2  | Cpl      | Completion (no data)           |
+------+----------+--------------------------------+
| 0x3  | CplD     | Completion with Data           |
+------+----------+--------------------------------+
| 0x4  | MsiX     | MSI-X Interrupt                |
+------+----------+--------------------------------+
| 0x5  | AtsReq   | ATS Translation Request        |
+------+----------+--------------------------------+
| 0x6  | AtsCpl   | ATS Translation Completion     |
+------+----------+--------------------------------+
| 0x7  | AtsInv   | ATS Invalidation               |
+------+----------+--------------------------------+


Capture Engine
--------------

Each capture engine taps a PCIe stream without consuming data.

**Operation:**

1. **First Beat Detection:**

   * Check if header FIFO has space
   * If full: drop entire packet, increment ``dropped`` counter
   * If ready: latch all header fields, prepare for payload

2. **Payload Capture:**

   * Write 64-bit data words to payload FIFO
   * If FIFO backpressures mid-packet: mark truncated, continue
   * Track actual payload count vs expected

3. **Last Beat Processing:**

   * Write 256-bit header to header FIFO
   * Include truncation flag and final payload count
   * Increment ``captured`` counter

**Tap Interface:**

The capture engine observes streams without backpressure:

.. code-block:: text

    Signal      Dir     Description
    ──────────────────────────────────────────
    valid       in      Data valid (from PCIe)
    ready       in      Downstream ready (observed)
    first       in      First beat of packet
    last        in      Last beat of packet
    data        in      TLP data (64-bit)
    <header>    in      TLP header fields


Header Format
-------------

Each captured TLP has a 256-bit (32-byte) header transmitted as 8 x 32-bit words:

**Word 0:**

.. code-block:: text

    [9:0]   payload_length   DW count from TLP header
    [13:10] tlp_type         Encoded TLP type (0-7)
    [14]    direction        0=RX (inbound), 1=TX (outbound)
    [15]    truncated        Payload was truncated
    [31:16] header_wcount    Fixed value: 4
    [63:32] timestamp[31:0]  Low 32 bits of timestamp

**Word 1:**

.. code-block:: text

    [31:0]  timestamp[63:32] High 32 bits of timestamp
    [47:32] req_id           Requester ID
    [55:48] tag              Transaction tag
    [59:56] first_be         First DW byte enables
    [63:60] last_be          Last DW byte enables

**Word 2:**

.. code-block:: text

    [63:0]  address          64-bit address

**Word 3 (RX direction):**

.. code-block:: text

    [0]     we               Write enable (from TLP type)
    [3:1]   bar_hit          BAR hit indicator
    [5:4]   attr             Attributes (relaxed ordering, etc.)
    [7:6]   at               Address type
    [8]     pasid_valid      PASID valid flag
    [28:9]  pasid            Process Address Space ID
    [29]    privileged       Privileged mode request
    [30]    execute          Execute request

**Word 3 (TX direction):**

.. code-block:: text

    [0]     we               Write enable
    [3:1]   status           Completion status (completions only)
    [5:4]   attr             Attributes
    [7:6]   at               Address type
    [8]     pasid_valid      PASID valid flag
    [28:9]  pasid            Process Address Space ID
    [29]    status_bit0      Status bit 0 (completions)
    [30]    status_bit1      Status bit 1 (completions)
    [47:32] cmp_id           Completer ID (completions)
    [63:48] byte_count       Byte count (completions)


USB Packet Format
-----------------

Monitor data on USB channel 1:

.. code-block:: text

    USB Header (12 bytes):
      Preamble:  0x5aa55aa5
      Channel:   1
      Length:    32 + (payload_dwords * 4)

    Header (32 bytes):
      4 x 64-bit words, transmitted as 8 x 32-bit LE

    Payload (variable):
      payload_dwords x 32-bit words
      Padded to even count if necessary


FIFOs
-----

**Header FIFO:**

* Input: 256 bits (4 x 64-bit words)
* Output: 32 bits
* Depth: 4 entries
* Width conversion: 256-to-32

**Payload FIFO:**

* Input: 64 bits
* Output: 32 bits
* Depth: 512 entries (1 BRAM)
* Width conversion: 64-to-32


Arbiter
-------

The arbiter multiplexes RX and TX capture streams to USB channel 1.

**Priority:** RX has priority over TX.

**Packet Atomicity:** Complete packets are transmitted before switching sources.

**State Machine:**

.. code-block:: text

    IDLE ──> HEADER ──> PAYLOAD ──> [PAD] ──> IDLE

**PAD State:**

If payload has odd DW count, a padding word is inserted to maintain
32-bit alignment for the USB interface.


Control and Status
------------------

**Control Signals:**

.. code-block:: text

    rx_enable       Enable RX capture
    tx_enable       Enable TX capture
    clear_stats     Clear statistics counters
    timestamp       64-bit timestamp input (from system)

**Statistics:**

.. code-block:: text

    rx_captured     Packets successfully captured (RX)
    rx_dropped      Packets dropped - header FIFO full (RX)
    rx_truncated    Packets truncated - payload FIFO full (RX)
    tx_captured     Packets successfully captured (TX)
    tx_dropped      Packets dropped (TX)
    tx_truncated    Packets truncated (TX)


SystemVerilog Conversion Notes
------------------------------

**Moderate Complexity - Good Candidate for Native SV:**

The monitor subsystem is relatively self-contained:

* Clear state machines for capture logic
* Standard FIFO interfaces
* Well-defined header format
* No complex external dependencies

**Recommended Approach:**

1. Implement capture engine as parameterized SV module
2. Use vendor FIFO IP for width conversion
3. Arbiter is straightforward round-robin with packet boundaries

**Key Considerations:**

* Tap interface must not add backpressure to PCIe
* Pipeline registers critical for timing closure
* Consider making TLP type filtering configurable
* Header format should match software parser exactly
