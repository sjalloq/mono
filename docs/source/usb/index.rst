USB Etherbone Bridge
====================

A multi-channel USB3 to Wishbone bridge using the FT601 USB3 FIFO IC and Etherbone protocol.

This documentation provides a functional specification for the USB Etherbone Bridge system,
originally implemented in Migen/LiteX. The goal is to support translation to SystemVerilog
while maintaining the multi-channel architecture that allows host software to read/write
to any channel.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   overview
   ft601_phy
   usb_protocol
   etherbone
   monitor
   software
   sv_conversion

