##########
Memory Map
##########

The SERV SoC memory map is defined in ``hw/ip/soc/serv_soc/rtl/serv_soc_pkg.sv``.

*******
Regions
*******

================  ================  ======  ====================================
Region            Base Address      Size    Description
================  ================  ======  ====================================
TCM               ``0x0000_0000``   8KB     Unified code + data memory
Timer             ``0x1000_0000``   4KB     RISC-V mtime/mtimecmp
SimCtrl           ``0x1000_1000``   4KB     Simulation control peripheral
USB UART          ``0x1000_2000``   4KB     USB UART (external slave)
================  ================  ======  ====================================

The peripheral base address (``0x1000_0000``) matches the Ibex SoC, so the same
register offsets and HAL patterns apply. The crossbar's base+mask decode handles
all address routing.

************
Boot Address
************

The CPU boots from the start of TCM (``0x0000_0000``). SERV does not have a
vector table like Ibex; execution begins directly at ``RESET_PC``.

::

    0x0000_0000  _start (execution begins here)

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

USB UART
========

The USB UART register interface is shared with the Ibex SoC. See the
:doc:`USB UART documentation </ip/usb/usb_uart>` for the full register map.

========  ==================  ====  ==========================================
Offset    Name                R/W   Description
========  ==================  ====  ==========================================
0x00      ``TX_DATA``         W     Write 32-bit word to TX FIFO
0x04      ``RX_DATA``         R     Read 32-bit word from RX FIFO (pops)
0x08      ``RX_LEN``          R     Byte count of current RX packet (peek)
0x0C      ``STATUS``          R     TX/RX FIFO status flags
0x10      ``CTRL``            R/W   TX/RX enable, flush controls
========  ==================  ====  ==========================================
