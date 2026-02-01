###########
C Toolchain
###########

A minimal C runtime for hardware bringup and simulation validation. This
toolchain is intentionally simple - the long-term target is Rust with Embassy.

*********
Toolchain
*********

The lowRISC prebuilt GCC toolchain is recommended:

https://github.com/lowRISC/lowrisc-toolchains/releases

Download a release with "gcc" in the name (e.g., ``lowrisc-toolchain-rv32imcb-*``).

Architecture flags: ``-march=rv32i -mabi=ilp32``

.. note::

   SERV is a base RV32I core only. No compressed (C) or multiply/divide (M)
   extensions are available. The toolchain must not emit C or M instructions.

*******************
Directory Structure
*******************

.. code-block:: text

   sw/device/
   ├── serv_soc/              # SoC-specific toolchain (shared across boards)
   │   ├── link.ld            # Linker script
   │   ├── crt0.S             # Startup code
   │   ├── common.mk          # Shared Makefile
   │   └── lib/
   │       ├── serv_soc_regs.h    # Register definitions (C and asm)
   │       ├── serv_soc.h         # HAL header
   │       └── serv_soc.c         # HAL implementation
   └── <board>/
       └── serv_soc/
           └── <app>/         # Application code
               ├── main.c
               └── Makefile

The SoC toolchain lives under ``sw/device/serv_soc/`` because it depends on the
memory map, which is SoC-specific but board-agnostic. Applications are organized
by board since they may have board-specific peripheral configurations.

*************
Linker Script
*************

The linker script (``link.ld``) defines a single unified memory region:

.. code-block:: text

   TCM (0x0000_0000, 8KB)
   ┌─────────────────────┐
   │ .text               │
   │ .rodata             │
   │ .data               │
   │ .bss                │
   │                     │
   │         ↑           │
   │       stack         │
   └─────────────────────┘

Unlike the Ibex SoC which splits code and data across ITCM/DTCM, the SERV SoC
places everything in a single TCM. This simplifies the linker script and startup
code (no ``.data`` copy needed).

Key symbols exported:

* ``_stack_start`` - Top of stack (end of TCM)
* ``_bss_start``, ``_bss_end`` - BSS section bounds

************
Startup Code
************

The startup code (``crt0.S``) performs:

1. **Register initialization** - Zero all 32 registers
2. **Stack setup** - Load ``_stack_start`` into ``sp``
3. **BSS clear** - Zero the ``.bss`` section
4. **Call main** - Jump to ``main()`` with argc=0, argv=NULL
5. **Halt** - Write to SimCtrl to stop simulation

SERV does not use a vector table. The ``_start`` symbol is placed in
``.text.start`` which the linker script puts at the beginning of TCM, matching
``RESET_PC = 0x0``.

***
HAL
***

The HAL provides minimal functions for simulation and bringup:

.. code-block:: c

   #include "serv_soc.h"

   // Character/string output (to simulation log)
   int putchar(int c);
   int puts(const char *str);
   void puthex(uint32_t val);

   // Simulation control
   void sim_halt(void);

   // Timer
   uint64_t timer_read(void);
   void timer_set_cmp(uint64_t cmp);

   // USB UART
   void usb_uart_tx_word(uint32_t word);
   void usb_uart_tx_flush(void);
   uint32_t usb_uart_rx_len(void);
   uint32_t usb_uart_rx_word(void);
   uint32_t usb_uart_status(void);

   // Default handlers (weak, can be overridden)
   void exception_handler(void);
   void timer_interrupt_handler(void);

Register Access
===============

Direct register access macros are provided:

.. code-block:: c

   #include "serv_soc_regs.h"

   REG_WRITE(TIMER_BASE + TIMER_MTIME, 0);
   uint32_t val = REG_READ(TIMER_BASE + TIMER_MTIME);

*********************
Building Applications
*********************

Create a new application:

.. code-block:: bash

   mkdir -p sw/device/serv_soc/hello
   cd sw/device/serv_soc/hello

Create ``Makefile``:

.. code-block:: make

   PROG := hello
   SRCS := hello.c

   include ../common.mk

Create ``hello.c``:

.. code-block:: c

   #include "serv_soc.h"

   int main(void) {
       puts("Hello from SERV!");
       return 0;
   }

Build:

.. code-block:: bash

   make

Outputs:

* ``hello.elf`` - ELF executable (for debugging)
* ``hello.bin`` - Raw binary
* ``hello.vmem`` - Verilog hex file (for simulation)
* ``hello.dis`` - Disassembly
* ``hello.map`` - Linker map

*******
Example
*******

A hello world example is provided at ``sw/device/serv_soc/hello/``:

.. code-block:: bash

   make -C sw/device/serv_soc/hello

This prints a greeting and timer values to the simulation log.
