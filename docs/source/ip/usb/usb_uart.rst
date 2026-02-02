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

    ┌───────────────────────────────────────────────────────────────────────────┐
    │                                usb_uart                                    │
    │                                                                            │
    │  Wishbone Slave                                  usb_channel_description   │
    │  ┌──────────────────────┐                                                  │
    │  │    usb_uart_csr      │    ┌─────────────────┐                           │
    │  │  (wb2simple +        │    │  prim_fifo_sync  │                           │
    │  │   reg_top + IRQ)     │───►│  (TX Data FIFO)  │                           │
    │  │                      │    └────────┬────────┘                           │
    │  │                      │             │                                    │
    │  │                      │    ┌────────▼────────┐                           │
    │  │                      │    │ usb_uart_tx_ctrl │──► sink                  │
    │  │                      │    │ (flush + send)   │   .valid/ready           │
    │  │                      │    └─────────────────┘   .data, .dst, .length   │
    │  │                      │                          .last                   │
    │  │                      │    ┌─────────────────┐                           │
    │  │                      │◄───│  prim_fifo_sync  │◄── source                │
    │  │                      │    │  (RX Data FIFO)  │   .valid/ready           │
    │  │                      │    └─────────────────┘   .data, .length         │
    │  │                      │    ┌─────────────────┐   .last                   │
    │  │                      │◄───│  prim_fifo_sync  │                           │
    │  │                      │    │  (RX Len FIFO)   │                           │
    │  │                      │    └────────▲────────┘                           │
    │  │                      │             │                                    │
    │  │                      │    ┌────────┴────────┐                           │
    │  │                      │    │ usb_uart_rx_ctrl │                           │
    │  └──────────────────────┘    │ (packet tracker) │                           │
    │                              └─────────────────┘                           │
    └───────────────────────────────────────────────────────────────────────────┘


Register Map
------------

The register map is auto-generated from the SystemRDL source
(``hw/ip/usb/uart/rdl/usb_uart_csr.rdl``).

.. rdl:docnode:: usb_uart_csr


TX Path Operation
-----------------

The TX path handles CPU-to-host data (printf output).

Data Flow
~~~~~~~~~

1. CPU writes 32-bit words to ``tx_data``
2. Hardware scans for ``flush_char`` (default ``0x0A``) in all 4 byte positions
3. Flush triggers on:

   - Character match (if ``ctrl.char_flush_en``)
   - Idle timeout expires (if ``ctrl.timeout_flush_en``)
   - Threshold reached (if ``ctrl.thresh_flush_en``)
   - Software flush (``ctrl.tx_flush``)

4. On flush, stream FIFO contents to USB with:

   - ``dst`` = configured channel ID
   - ``length`` = byte count (currently words * 4, see note below)
   - ``last`` = asserted on final word

5. USB packetizer wraps data in packet header

Character Match Detection
~~~~~~~~~~~~~~~~~~~~~~~~~

Hardware examines each written word for ``flush_char`` in all 4 byte
positions simultaneously:

.. code-block:: text

    flush_char = 0x0A (newline)

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
    │                  usb_uart_rx_ctrl                       │
    │                                                         │
    │  - Writes incoming data words to Data FIFO              │
    │  - On accepted last beat, pushes rx_length_i to Len     │
    │    FIFO directly (no internal packet state)             │
    └─────────────────┬─────────────────────┬─────────────────┘
                      │                     │
                      ▼                     ▼
              ┌──────────────┐      ┌──────────────┐
              │  Data FIFO   │      │  Len FIFO    │
              │  (RX_DEPTH)  │      │  (LEN_DEPTH) │
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
2. ``usb_uart_rx_ctrl`` writes each data word to Data FIFO as it arrives
3. On the accepted last beat, ``rx_length_i`` is pushed directly to Len FIFO
4. ``RX_LEN`` now shows packet byte count; ``status.rx_valid`` asserts
5. Interrupt fires if ``irq_enable.rx_valid`` set
6. CPU reads ``RX_LEN`` to learn packet size
7. CPU reads ``ceil(RX_LEN / 4)`` words from ``RX_DATA``
8. After final word read, hardware pops Len FIFO
9. ``RX_LEN`` updates to next packet's length (or 0 if none)

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

Four interrupt sources, managed via ``irq_status`` and ``irq_enable``:

- ``rx_valid`` — RX packet became available (rising edge of ``status.rx_valid``)
- ``tx_empty`` — TX FIFO became empty (rising edge of ``status.tx_empty``)
- ``rx_overflow`` — RX Data FIFO overflow (pulse from FIFO)
- ``len_overflow`` — RX Len FIFO overflow (pulse from FIFO)

Each event sets a sticky bit in ``irq_status``. Software clears bits by
writing 1 (W1C). The interrupt output is:

.. code-block:: text

    irq_o = |(irq_status & irq_enable)

The interrupt output is active-high, directly usable as an external
interrupt to the CPU. Software should read ``irq_status`` to determine
which condition triggered the interrupt, then write 1 to clear the
serviced bits.


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

The registers are defined in ``hw/ip/usb/uart/rdl/usb_uart_csr.rdl``.

Key features:

- ``tx_data`` @ 0x00 - External write-only, triggers TX FIFO push
- ``rx_data`` @ 0x04 - External read-only, pops RX Data FIFO
- ``rx_len`` @ 0x08 - External read-only, peeks at Len FIFO head
- ``status`` @ 0x0C - Hardware-written read-only status flags
- ``ctrl`` @ 0x10 - Control enables with singlepulse flush triggers
- ``timeout`` @ 0x14 - Idle timeout for auto-flush
- ``thresh`` @ 0x18 - Threshold for level-based flush
- ``flush_char`` @ 0x1C - Configurable flush trigger character (default 0x0A)
- ``irq_status`` @ 0x20 - Sticky W1C interrupt event flags
- ``irq_enable`` @ 0x24 - Interrupt enable mask

Regenerate CSR with: ``make -C hw/ip/usb/uart/rdl``


RTL Structure
-------------

The ``usb_uart`` module instantiates:

1. **usb_uart_csr** — CSR wrapper (wb2simple + reg_top + IRQ generation)
2. **prim_fifo_sync** — TX data FIFO (32-bit x TX_DEPTH)
3. **usb_uart_tx_ctrl** — TX control (flush triggers, byte counting, state machine)
4. **prim_fifo_sync** — RX data FIFO (32-bit x RX_DEPTH)
5. **prim_fifo_sync** — RX length FIFO (32-bit x LEN_DEPTH)
6. **usb_uart_rx_ctrl** — RX control (packet tracking, CPU read controller)

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
``hw/ip/usb/uart/rdl/usb_uart_csr.rdl``     SystemRDL register definition
``hw/ip/usb/uart/rdl/Makefile``             PeakRDL generation
``hw/ip/usb/uart/rtl/usb_uart_csr_*.sv``    Generated CSR package and top
``hw/ip/usb/uart/rtl/usb_uart_csr.sv``      CSR + bus adapter + IRQ wrapper
``hw/ip/usb/uart/rtl/usb_uart_tx_ctrl.sv``  TX control logic (flush/send)
``hw/ip/usb/uart/rtl/usb_uart_rx_ctrl.sv``  RX control logic (packet tracking)
``hw/ip/usb/uart/rtl/usb_uart.sv``          Top-level composition module
``hw/ip/usb/uart/usb_uart.core``            FuseSoC core file
==========================================  ==========================================
