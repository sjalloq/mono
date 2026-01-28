USB UART Channel
================

A bidirectional character stream over USB for CPU-to-host communication.
Provides printf output and REPL input using USB Channel 2.

.. note::

    This is a new implementation with packet-aware RX handling and correct
    ``usb_channel_description`` stream interface. See :doc:`usb_protocol`
    for the underlying packet format.

Overview
--------

The USB UART replaces traditional UART for CPU debug I/O:

- **TX path**: CPU writes to FIFO, hardware packetizes and sends to host
- **RX path**: Host sends commands, hardware depacketizes to CPU-readable FIFO
- **Newline detection**: Auto-flush on ``\n`` for interactive printf
- **32-bit word interface**: Efficient bulk transfers, no byte-at-a-time overhead
- **Packet boundaries**: RX preserves USB packet structure via ``RX_LEN`` register

.. code-block:: text

    ┌────────────────────────────────────────────────────────────────────────────┐
    │                                 usb_uart                                   │
    │                                                                            │
    │  Wishbone Slave                                   usb_channel_description  │
    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐                 │
    │  │ wb2simple   │───►│ CSR Block   │    │    TX FIFO      │──► sink         │
    │  │             │    │ (PeakRDL)   │───►│  + flush logic  │   .valid/ready  │
    │  └─────────────┘    │             │    │  + byte count   │   .data[31:0]   │
    │                     │             │    └─────────────────┘   .dst[7:0]     │
    │                     │             │                          .length[31:0] |
    │                     │             │                          .last         │
    │                     │             │    ┌─────────────────┐                 │
    │                     │             │◄───│   RX Data FIFO  │◄── source       │
    │                     │             │    │   (32 words)    │   .valid/ready  │
    │                     │             │    ├─────────────────┤   .data[31:0]   │
    │                     │             │◄───│   RX Len FIFO   │   .length[31:0] |
    │                     │             │    │   (4 entries)   │   .last         │
    │                     └─────────────┘    └─────────────────┘                 │
    │                                                                            │
    └────────────────────────────────────────────────────────────────────────────┘


Memory Map
----------

Base address: ``0x1000_2000`` (4KB region)

========  ==================  ====  ==========================================
Offset    Name                R/W   Description
========  ==================  ====  ==========================================
0x00      ``tx_data``         W     Write 32-bit word to TX FIFO
0x04      ``rx_data``         R     Read 32-bit word from RX Data FIFO
0x08      ``rx_len``          R     Byte count of current RX packet
0x0C      ``status``          R     FIFO status flags
0x10      ``ctrl``            R/W   Control enables and flush triggers
0x14      ``timeout``         R/W   Idle timeout (clock cycles)
0x18      ``thresh``          R/W   TX flush threshold (words)
========  ==================  ====  ==========================================


Register Definitions
--------------------

See ``usb_bridge_csr.rdl`` for complete definitions. Key registers below.

tx_data (0x00) - Write Only
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Write a 32-bit word to the TX FIFO. Hardware scans each byte for the
flush character (default newline ``0x0A``) to trigger automatic flush.

.. code-block:: text

    [31:24]  Byte 3 (MSB)
    [23:16]  Byte 2
    [15:8]   Byte 1
    [7:0]    Byte 0 (LSB, first in stream)


rx_data (0x04) - Read Only
~~~~~~~~~~~~~~~~~~~~~~~~~~

Read a 32-bit word from the RX Data FIFO.

.. code-block:: text

    [31:24]  Byte 3 (MSB)
    [23:16]  Byte 2
    [15:8]   Byte 1
    [7:0]    Byte 0 (LSB, first in stream)

Read when ``status.rx_empty`` is 0. Use ``rx_len`` to determine how many
bytes are valid in the current packet. Each read pops one word from the
Data FIFO. After reading ``ceil(rx_len / 4)`` words, the Len FIFO
automatically advances to the next packet.


rx_len (0x2C) - Read Only (NEW)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Byte count of the current RX packet (from Len FIFO head).

.. code-block:: text

    [31:0]   Byte count (0 = no complete packet available)

This register peeks at the head of the Len FIFO without popping it.
The value becomes non-zero only when a **complete** packet has been
received (i.e., after ``rx_last`` seen on the USB stream).

After the CPU reads all words for the current packet (``ceil(rx_len / 4)``
reads from ``rx_data``), the hardware automatically pops the Len FIFO
and ``rx_len`` updates to show the next queued packet's length, or 0
if no more packets are available.

**Important**: The CPU does not need to explicitly "acknowledge" the
packet. Simply reading the correct number of words advances to the next.


