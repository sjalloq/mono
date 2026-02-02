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

Architecture flags: ``-march=rv32imc -mabi=ilp32``

*******************
Directory Structure
*******************

.. code-block:: text

   sw/device/
   ├── ibex_soc/              # SoC-specific toolchain (shared across boards)
   │   ├── link.ld            # Linker script
   │   ├── crt0.S             # Startup code
   │   ├── common.mk          # Shared Makefile
   │   └── lib/
   │       ├── ibex_soc_regs.h    # Register definitions (C and asm)
   │       ├── ibex_soc.h         # HAL header
   │       └── ibex_soc.c         # HAL implementation
   └── <board>/
       └── ibex_soc/
           └── <app>/         # Application code
               ├── main.c
               └── Makefile

The SoC toolchain lives under ``sw/device/ibex_soc/`` because it depends on the
memory map, which is SoC-specific but board-agnostic. Applications are organized
by board since they may have board-specific peripheral configurations.

*************
Linker Script
*************

The linker script (``link.ld``) defines the memory layout:

.. code-block:: text

   ITCM (0x0001_0000, 16KB)     DTCM (0x0002_0000, 16KB)
   ┌─────────────────────┐      ┌─────────────────────┐
   │ .vectors            │      │ .data               │
   │ .text               │      │ .bss                │
   │ .rodata             │      │                     │
   │                     │      │         ↑           │
   │ .data (load addr)   │      │       stack         │
   └─────────────────────┘      └─────────────────────┘

Key symbols exported:

* ``_vectors_start`` - Start of vector table
* ``_entry_point`` - Reset vector (vectors_start + 0x80)
* ``_stack_start`` - Top of stack (end of DTCM)
* ``_bss_start``, ``_bss_end`` - BSS section bounds
* ``_data_start``, ``_data_end``, ``_data_load`` - For .data initialization

************
Startup Code
************

The startup code (``crt0.S``) performs:

1. **Register initialization** - Zero all 32 registers
2. **Stack setup** - Load ``_stack_start`` into ``sp``
3. **Data copy** - Copy ``.data`` section from ITCM to DTCM
4. **BSS clear** - Zero the ``.bss`` section
5. **Call main** - Jump to ``main()`` with argc=0, argv=NULL
6. **Halt** - Write to SimCtrl to stop simulation

Vector Table
============

The vector table is placed at the start of ITCM:

=========  ====================  ================================
Offset     Vector                Handler
=========  ====================  ================================
0x00-0x1B  Exception vectors     ``exception_handler()``
0x1C       Timer interrupt       ``timer_interrupt_handler()``
0x20-0x7F  More exceptions       ``exception_handler()``
0x80       Reset vector          ``reset_handler``
=========  ====================  ================================

***
HAL
***

The HAL provides minimal functions for simulation and bringup:

.. code-block:: c

   #include "ibex_soc.h"

   // Character/string output (to simulation log)
   int putchar(int c);
   int puts(const char *str);
   void puthex(uint32_t val);

   // Simulation control
   void sim_halt(void);

   // Timer
   uint64_t timer_read(void);
   void timer_set_cmp(uint64_t cmp);

   // Default handlers (weak, can be overridden)
   void exception_handler(void);
   void timer_interrupt_handler(void);

Register Access
===============

Direct register access macros are provided:

.. code-block:: c

   #include "ibex_soc_regs.h"

   REG_WRITE(TIMER_BASE + TIMER_MTIME, 0);
   uint32_t val = REG_READ(TIMER_BASE + TIMER_MTIME);

*********************
Building Applications
*********************

Create a new application:

.. code-block:: bash

   mkdir -p sw/device/squirrel/ibex_soc/myapp
   cd sw/device/squirrel/ibex_soc/myapp

Create ``Makefile``:

.. code-block:: make

   PROG := myapp
   SRCS := main.c

   include ../../../ibex_soc/common.mk

Create ``main.c``:

.. code-block:: c

   #include "ibex_soc.h"

   int main(void) {
       puts("Hello from myapp!");
       return 0;
   }

Build:

.. code-block:: bash

   make

Outputs:

* ``myapp.elf`` - ELF executable (for debugging)
* ``myapp.bin`` - Raw binary
* ``myapp.vmem`` - Verilog hex file (for simulation)
* ``myapp.dis`` - Disassembly
* ``myapp.map`` - Linker map

*******
Example
*******

A hello world example is provided at ``sw/device/squirrel/ibex_soc/hello/``:

.. code-block:: bash

   make -C sw/device/squirrel/ibex_soc/hello

This prints memory map information and timer values to the simulation log.
