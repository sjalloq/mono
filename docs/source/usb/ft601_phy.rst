FT601 PHY Interface
===================

Overview
--------

The FT601 is a USB 3.0 to FIFO bridge IC from FTDI. It presents a 32-bit synchronous
FIFO interface to the FPGA running at 100MHz.

Pin Interface
-------------

+----------+------+--------+------------------------------------------------+
| Signal   | Dir  | Width  | Description                                    |
+==========+======+========+================================================+
| clk      | in   | 1      | 100MHz clock from FT601                        |
+----------+------+--------+------------------------------------------------+
| data     | bidir| 32     | Bidirectional data bus                         |
+----------+------+--------+------------------------------------------------+
| be       | out  | 4      | Byte enables (directly from stream)            |
+----------+------+--------+------------------------------------------------+
| rxf_n    | in   | 1      | RX FIFO not empty (active low)                 |
+----------+------+--------+------------------------------------------------+
| txe_n    | in   | 1      | TX FIFO not full (active low)                  |
+----------+------+--------+------------------------------------------------+
| rd_n     | out  | 1      | Read strobe (active low)                       |
+----------+------+--------+------------------------------------------------+
| wr_n     | out  | 1      | Write strobe (active low)                      |
+----------+------+--------+------------------------------------------------+
| oe_n     | out  | 1      | Output enable for data bus (active low)        |
+----------+------+--------+------------------------------------------------+
| siwu_n   | out  | 1      | Send immediate / wake up (active low)          |
+----------+------+--------+------------------------------------------------+
| rst_n    | out  | 1      | Reset (active low)                             |
+----------+------+--------+------------------------------------------------+


State Machine
-------------

The PHY implements a 13-state FSM based on the PCILeech timing model:

.. code-block:: text

    IDLE ──┬──> RX_WAIT1 -> RX_WAIT2 -> RX_WAIT3 -> RX_ACTIVE -> RX_COOLDOWN1 -> RX_COOLDOWN2 ──┐
           │                                                                                    │
           └──> TX_WAIT1 -> TX_WAIT2 -> TX_ACTIVE -> TX_COOLDOWN1 -> TX_COOLDOWN2 ──────────────┴──> IDLE

**State Descriptions:**

IDLE
    Check status flags. RX has priority over TX. Transition to RX_WAIT1 if ``rxf_n=0``,
    else TX_WAIT1 if ``txe_n=0`` and data available.

RX_WAIT1
    First wait cycle after ``rxf_n`` sampled LOW.

RX_WAIT2
    Evaluate ``oe_n_d=0``. Registered ``oe_n`` goes LOW on next posedge (W2→W3).

RX_WAIT3
    Evaluate ``rd_n_d=0``. Registered ``rd_n`` goes LOW on next posedge (W3→ACT).
    FT601 starts driving data in response to ``oe_n`` going LOW.

RX_ACTIVE
    Capture data on each clock. Continue while ``rxf_n=0``. Data is registered
    with 1-cycle latency to meet timing.

RX_COOLDOWN1/2
    Deassert control signals, allow bus to settle before next operation.

TX_WAIT1
    Prepare to transmit. Deassert ``oe_n`` (FPGA drives bus).

TX_WAIT2
    Assert ``wr_n=0``, latch first data word.

TX_ACTIVE
    Output data words. Continue while ``txe_n=0`` and data available.

TX_COOLDOWN1/2
    Complete write transaction, prepare for next operation.


Timing Diagram (RX — 3 data words)
-----------------------------------

.. code-block:: text

    CLK     ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
             └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘

    rxf_n   ─────┐                               ┌───────
                 └───────────────────────────────┘

    oe_n    ─────────────┐                           ┌───
                         └───────────────────────────┘

    rd_n    ─────────────────┐                       ┌───
                             └───────────────────────┘

    data    ─────────────────────X D0 X D1 X D2 X────────

    State    IDLE W1  W2  W3  ACT  ACT  ACT  CD1 CD2


Clock Domain Crossing
---------------------

Two async FIFOs handle the CDC between USB (100MHz) and system clocks:

**RX FIFO** (USB write, sys read):

* Depth: 128 entries
* Width: 32 bits data + valid
* Small staging buffer (4 entries) in USB domain for timing alignment

**TX FIFO** (sys write, USB read):

* Depth: 128 entries
* Width: 32 bits data + last

The PHY does not support backpressure from the FT601; buffering via async FIFOs
absorbs any rate mismatch.


SystemVerilog Conversion Notes
------------------------------

The FT601 PHY is a good candidate for direct SV implementation:

* **Self-contained**: No external Migen/LiteX dependencies except async FIFO
* **Well-defined interface**: Standard FIFO protocol with clear timing
* **Testable**: Can be verified with standard USB/FIFO testbench patterns

Key considerations:

1. Use standard async FIFO IP (e.g., from vendor or open-source)
2. Tristate handling differs by vendor - may need wrapper
3. Registered data path critical for timing closure
4. Consider adding optional FIFO depth parameterization