status (0x0C) - Read Only
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: text

    [0]      tx_empty    TX FIFO is empty
    [1]      tx_full     TX FIFO is full
    [2]      rx_valid    Complete packet available (Len FIFO not empty)
    [3]      rx_full     Data FIFO full (backpressure to USB)
    [7:4]    tx_level    TX FIFO fill level (words, 4-bit)
    [11:8]   rx_packets  Number of complete packets queued

Note: ``rx_valid`` reflects the Len FIFO state, not just the Data FIFO.
This means ``rx_valid=1`` guarantees at least one complete packet is
available for reading. Partial packets (still receiving) don't count.


ctrl (0x10) - Read/Write
~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: text

    [0]      tx_en              Enable TX path (default: 1)
    [1]      rx_en              Enable RX path (default: 1)
    [2]      nl_flush_en        Auto-flush TX on newline (default: 1)
    [3]      timeout_flush_en   Auto-flush TX on idle timeout (default: 1)
    [4]      thresh_flush_en    Auto-flush TX on threshold (default: 0)
    [5]      tx_flush           Software flush trigger (singlepulse)
    [6]      rx_flush           Software RX FIFO clear (singlepulse)
    [8]      irq_rx_en          IRQ when RX packet available
    [9]      irq_tx_empty_en    IRQ when TX FIFO empty


timeout (0x14) - Read/Write
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: text

    [31:0]   Idle timeout in clock cycles

When ``ctrl.timeout_flush_en`` is set, the TX FIFO flushes after this
many cycles of inactivity. Default: 100000 (~1ms at 100MHz).


thresh (0x18) - Read/Write
~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: text

    [7:0]    TX flush threshold (words)

When ``ctrl.thresh_flush_en`` is set and TX FIFO level reaches this
threshold, trigger a flush. Default: 8.


TX Path Operation
-----------------

The TX path handles CPU-to-host data (printf output).

Data Flow
~~~~~~~~~

1. CPU writes 32-bit words to ``tx_data``
2. Hardware scans for flush character (default newline ``0x0A``)
3. Flush triggers on:

   - Character match (if ``control.char_flush_en``)
   - Idle timeout expires (if ``control.timeout_flush_en``)
   - Threshold reached (if ``control.thresh_flush_en``)
   - Software flush (``control.tx_flush``)

4. On flush, stream FIFO contents to USB with:

   - ``dst`` = configured channel ID
   - ``length`` = byte count (currently words * 4, see note below)
   - ``last`` = asserted on final word

5. USB packetizer wraps data in packet header

.. note::

    **Current limitation**: The existing ``usb_bridge_tx_fifo.sv`` only
    checks byte 0 for character match and always sends ``words * 4`` bytes.
    For proper UART behavior, it should:

    1. Scan all 4 byte positions for flush character
    2. Calculate exact byte count up to and including the match
    3. Output ``length`` with the precise byte count

Character Match Detection (TODO)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Hardware should examine each written word for flush character in any byte:

.. code-block:: text

    Word written: 0x0D0A6F6C  ('l' 'o' '\n' '\r')
                       ^
                  Match at byte 1

    Packet length = (words_before * 4) + (1 + 1) = N + 2 bytes

The scan checks bytes 0, 1, 2, 3 in parallel. First match found (lowest
byte position) determines the flush point and byte count.


RX Path Operation
-----------------

The RX path handles host-to-CPU data (REPL input) using a **dual-FIFO**
architecture to preserve packet boundaries.

Dual-FIFO Architecture
~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: text

    From USB Crossbar (usb_channel_description)
         │
         │  .valid, .ready, .data[31:0], .length[31:0], .last
         ▼
    ┌─────────────────────────────────────────────────────────┐
    │                  Packet Receiver FSM                    │
    │                                                         │
    │  - Captures .length on first beat of each packet        │
    │  - Writes payload words to Data FIFO                    │
    │  - Pushes length to Len FIFO when .last seen            │
    └─────────────────┬─────────────────────┬─────────────────┘
                      │                     │
                      ▼                     ▼
              ┌──────────────┐      ┌──────────────┐
              │  Data FIFO   │      │  Len FIFO    │
              │  (32 words)  │      │  (4 entries) │
              │              │      │              │
              │  32-bit data │      │  32-bit len  │
              └──────┬───────┘      └──────┬───────┘
                     │                     │
                     ▼                     ▼
    ┌─────────────────────────────────────────────────────────┐
    │                   Read Controller                       │
    │                                                         │
    │  - RX_LEN reads head of Len FIFO (peek, no pop)         │
    │  - RX_DATA reads head of Data FIFO (pop on read)        │
    │  - Tracks words read; pops Len FIFO when packet done    │
    └─────────────────────────────────────────────────────────┘

**Why two FIFOs?** A single data FIFO cannot distinguish packet boundaries.
The Len FIFO queues packet lengths so multiple packets can be buffered,
and ``RX_LEN`` always shows the *current* packet's byte count.

Data Flow
~~~~~~~~~

