Host Software
=============

Overview
--------

The host software is implemented in Rust and provides:

* Low-level USB device driver (FT601/d3xx)
* USB packet framing
* Etherbone protocol codec
* TLP packet parser
* High-level Bridge API

Library Structure
-----------------

.. code-block:: text

    src/
    ├── lib.rs          High-level Bridge API
    ├── usb.rs          Low-level USB driver
    ├── etherbone.rs    Etherbone packet codec
    ├── tlp.rs          TLP packet parser
    └── bin/
        ├── eb.rs           Etherbone CLI tool
        ├── debug_usb.rs    USB debugging
        ├── ft601_config.rs Device configuration
        ├── litex-server.rs LiteX server bridge
        └── tlp-mon.rs      TLP monitor client


USB Layer (usb.rs)
------------------

**Device Interface:**

.. code-block:: rust

    pub struct Device {
        inner: D3xxDevice,  // FTDI d3xx library wrapper
    }

    impl Device {
        /// List available FT601 devices
        pub fn list() -> Result<Vec<DeviceInfo>>;

        /// Open first available device
        pub fn open() -> Result<Self>;

        /// Send packet on channel
        pub fn send(channel: u8, payload: &[u8]) -> Result<()>;

        /// Receive packet (blocking with timeout)
        pub fn recv(timeout_ms: u32) -> Result<Option<(u8, Vec<u8>)>>;

        /// Send request and wait for response
        pub fn transact(
            channel: u8,
            request: &[u8],
            timeout_ms: u32
        ) -> Result<Vec<u8>>;
    }

**Packet Functions:**

.. code-block:: rust

    /// Wrap payload with USB header
    pub fn wrap_packet(channel: u8, payload: &[u8]) -> Vec<u8>;

    /// Unwrap USB packet, returns (channel, payload)
    pub fn unwrap_packet(data: &[u8]) -> Option<(u8, Vec<u8>)>;


Etherbone Codec (etherbone.rs)
------------------------------

**Packet Structure:**

.. code-block:: rust

    pub struct Packet {
        pub probe: bool,
        pub probe_reply: bool,
        pub writes: Option<(u32, Vec<u32>)>,  // (base_addr, data)
        pub reads: Option<(u32, Vec<u32>)>,   // (base_addr, addresses)
    }

**Packet Builders:**

.. code-block:: rust

    impl Packet {
        pub fn probe_request() -> Self;
        pub fn probe_reply() -> Self;
        pub fn read(addr: u32) -> Self;
        pub fn read_burst(addrs: Vec<u32>) -> Self;
        pub fn write(addr: u32, data: u32) -> Self;
        pub fn write_burst(base_addr: u32, data: Vec<u32>) -> Self;
    }

**Encoding/Decoding:**

.. code-block:: rust

    impl Packet {
        pub fn encode(&self) -> Vec<u8>;
        pub fn decode(data: &[u8]) -> Option<Self>;
    }


Bridge API (lib.rs)
-------------------

High-level interface for Wishbone access:

.. code-block:: rust

    pub struct Bridge {
        device: Mutex<Device>,
        pub channel: u8,      // USB channel (default 0)
        pub timeout_ms: u32,  // Read timeout
    }

    impl Bridge {
        /// Open first available device
        pub fn open() -> Result<Self>;

        /// Open device by index
        pub fn open_by_index(index: usize) -> Result<Self>;

        /// List available devices
        pub fn list_devices() -> Result<Vec<DeviceInfo>>;

        /// Read single 32-bit word
        pub fn read(addr: u32) -> Result<u32>;

        /// Read multiple addresses
        pub fn read_burst(addrs: &[u32]) -> Result<Vec<u32>>;

        /// Write single 32-bit word
        pub fn write(addr: u32, value: u32) -> Result<()>;

        /// Write burst (sequential addresses)
        pub fn write_burst(base_addr: u32, values: &[u32]) -> Result<()>;

        /// Test connection with probe
        pub fn probe() -> Result<bool>;
    }


TLP Parser (tlp.rs)
-------------------

**TLP Types:**

.. code-block:: rust

    pub enum TlpType {
        MRd = 0x0,      // Memory Read Request
        MWr = 0x1,      // Memory Write Request
        Cpl = 0x2,      // Completion
        CplD = 0x3,     // Completion with Data
        MsiX = 0x4,     // MSI-X
        AtsReq = 0x5,   // ATS Request
        AtsCpl = 0x6,   // ATS Completion
        AtsInv = 0x7,   // ATS Invalidation
    }

    pub enum Direction {
        RX = 0,  // Inbound (to FPGA)
        TX = 1,  // Outbound (from FPGA)
    }

**Parsed Packet:**

.. code-block:: rust

    pub struct TlpPacket {
        pub payload_length: u16,
        pub tlp_type: TlpType,
        pub direction: Direction,
        pub truncated: bool,
        pub timestamp: u64,
        pub req_id: u16,
        pub tag: u8,
        pub first_be: u8,
        pub last_be: u8,
        pub address: u64,
        pub we: bool,
        pub bar_hit: u8,
        pub attr: u8,
        pub at: u8,
        pub pasid_valid: bool,
        pub pasid: u32,
        pub privileged: bool,
        pub execute: bool,
        pub status: u8,
        pub cmp_id: u16,
        pub byte_count: u16,
        pub payload: Vec<u32>,
    }

**Parser Functions:**

.. code-block:: rust

    /// Find and parse TLP packet in data buffer
    pub fn find_packet(data: &[u8]) -> Option<(TlpPacket, usize)>;

    impl TlpPacket {
        /// Convert timestamp to microseconds (assumes 125MHz)
        pub fn timestamp_us(&self) -> f64;
    }


Command-Line Tools
------------------

**eb** - Etherbone CLI:

.. code-block:: bash

    # Read register
    eb read 0x00001000

    # Write register
    eb write 0x00001000 0xDEADBEEF

    # Probe device
    eb probe

**tlp-mon** - TLP Monitor:

.. code-block:: bash

    # Capture and display TLPs
    tlp-mon

    # Filter by type
    tlp-mon --filter MRd,MWr

**litex-server** - LiteX Remote Bridge:

.. code-block:: bash

    # Start server for LiteX tools
    litex-server --usb


Dependencies
------------

* **d3xx**: FTDI USB3 driver library
* **clap**: Command-line argument parsing
* **anyhow**: Error handling
