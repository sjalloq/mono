##########
Memory Map
##########

The Ibex SoC memory map is defined in ``hw/ip/soc/ibex_soc/rtl/ibex_soc_pkg.sv``.

*******
Regions
*******

================  ================  ======  ====================================
Region            Base Address      Size    Description
================  ================  ======  ====================================
ITCM              ``0x0001_0000``   16KB    Instruction memory (code + rodata)
DTCM              ``0x0002_0000``   16KB    Data memory (data + bss + stack)
Timer             ``0x1000_0000``   4KB     RISC-V mtime/mtimecmp
SimCtrl           ``0x1000_1000``   4KB     Simulation control peripheral
================  ================  ======  ====================================

************
Boot Address
************

The CPU boots from the start of ITCM (``0x0001_0000``). The vector table must
be placed at this address, with the reset handler at offset ``0x80``.

::

    0x0001_0000  Vector table base (exception handlers)
    0x0001_0080  Reset vector (execution starts here)

********************
Peripheral Registers
********************

Timer
=====

The timer implements the RISC-V standard machine timer registers.

========  ==============  ====  ==========================================
Offset    Name            R/W   Description
========  ==============  ====  ==========================================
0x00      ``mtime``       R/W   Timer counter (low 32 bits)
0x04      ``mtimeh``      R/W   Timer counter (high 32 bits)
0x08      ``mtimecmp``    R/W   Timer compare (low 32 bits)
0x0C      ``mtimecmph``   R/W   Timer compare (high 32 bits)
========  ==============  ====  ==========================================

A timer interrupt is generated when ``mtime >= mtimecmp``.

SimCtrl
=======

Simulation control peripheral for Verilator testbenches. In synthesis, this
peripheral responds to bus transactions but has no effect.

========  ==============  ====  ==========================================
Offset    Name            R/W   Description
========  ==============  ====  ==========================================
0x00      ``SIM_OUT``     W     Write ASCII character [7:0] to log file
0x08      ``SIM_CTRL``    W     Write 1 to bit 0 to halt simulation
========  ==============  ====  ==========================================

The register spacing (0x08) matches Ibex's ``simulator_ctrl`` for software
compatibility.
