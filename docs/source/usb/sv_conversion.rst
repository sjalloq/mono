SystemVerilog Conversion Strategy
=================================

Overview
--------

This document outlines the strategy for converting the USB Etherbone Bridge
from Migen/LiteX to SystemVerilog, with consideration for the Fusesoc generator
approach that auto-converts Migen to Verilog.


Conversion Complexity Assessment
--------------------------------

+----------------------+------------+------------------------------------------------+
| Component            | Complexity | Recommendation                                 |
+======================+============+================================================+
| FT601 PHY            | Low        | Native SV - self-contained, clear timing       |
+----------------------+------------+------------------------------------------------+
| USB Depacketizer     | Low-Med    | Native SV or Fusesoc generator                 |
+----------------------+------------+------------------------------------------------+
| USB Packetizer       | Low        | Native SV or Fusesoc generator                 |
+----------------------+------------+------------------------------------------------+
| USB Crossbar         | Medium     | Native SV - better tool optimization           |
+----------------------+------------+------------------------------------------------+
| Etherbone Adapter    | High       | Fusesoc generator - LiteEth dependency         |
+----------------------+------------+------------------------------------------------+
| TLP Capture Engine   | Medium     | Native SV - good candidate                     |
+----------------------+------------+------------------------------------------------+
| Monitor FIFOs        | Low        | Vendor IP or open-source                       |
+----------------------+------------+------------------------------------------------+
| Monitor Arbiter      | Low-Med    | Native SV                                      |
+----------------------+------------+------------------------------------------------+


Fusesoc Generator Approach
--------------------------

The Fusesoc generator can auto-convert Migen modules to Verilog at build time.
This is particularly useful for:

**Good Candidates:**

* Modules with complex FSMs but no vendor primitives
* LiteX/LiteEth protocol implementations
* Modules that are stable and don't need SV-specific features

**Poor Candidates:**

* Modules using vendor-specific primitives (BRAM, PLL, etc.)
* Performance-critical paths needing SV optimizations
* Modules requiring extensive parameterization

**Integration Pattern:**

.. code-block:: text

    fusesoc.core:
      generators:
        migen_to_verilog:
          command: python -m litex.gen ...
          parameters:
            top_module: USBEtherbone
            output: usb_etherbone.v

    filesets:
      rtl:
        files:
          - usb_etherbone.v  # Generated
          - ft601_phy.sv     # Native SV
        file_type: systemVerilogSource


Recommended Hybrid Strategy
---------------------------

**Phase 1: Native SV Foundation**

Implement core infrastructure in native SystemVerilog:

1. FT601 PHY with parameterized async FIFOs
2. USB packet format (packetizer/depacketizer)
3. Channel crossbar with AXI-Stream interfaces

**Phase 2: Fusesoc Generator for Etherbone**

Use Migen-to-Verilog generator for Etherbone:

1. Wrap LiteEth Etherbone in thin adapter
2. Generate Verilog via Fusesoc
3. Instantiate in SV top-level

**Phase 3: Native SV Monitor**

Implement TLP monitor in native SV:

1. Parameterized capture engine
2. Vendor FIFO IP for width conversion
3. Clean AXI-Stream interfaces


Interface Mapping
-----------------

**Migen Stream to AXI-Stream:**

.. code-block:: text

    Migen               AXI-Stream
    ──────────────────────────────────
    valid               tvalid
    ready               tready
    data                tdata
    last                tlast
    first               (derived from tlast history)
    error               (side-channel or tuser)

**Wishbone to AXI-Lite (Optional):**

If downstream infrastructure uses AXI, consider adding a Wishbone-to-AXI-Lite
bridge. Otherwise, keep Wishbone for direct LiteX compatibility.


Native SV Module Templates
--------------------------

**FT601 PHY Interface:**

.. code-block:: systemverilog

    module ft601_phy #(
        parameter DATA_WIDTH = 32,
        parameter FIFO_DEPTH = 128
    ) (
        // System interface
        input  logic        sys_clk,
        input  logic        sys_rst,

        // FT601 pins
        input  logic        usb_clk,
        inout  wire [31:0]  usb_data,
        inout  wire [3:0]   usb_be,
        input  logic        usb_rxf_n,
        input  logic        usb_txe_n,
        output logic        usb_rd_n,
        output logic        usb_wr_n,
        output logic        usb_oe_n,
        output logic        usb_siwu_n,
        output logic        usb_rst_n,

        // RX AXI-Stream (to system)
        output logic [31:0] rx_tdata,
        output logic        rx_tvalid,
        input  logic        rx_tready,

        // TX AXI-Stream (from system)
        input  logic [31:0] tx_tdata,
        input  logic        tx_tlast,
        input  logic        tx_tvalid,
        output logic        tx_tready
    );

**USB Crossbar Interface:**

.. code-block:: systemverilog

    module usb_crossbar #(
        parameter NUM_CHANNELS = 4,
        parameter DATA_WIDTH = 32
    ) (
        input  logic clk,
        input  logic rst,

        // From depacketizer
        input  logic [DATA_WIDTH-1:0] rx_tdata,
        input  logic [7:0]            rx_tdest,
        input  logic                  rx_tlast,
        input  logic                  rx_tvalid,
        output logic                  rx_tready,

        // To packetizer
        output logic [DATA_WIDTH-1:0] tx_tdata,
        output logic [7:0]            tx_tdest,
        output logic [31:0]           tx_tlen,
        output logic                  tx_tlast,
        output logic                  tx_tvalid,
        input  logic                  tx_tready,

        // User ports (arrays)
        // ... per-channel AXI-Stream interfaces
    );


Testing Strategy
----------------

**Simulation:**

1. Use existing Rust software as reference for packet formats
2. Create SV testbenches that generate/verify USB packets
3. Compare Migen vs SV simulation results

**Hardware Validation:**

1. Use existing host software unchanged
2. Verify Etherbone read/write operations
3. Verify TLP monitor streaming
4. Performance comparison (throughput, latency)


Migration Path
--------------

**Step 1: Parallel Implementation**

* Keep Migen implementation as reference
* Develop SV modules alongside
* Use Fusesoc to select implementation

**Step 2: Component Swap**

* Replace one component at a time
* Validate each swap with existing tests
* Start with FT601 PHY (lowest risk)

**Step 3: Full SV (Optional)**

* If Etherbone complexity warrants, implement natively
* Or keep Fusesoc generator for LiteEth components
* Document any behavioral differences


Multi-Channel Architecture Preservation
---------------------------------------

The key architectural feature to preserve is the multi-channel capability:

**Requirements:**

1. Channel ID field (8 bits) in packet header
2. Crossbar routing based on channel ID
3. Independent flow control per channel
4. Extensible for new channel handlers

**SV Implementation:**

.. code-block:: systemverilog

    // Channel port definition
    typedef struct packed {
        logic [7:0]  channel_id;
        logic [31:0] length;
    } usb_channel_header_t;

    // Per-channel interface
    interface usb_channel_if #(
        parameter DATA_WIDTH = 32
    );
        logic [DATA_WIDTH-1:0] tdata;
        logic                  tlast;
        logic                  tvalid;
        logic                  tready;
        usb_channel_header_t   header;

        modport master (output tdata, tlast, tvalid, header, input tready);
        modport slave  (input tdata, tlast, tvalid, header, output tready);
    endinterface

This allows easy addition of new channel handlers while maintaining
compatibility with the existing USB packet protocol and host software.