1. USB packet arrives on channel 2 via ``usb_channel_description`` stream
2. Stream provides ``length`` (from packet header) on first beat
3. Receiver FSM captures ``length``, writes data words to Data FIFO
4. When ``last`` asserted, push captured length to Len FIFO
5. ``RX_LEN`` now shows packet byte count; ``STATUS.rx_empty`` clears
6. Interrupt fires if ``CTRL.rx_irq_en`` set
7. CPU reads ``RX_LEN`` to learn packet size
8. CPU reads ``ceil(RX_LEN / 4)`` words from ``RX_DATA``
9. After final word read, hardware pops Len FIFO
10. ``RX_LEN`` updates to next packet's length (or 0 if none)

Packet Boundaries
~~~~~~~~~~~~~~~~~

Each USB packet is a discrete message. The host software typically sends
one command line per packet (buffered until user presses Enter).

The hardware tracks how many words the CPU has read. After reading
``ceil(RX_LEN / 4)`` words, the Len FIFO automatically advances to the
next packet. This is transparent to software.

**Example: Host sends "hello\\n" (6 bytes)**

.. code-block:: text

    USB Stream:
      Beat 0: valid=1, data=0x6c6c6568, length=6, last=0  ('h','e','l','l')
      Beat 1: valid=1, data=0x00000a6f, length=6, last=1  ('o','\n', pad, pad)

    After reception:
      Data FIFO: [0x6c6c6568, 0x00000a6f]
      Len FIFO:  [6]
      RX_LEN = 6

    CPU reads:
      1. Read RX_LEN → 6 (need ceil(6/4) = 2 words)
      2. Read RX_DATA → 0x6c6c6568, words_remaining = 2→1
      3. Read RX_DATA → 0x00000a6f, words_remaining = 1→0, pop Len FIFO
      4. Read RX_LEN → 0 (no more packets)

Software should use ``RX_LEN`` to know when to stop extracting bytes:

.. code-block:: c

    uint32_t len = REG_READ(USB_UART_RX_LEN);
    uint32_t words = (len + 3) / 4;
    uint32_t bytes_read = 0;

    for (uint32_t i = 0; i < words; i++) {
        uint32_t word = REG_READ(USB_UART_RX_DATA);
        for (int b = 0; b < 4 && bytes_read < len; b++) {
            char c = (word >> (b * 8)) & 0xFF;
            process_char(c);
            bytes_read++;
        }
    }
    // RX_LEN now shows next packet (or 0)


Interrupt Behavior
------------------

Four interrupt sources, directly ORed to ``irq_o``:

When ``control.irq_rx_valid_en`` is set:

- IRQ when complete RX packet available (``rx_len != 0``)

When ``control.irq_tx_empty_en`` is set:

- IRQ when TX FIFO becomes empty

When ``control.irq_tx_low_en`` is set:

- IRQ when TX FIFO level drops below ``tx_watermark``

When ``control.irq_rx_high_en`` is set:

- IRQ when RX FIFO level exceeds ``rx_watermark``

The interrupt output is active-high, directly usable as an external
interrupt to the CPU. Software should check ``status`` to determine
which condition triggered the interrupt.


Software Interface
------------------

TX (printf replacement)
~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: c

    #include "usb_uart_csr_reg_pkg.h"

    #define USB_UART_BASE  0x10002000

    // Register offsets from usb_uart_csr.rdl
    #define TX_DATA_OFF    USB_UART_CSR_TX_DATA_OFFSET   // 0x00
    #define STATUS_OFF     USB_UART_CSR_STATUS_OFFSET    // 0x0C
    #define CTRL_OFF       USB_UART_CSR_CTRL_OFFSET      // 0x10

    #define STATUS_TX_FULL (1 << 1)

    static uint32_t tx_word = 0;
    static int tx_byte = 0;

    int putchar(int c) {
        tx_word |= ((uint8_t)c) << (tx_byte * 8);
        tx_byte++;

        if (tx_byte == 4 || c == '\n') {
            while (REG_READ(USB_UART_BASE + STATUS_OFF) & STATUS_TX_FULL)
                ;
            REG_WRITE(USB_UART_BASE + TX_DATA_OFF, tx_word);
            tx_word = 0;
            tx_byte = 0;
        }

        return c;
    }

    // For strings without newline, call explicitly
    void usb_uart_flush(void) {
        if (tx_byte > 0) {
            while (REG_READ(USB_UART_BASE + STATUS_OFF) & STATUS_TX_FULL)
                ;
            REG_WRITE(USB_UART_BASE + TX_DATA_OFF, tx_word);
            tx_word = 0;
            tx_byte = 0;
        }
        // Hardware timeout will flush to USB
    }


RX (REPL input)
~~~~~~~~~~~~~~~

