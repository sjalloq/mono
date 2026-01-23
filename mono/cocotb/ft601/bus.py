"""FT601 bus signal definitions.

Signal interface based on the FT601 datasheet and project specification
in docs/source/usb/ft601_phy.rst.
"""

from cocotb_bus.bus import Bus


class FT601Bus(Bus):
    """Signal grouping for the FT601 FIFO interface.

    This defines the signals from the perspective of the FPGA (DUT):
        - Inputs: clk, rxf_n, txe_n (active low status from FT601)
        - Outputs: rd_n, wr_n, oe_n, siwu_n, rst_n, be (active low controls)
        - Bidirectional: data (directly directly by FT601 or FPGA depending on oe_n)

    The driver simulates the FT601 chip, so it drives rxf_n, txe_n, and data
    (when reading), while monitoring rd_n, wr_n, oe_n, and data (when writing).

    Args:
        entity: The DUT entity containing the signals.
        name: Optional signal name prefix (e.g., "usb" for "usb_data").
        signals: Override default signal names if needed.
        optional_signals: Additional optional signals.

    Attributes:
        _signals: Required signals for the FT601 interface.
        _optional_signals: Optional signals that may not be present.
    """

    _signals = [
        "clk",      # 100MHz clock from FT601
        "data",     # 32-bit bidirectional data bus
        "be",       # 4-bit byte enables
        "rxf_n",    # RX FIFO not empty (active low) - FT601 has data for FPGA
        "txe_n",    # TX FIFO not full (active low) - FT601 can accept data
        "rd_n",     # Read strobe (active low) - FPGA reading from FT601
        "wr_n",     # Write strobe (active low) - FPGA writing to FT601
        "oe_n",     # Output enable (active low) - FT601 drives data bus
    ]

    _optional_signals = [
        "siwu_n",   # Send immediate / wake up (active low)
        "rst_n",    # Reset (active low)
    ]

    def __init__(self, entity, name=None, signals=None, optional_signals=None):
        super().__init__(
            entity,
            name,
            signals if signals is not None else self._signals,
            optional_signals if optional_signals is not None else self._optional_signals,
        )
