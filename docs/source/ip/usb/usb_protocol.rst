USB Packet Protocol
===================

Packet Format
-------------

All USB communication uses a simple framing protocol:

.. code-block:: text

    +----------------+----------------+----------------+----------------+
    |    Preamble    |    Channel     |     Length     |    Payload     |
    |   (4 bytes)    |   (4 bytes)    |   (4 bytes)    |   (variable)   |
    +----------------+----------------+----------------+----------------+

    Bytes 0-3:   0x5aa55aa5 (preamble/sync pattern)
    Bytes 4-7:   Channel ID (32-bit LE, only lower 8 bits used)
    Bytes 8-11:  Payload length in bytes (32-bit LE)
    Bytes 12+:   Payload data


Field Descriptions
------------------

Preamble (0x5aa55aa5)
    Sync pattern for packet detection. The depacketizer continuously searches
    for this pattern to find packet boundaries.

Channel ID
    8-bit logical channel identifier (0-255). Upper 24 bits reserved (zero).
    Routes packets through the crossbar to appropriate handlers.

Length
    Payload length in bytes. The depacketizer converts this to 32-bit word
    count internally for last-beat detection.

Payload
    Variable-length data. Must be 32-bit aligned (padded if necessary).


Depacketizer
------------

The depacketizer strips USB headers and routes payloads to the crossbar.

**State Machine:**

.. code-block:: text

    IDLE ──> RECEIVE_HEADER ──> COPY ──> IDLE
      ^                           │
      └───────────────────────────┘

**States:**

IDLE
    Search input stream for preamble pattern (0x5aa55aa5).
    When found, transition to RECEIVE_HEADER.

RECEIVE_HEADER
    Capture channel ID (word 1) and length (word 2).
    Calculate word count from byte length.
    Transition to COPY.

COPY
    Pass payload words to crossbar with channel routing info.
    Track word count to detect last beat.
    Return to IDLE after last word.

**Timeout Handling:**

A configurable timeout (default: 10 seconds at system clock rate) resets
the state machine if a packet is not completed. This prevents lockup
from corrupted or partial packets.

**Output Stream:**

.. code-block:: text

    Signal      Width   Description
    ──────────────────────────────────────────
    data        32      Payload data word
    dst         8       Channel ID
    length      32      Original byte length
    last        1       Last word of packet
    valid       1       Data valid
    ready       1       Downstream ready


Packetizer
----------

The packetizer prepends USB headers to outgoing data.

**Operation:**

1. Accept stream with channel ID and payload
2. Generate 3-word header (preamble, channel, length)
3. Pass through payload unchanged
4. Assert ``last`` on final word

**Input Stream:**

Requires ``dst`` (channel), ``length`` (bytes), and payload data.


USB Crossbar
------------

The crossbar provides multi-channel multiplexing/demultiplexing.

**Architecture:**

.. code-block:: text

    From PHY              To PHY
        │                    ^
        v                    │
    ┌────────┐          ┌────────┐
    │Dispatch│          │Arbiter │
    │  er    │          │        │
    └────────┘          └────────┘
        │                    ^
    ┌───┴───┬───┐        ┌───┴───┬───┐
    v       v   v        │       │   │
    Ch0    Ch1  ChN     Ch0    Ch1  ChN

**RX Dispatcher:**

Routes incoming packets by ``dst`` field to appropriate user port.
Only the targeted port sees the packet.

**TX Arbiter:**

Round-robin arbitration among user ports with data to send.
Packet-atomic: completes entire packet before switching sources.

**User Port Interface:**

.. code-block:: text

    USBUserPort:
        sink    endpoint    TX path (to host)
        source  endpoint    RX path (from host)
        tag     int         Channel ID

**Stream Description (usb_channel_description):**

.. code-block:: text

    Parameter   Width   Description
    ──────────────────────────────────────────
    dst         8       Destination channel ID
    length      32      Payload length (bytes)

    Payload:
    data        32      Data word
    error       4       Error flags (one per byte)
    last        1       Last word indicator


SystemVerilog Conversion Notes
------------------------------

The USB protocol layer is moderately complex to convert:

**Straightforward:**

* Packet format is well-defined and simple
* State machines are clear and documented
* No complex Migen-specific constructs

**Considerations:**

1. LiteX stream protocol maps to AXI-Stream with minor differences
2. The ``error`` field per-byte is unusual - consider if needed
3. Crossbar arbiter can use standard round-robin implementation
4. Consider parameterizing number of channels for flexibility

**Reuse via Fusesoc Generator:**

The depacketizer and packetizer could potentially be auto-generated from
Migen if they don't use vendor primitives. The crossbar is more complex
and may benefit from native SV implementation for better tool optimization.