.. code-block:: c

    #define RX_DATA_OFF    USB_UART_CSR_RX_DATA_OFFSET   // 0x04
    #define RX_LEN_OFF     USB_UART_CSR_RX_LEN_OFFSET    // 0x08

    int usb_uart_readline(char *buf, int max) {
        // Wait for complete packet (rx_len != 0)
        uint32_t len;
        while ((len = REG_READ(USB_UART_BASE + RX_LEN_OFF)) == 0)
            ;

        uint32_t words = (len + 3) / 4;
        int pos = 0;

        for (uint32_t i = 0; i < words && pos < max - 1; i++) {
            uint32_t word = REG_READ(USB_UART_BASE + RX_DATA_OFF);
            for (int b = 0; b < 4 && pos < len && pos < max - 1; b++) {
                buf[pos++] = (word >> (b * 8)) & 0xFF;
            }
        }
        // After reading all words, rx_len auto-advances to next packet
        buf[pos] = '\0';
        return pos;
    }


Simple REPL Loop
~~~~~~~~~~~~~~~~

.. code-block:: c

    void repl_main(void) {
        char line[128];

        // Enable TX/RX and newline flush (default ctrl value is good)
        // ctrl defaults: tx_en=1, rx_en=1, nl_flush_en=1

        puts("USB UART REPL ready\n");

        while (1) {
            int n = usb_uart_readline(line, sizeof(line));
            if (n > 0) {
                // Echo and process
                printf("> %s", line);
                execute_command(line);
            }
        }
    }


SystemRDL Definition
--------------------

The registers are defined in ``hw/ip/usb_uart/rdl/usb_uart_csr.rdl``.

Key features:

- ``tx_data`` @ 0x00 - External write-only, triggers TX FIFO push
- ``rx_data`` @ 0x04 - External read-only, pops RX Data FIFO
- ``rx_len`` @ 0x08 - External read-only, peeks at Len FIFO head
- ``status`` @ 0x0C - Hardware-written status flags
- ``ctrl`` @ 0x10 - Control enables with singlepulse flush triggers
- ``timeout`` @ 0x14 - Idle timeout for auto-flush
- ``thresh`` @ 0x18 - Threshold for level-based flush

Regenerate CSR with: ``make -C hw/ip/usb_uart/rdl``


RTL Structure
-------------

The ``usb_uart`` module instantiates:

1. **wb2simple** - Wishbone to simple bus adapter
2. **usb_uart_csr_reg_top** - PeakRDL-generated CSR block
3. **usb_uart_tx_fifo** - TX FIFO with multi-byte newline scan and flush logic
4. **usb_uart_rx_fifo** - Dual-FIFO RX with packet boundary tracking

.. code-block:: text

    Parameters:
        TX_DEPTH    = 64   (words, default)
        RX_DEPTH    = 64   (words, default)
        LEN_DEPTH   = 4    (packets, default)
        CHANNEL_ID  = 2    (USB channel)

USB Stream Interface (usb_channel_description)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The module connects to the USB crossbar via the standard
``usb_channel_description`` stream interface from ``core.py``:

.. code-block:: text

    TX (to host) - usb_uart sink:
        tx_valid_o          Stream valid
        tx_ready_i          Stream ready
        tx_data_o[31:0]     Payload data word
        tx_dst_o[7:0]       Channel ID (set to CHANNEL_ID parameter)
        tx_length_o[31:0]   Packet byte count (calculated from FIFO)
        tx_last_o           Last word of packet

    RX (from host) - usb_uart source:
        rx_valid_i          Stream valid
        rx_ready_o          Stream ready (backpressure when FIFO full)
        rx_data_i[31:0]     Payload data word
        rx_dst_i[7:0]       Channel ID (filtered by crossbar)
        rx_length_i[31:0]   Packet byte count (from USB header)
        rx_last_i           Last word of packet

    Other:
        irq_o               Interrupt output (directly usable by CPU)

This matches the ``USBUserPort`` interface from the USB crossbar, allowing
direct connection without adapters.


File Locations
--------------

==========================================  ==========================================
File                                        Description
==========================================  ==========================================
``hw/ip/usb_uart/rdl/usb_uart_csr.rdl``     SystemRDL register definition
``hw/ip/usb_uart/rdl/Makefile``             PeakRDL generation
``hw/ip/usb_uart/rtl/usb_uart_csr_*.sv``    Generated CSR package and top
``hw/ip/usb_uart/rtl/usb_uart_tx_fifo.sv``  TX FIFO with flush logic
``hw/ip/usb_uart/rtl/usb_uart_rx_fifo.sv``  RX dual-FIFO with packet tracking
``hw/ip/usb_uart/rtl/usb_uart.sv``          Top-level module
``hw/ip/usb_uart/usb_uart.core``            FuseSoC core file
==========================================  ==========================================
