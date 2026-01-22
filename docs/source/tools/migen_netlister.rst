Migen Netlister
===============

A FuseSoC generator that converts Migen/LiteX modules to Verilog netlists with
clean, stable port names suitable for integration with hand-written SystemVerilog.

Overview
--------

The Migen netlister solves the problem of Migen renaming top-level ports during
Verilog conversion. By wrapping Migen modules in a ``MigenWrapper`` class, we can:

1. Create explicit top-level signals with controlled names
2. Connect them to the underlying Migen module's signals
3. Generate Verilog with predictable port names

This enables a hybrid workflow where complex logic (FSMs, stream handling) stays
in Migen while structural integration happens in SystemVerilog.

Architecture
------------

The generator flow has three components:

.. code-block:: text

   ┌─────────────────────────────────────────────────────────────────┐
   │ FuseSoC Core File (.core)                                       │
   │   generate:                                                     │
   │     netlist:                                                    │
   │       generator: migen_netlister                                │
   │       parameters:                                               │
   │         module: mono.gateware.wrappers.usb_core                 │
   │         class: USBCoreWrapper                                   │
   │         args: {num_ports: 2, clk_freq: 100000000}               │
   └──────────────────────────┬──────────────────────────────────────┘
                              │
                              ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ Generator (hw/generators/migen_netlister.py)                    │
   │   - Imports the wrapper class                                   │
   │   - Instantiates with args                                      │
   │   - Calls wrapper.netlist() or migen.fhdl.verilog.convert()     │
   │   - Registers output .v file with FuseSoC                       │
   └──────────────────────────┬──────────────────────────────────────┘
                              │
                              ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ Wrapper Class (mono/gateware/wrappers/*.py)                     │
   │   - Inherits from MigenWrapper                                  │
   │   - Instantiates Migen submodules                               │
   │   - Uses wrap_endpoint() to expose clean port names             │
   └─────────────────────────────────────────────────────────────────┘

File Locations
--------------

==========================================  ==========================================
File                                        Purpose
==========================================  ==========================================
``hw/generators/migen_netlister.py``        FuseSoC generator script
``hw/generators/generators.core``           Registers the generator with FuseSoC
``mono/migen/netlister.py``                 ``MigenWrapper`` base class
``mono/gateware/wrappers/``                 Wrapper implementations
==========================================  ==========================================

Generator Parameters
--------------------

The generator accepts these parameters in the core file's ``generate:`` section:

``module`` (required)
    Dotted Python module path containing the wrapper class.

    Example: ``mono.gateware.wrappers.usb_core``

``class`` (required)
    Name of the wrapper class to instantiate.

    Example: ``USBCoreWrapper``

``name`` (optional)
    Output Verilog module name. Defaults to lowercase class name.

    Example: ``usb_core``

``args`` (optional)
    Dictionary of keyword arguments passed to the wrapper's ``__init__``.

    Example:

    .. code-block:: yaml

       args:
         num_ports: 2
         clk_freq: 100000000

``ios`` (optional)
    List of signal names to use as IO if the wrapper doesn't provide an
    ``ios()`` method. Rarely needed when using ``MigenWrapper``.

Writing Wrappers
----------------

Basic Structure
^^^^^^^^^^^^^^^

Wrappers inherit from ``MigenWrapper`` and use ``wrap_endpoint()`` to expose
LiteX stream endpoints as clean Verilog ports:

.. code-block:: python

   from mono.migen import MigenWrapper
   from some_package import SomeMigenModule

   class MyWrapper(MigenWrapper):
       def __init__(self, param1=default1, param2=default2):
           super().__init__()

           # Instantiate the Migen module
           self.submodules.inner = SomeMigenModule(param1, param2)

           # Wrap stream endpoints
           self.wrap_endpoint(self.inner.sink, "sink", direction="sink")
           self.wrap_endpoint(self.inner.source, "source", direction="source")

The ``wrap_endpoint()`` Method
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. code-block:: python

   wrap_endpoint(endpoint, prefix, direction="auto")

Parameters:

``endpoint``
    A LiteX ``stream.Endpoint`` instance (has ``valid``, ``ready``, ``data``, etc.)

``prefix``
    String prefix for generated port names. An endpoint with fields ``valid``,
    ``ready``, ``data`` and prefix ``"sink"`` produces ports ``sink_valid``,
    ``sink_ready``, ``sink_data``.

``direction``
    Controls signal directions:

    - ``"sink"``: Data flows INTO the wrapper (valid/data are inputs, ready is output)
    - ``"source"``: Data flows OUT of the wrapper (valid/data are outputs, ready is input)
    - ``"auto"``: Infers from prefix (contains "sink" → sink, otherwise source)

Manual Signal Registration
^^^^^^^^^^^^^^^^^^^^^^^^^^

For non-endpoint signals, create signals manually and register them:

.. code-block:: python

   from migen import Signal

   class MyWrapper(MigenWrapper):
       def __init__(self):
           super().__init__()
           self.submodules.inner = SomeModule()

           # Create top-level signal
           self.status = Signal(8, name="status")

           # Connect to internal signal
           self.comb += self.status.eq(self.inner.some_status)

           # Register as IO
           self.register_io(self.status)

Example: USBCoreWrapper
-----------------------

This wrapper exposes the USB channel multiplexer (Packetizer + Depacketizer + Crossbar)
with a configurable number of channel ports:

.. code-block:: python

   class USBCoreWrapper(MigenWrapper):
       def __init__(self, num_ports=2, clk_freq=100_000_000, timeout=10):
           super().__init__()

           # Create core components
           self.submodules.depacketizer = USBDepacketizer(clk_freq, timeout)
           self.submodules.packetizer = USBPacketizer()
           self.submodules.crossbar = USBCrossbar()

           # Allocate channel ports
           self.user_ports = []
           for i in range(num_ports):
               port = self.crossbar.get_port(channel_id=i)
               self.user_ports.append(port)

           # Connect pipelines
           self.comb += self.depacketizer.source.connect(self.crossbar.master.sink)
           self.comb += self.crossbar.master.source.connect(self.packetizer.sink)

           # Wrap PHY interface
           self.wrap_endpoint(self.depacketizer.sink, "phy_rx", direction="sink")
           self.wrap_endpoint(self.packetizer.source, "phy_tx", direction="source")

           # Wrap channel interfaces
           for i, port in enumerate(self.user_ports):
               self.wrap_endpoint(port.source, f"ch{i}_rx", direction="source")
               self.wrap_endpoint(port.sink, f"ch{i}_tx", direction="sink")

Generated Verilog ports:

.. code-block:: verilog

   module usb_core(
       // PHY interface
       input  phy_rx_valid, output phy_rx_ready,
       input  [31:0] phy_rx_data, ...
       output phy_tx_valid, input  phy_tx_ready,
       output [31:0] phy_tx_data, ...

       // Channel 0
       output ch0_rx_valid, input  ch0_rx_ready,
       output [31:0] ch0_rx_data, [7:0] ch0_rx_dst, [31:0] ch0_rx_length, ...
       input  ch0_tx_valid, output ch0_tx_ready,
       input  [31:0] ch0_tx_data, [7:0] ch0_tx_dst, [31:0] ch0_tx_length, ...

       // Channel 1 (same pattern)
       ...

       input sys_clk, sys_rst
   );

Usage
-----

Running the Generator
^^^^^^^^^^^^^^^^^^^^^

.. code-block:: bash

   # List available cores
   fusesoc core list

   # Run generator (verilator triggers the build)
   fusesoc run --target=default --tool=verilator mono:ip:usb_core:0.1.0

The generated ``.v`` file appears in ``build/<core>/default-verilator/src/``.

Core File Example
^^^^^^^^^^^^^^^^^

.. code-block:: yaml

   CAPI=2:
   name: mono:ip:usb_core:0.1.0
   description: USB channel multiplexer

   filesets:
     rtl:
       depend:
         - mono:utils:generators

   generate:
     netlist:
       generator: migen_netlister
       parameters:
         module: mono.gateware.wrappers.usb_core
         class: USBCoreWrapper
         name: usb_core
         args:
           num_ports: 2
           clk_freq: 100000000

   targets:
     default:
       generate: [netlist]
       filesets: [rtl]
       toplevel: usb_core

Using from Another Core
^^^^^^^^^^^^^^^^^^^^^^^

The generator can be called with different parameters from any consuming core file.
Each invocation specifies its own ``args``:

.. code-block:: yaml

   # In your board's top.core
   generate:
     usb_2ch:
       generator: migen_netlister
       parameters:
         module: mono.gateware.wrappers.usb_core
         class: USBCoreWrapper
         name: usb_core
         args:
           num_ports: 2
           clk_freq: 100000000

Troubleshooting
---------------

Import Errors
^^^^^^^^^^^^^

If the generator fails with "No module named 'mono.gateware.wrappers'":

.. code-block:: bash

   # Reinstall the package to pick up new modules
   uv pip install .

The ``mono`` package must be installed in the venv for the generator to import wrappers.

Verilator Warnings
^^^^^^^^^^^^^^^^^^

Migen-generated Verilog often produces Verilator warnings about:

- Width mismatches (``WIDTHEXPAND``, ``WIDTHTRUNC``)
- Non-blocking assignments in combinational blocks (``COMBDLY``)

These are artifacts of Migen's code generation style and generally don't indicate
functional problems. They can be suppressed with Verilator lint pragmas if needed.
