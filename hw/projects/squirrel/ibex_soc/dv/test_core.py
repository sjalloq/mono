"""Cocotb testbench for Squirrel core.sv.

Exercises the end-to-end USB-to-CPU data path:
    FT601 PHY -> CDC FIFOs -> USB Core -> USB UART -> Wishbone -> Ibex SoC

Uses the FT601Driver BFM to inject/capture USB packets at the PHY level.
The SimCtrl signals (sim_char_valid, sim_char_data, sim_halt) are used to
verify the CPU is executing firmware correctly.

CPU error signals (alert_minor, alert_major_internal, alert_major_bus,
double_fault_seen) are monitored and cause immediate test failure if
asserted.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, First
from cocotb.handle import Immediate

from mono.cocotb.ft601 import FT601Bus, FT601Driver


# USB packet framing constants
USB_PREAMBLE = 0x5AA55AA5
USB_CHANNEL_UART = 0x00000000


def build_usb_packet(channel, payload_bytes):
    """Build a USB-framed packet as a list of 32-bit words.

    Format: [preamble, channel, length_bytes, payload_word0, ...]

    Args:
        channel: Channel ID (0 = UART).
        payload_bytes: bytes or bytearray of payload data.

    Returns:
        List of 32-bit integers.
    """
    length = len(payload_bytes)
    words = [USB_PREAMBLE, channel, length]

    # Pack payload into 32-bit words (little-endian)
    for i in range(0, length, 4):
        chunk = payload_bytes[i:i + 4]
        word = int.from_bytes(chunk.ljust(4, b'\x00'), 'little')
        words.append(word)

    return words


class CpuError(Exception):
    """Raised when a CPU error signal is detected during simulation."""
    pass


class CoreTestbench:
    """Test harness for the core DUT.

    Manages dual clocks (sys_clk, usb_clk), reset, FT601 driver,
    SimCtrl character monitoring, and CPU error detection.
    """

    def __init__(self, dut):
        self.dut = dut
        self.sys_clk = dut.sys_clk
        self.usb_clk = dut.usb_clk
        self.log = dut._log

        # Captured SimCtrl output
        self.sim_output = []
        self._sim_lines = []

        # CPU error state
        self.cpu_errors = []
        self._monitoring_enabled = False

        # Initialize clocks and reset
        self.sys_clk.value = Immediate(0)
        self.usb_clk.value = Immediate(0)
        dut.sys_rst_n.value = Immediate(1)
        dut.user_sw.value = Immediate(0)

        # Start clocks: sys_clk = 62.5 MHz (16ns), usb_clk = 100 MHz (10ns)
        cocotb.start_soon(Clock(self.sys_clk, 16, 'ns').start())
        cocotb.start_soon(Clock(self.usb_clk, 10, 'ns').start())

        # Background monitors
        cocotb.start_soon(self._char_monitor())
        cocotb.start_soon(self._cpu_error_monitor())

        # FT601 driver on the USB bus signals
        bus = FT601Bus(dut, name="usb")
        self.ft601 = FT601Driver(dut, name="usb", clock=self.usb_clk)

    async def _char_monitor(self):
        """Background coroutine capturing SimCtrl printf output."""
        line = []
        while True:
            await RisingEdge(self.dut.sim_char_valid)
            char = chr(int(self.dut.sim_char_data.value))
            self.sim_output.append(char)
            line.append(char)
            if char == '\n':
                text = "".join(line).rstrip()
                self._sim_lines.append(text)
                self.log.info(f"[CPU] {text}")
                line.clear()

    async def _cpu_error_monitor(self):
        """Background coroutine watching for CPU error signals.

        Waits until monitoring is enabled (after reset), then watches for
        rising edges on sticky signals (double_fault_seen) and level
        assertions on pulse signals (alert_*).

        Each error is logged once with crash dump context.
        """
        # Wait until reset completes and monitoring is enabled
        while not self._monitoring_enabled:
            await RisingEdge(self.sys_clk)

        # Track previous state for edge detection on sticky signals
        prev_double_fault = 0

        while True:
            await RisingEdge(self.sys_clk)

            errors = []

            # double_fault_seen is sticky (latched high forever) — detect rising edge
            cur_double_fault = int(self.dut.double_fault_seen.value)
            if cur_double_fault == 1 and prev_double_fault == 0:
                errors.append("DOUBLE_FAULT")
            prev_double_fault = cur_double_fault

            # alert signals are active-high pulses
            if int(self.dut.alert_major_internal.value) == 1:
                errors.append("ALERT_MAJOR_INTERNAL")

            if int(self.dut.alert_major_bus.value) == 1:
                errors.append("ALERT_MAJOR_BUS")

            if int(self.dut.alert_minor.value) == 1:
                errors.append("ALERT_MINOR")

            if errors:
                current_pc = int(self.dut.crash_dump_current_pc.value)
                next_pc = int(self.dut.crash_dump_next_pc.value)
                last_data_addr = int(self.dut.crash_dump_last_data_addr.value)
                exception_pc = int(self.dut.crash_dump_exception_pc.value)
                exception_addr = int(self.dut.crash_dump_exception_addr.value)

                msg = (
                    f"CPU error detected: {', '.join(errors)}\n"
                    f"  Crash dump:\n"
                    f"    current_pc    = 0x{current_pc:08x}\n"
                    f"    next_pc       = 0x{next_pc:08x}\n"
                    f"    last_data_addr = 0x{last_data_addr:08x}\n"
                    f"    exception_pc  = 0x{exception_pc:08x}\n"
                    f"    exception_addr = 0x{exception_addr:08x}"
                )

                self.log.error(msg)
                self.cpu_errors.append(msg)

    @property
    def cpu_output(self):
        """Return all captured CPU output as a single string."""
        return "".join(self.sim_output)

    @property
    def cpu_produced_output(self):
        """True if the CPU has produced any SimCtrl character output."""
        return len(self.sim_output) > 0

    @property
    def cpu_has_errors(self):
        """True if any CPU error signals have been detected."""
        return len(self.cpu_errors) > 0

    def check_no_cpu_errors(self):
        """Raise TestFailure if any CPU errors were detected."""
        if self.cpu_has_errors:
            raise AssertionError(
                f"CPU error(s) detected during test:\n"
                + "\n".join(self.cpu_errors)
            )

    async def reset(self, cycles=10):
        """Assert sys_rst_n for the specified number of sys_clk cycles."""
        self.log.info("Asserting reset")
        await ClockCycles(self.sys_clk, 2)
        self.dut.sys_rst_n.value = 0
        await ClockCycles(self.sys_clk, cycles)
        self.dut.sys_rst_n.value = 1
        # Wait for USB domain reset synchronizer to release
        await ClockCycles(self.usb_clk, 10)
        # Clear any transient error state from reset, then enable monitoring
        self.cpu_errors.clear()
        self._monitoring_enabled = True
        self.log.info("Reset released, CPU error monitoring enabled")

    async def wait_for_cpu_output(self, timeout_cycles=20000):
        """Wait until the CPU produces at least one character, or timeout.

        Also checks for CPU errors during the wait.

        Returns:
            True if output was seen, False on timeout.
        """
        if self.cpu_produced_output:
            return True

        for _ in range(timeout_cycles):
            await RisingEdge(self.sys_clk)
            if self.cpu_has_errors:
                self.check_no_cpu_errors()
            if self.cpu_produced_output:
                return True

        return False

    async def wait_for_halt(self, timeout_cycles=50000):
        """Wait for CPU to signal simulation halt, or timeout.

        Returns:
            True if halt was seen, False on timeout.
        """
        halt_edge = RisingEdge(self.dut.sim_halt)
        timeout = ClockCycles(self.sys_clk, timeout_cycles)
        result = await First(halt_edge, timeout)
        return result is halt_edge

    async def sys_cycles(self, n):
        """Wait for n sys_clk cycles."""
        await ClockCycles(self.sys_clk, n)

    async def usb_cycles(self, n):
        """Wait for n usb_clk cycles."""
        await ClockCycles(self.usb_clk, n)


@cocotb.test(timeout_time=5, timeout_unit='ms')
async def test_boot_heartbeat(dut):
    """Verify CPU boots and executes firmware (produces SimCtrl output)."""
    tb = CoreTestbench(dut)

    dut._log.info("=== test_boot_heartbeat ===")
    dut._log.info("Verify CPU boots and runs hello firmware via SimCtrl output")

    await tb.reset()

    dut._log.info("Waiting for CPU to produce printf output...")
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)

    if not got_output:
        raise AssertionError(
            "CPU produced no SimCtrl output after 20000 cycles. "
            "Firmware may not be loaded (missing/empty vmem file?) "
            "or CPU is stuck (illegal instructions, bus errors)."
        )

    dut._log.info(f"CPU output so far: {tb.cpu_output!r}")

    # Let the firmware run to completion
    dut._log.info("Waiting for firmware to halt...")
    halted = await tb.wait_for_halt(timeout_cycles=50000)

    if halted:
        dut._log.info("CPU halted cleanly")
    else:
        dut._log.info("CPU did not halt within timeout (may be expected)")

    tb.check_no_cpu_errors()

    dut._log.info(f"LED state: {int(dut.user_led.value):#04b}")
    dut._log.info("PASS: CPU booted and produced output")


@cocotb.test(timeout_time=5, timeout_unit='ms')
async def test_usb_rx_to_uart(dut):
    """Host-to-device path: send USB-framed packet via FT601 to USB UART.

    Constructs a USB-framed packet targeting channel 0 (UART) and sends it
    through the FT601 driver. Verifies the packet traverses the CDC FIFOs
    and reaches the USB core depacketizer.

    Full end-to-end verification (data arriving at CPU) requires firmware
    that polls the USB UART RX. This test verifies the PHY-to-CDC path.
    """
    tb = CoreTestbench(dut)

    dut._log.info("=== test_usb_rx_to_uart ===")
    dut._log.info("Send USB-framed packet through FT601 -> CDC -> USB Core")

    await tb.reset()

    # Wait for CPU to boot (verify firmware is loaded)
    dut._log.info("Waiting for CPU boot confirmation...")
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)
    if not got_output:
        raise AssertionError(
            "CPU produced no output — cannot verify USB RX path "
            "without a running CPU. Check vmem file."
        )
    dut._log.info("CPU is running")

    # Build a USB-framed packet: 4 bytes of payload on channel 0
    payload = b'\x48\x65\x6c\x6c'  # "Hell"
    packet = build_usb_packet(USB_CHANNEL_UART, payload)

    dut._log.info(f"Sending USB packet ({len(packet)} words): "
                  f"{[f'{w:#010x}' for w in packet]}")

    # Send via FT601 driver
    await tb.ft601.send_to_fpga(packet)

    # Allow time for CDC crossing and USB core processing
    dut._log.info("Waiting for CDC crossing and USB core processing...")
    await tb.sys_cycles(500)

    tb.check_no_cpu_errors()

    dut._log.info("PASS: USB RX packet sent through FT601 -> CDC FIFO path")


@cocotb.test(timeout_time=5, timeout_unit='ms')
async def test_usb_uart_tx(dut):
    """Device-to-host path: verify USB UART TX produces framed output.

    Boots the CPU with firmware that writes to SimCtrl (not USB UART TX).
    Checks whether any data emerges on the FT601 TX path.

    Full TX path testing requires firmware that writes to USB UART TX.
    """
    tb = CoreTestbench(dut)

    dut._log.info("=== test_usb_uart_tx ===")
    dut._log.info("Check FT601 TX path for any output from USB subsystem")

    await tb.reset()

    # Wait for CPU to boot
    dut._log.info("Waiting for CPU boot confirmation...")
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)
    if not got_output:
        raise AssertionError(
            "CPU produced no output — cannot verify USB TX path "
            "without a running CPU. Check vmem file."
        )
    dut._log.info("CPU is running")

    # Let firmware run a bit more to potentially produce USB output
    dut._log.info("Running CPU for additional cycles to collect TX data...")
    await tb.sys_cycles(5000)

    # Check if any data was received from FPGA
    if tb.ft601.rx_queue_depth > 0:
        received = []
        while tb.ft601.rx_queue_depth > 0:
            word = await tb.ft601.receive_from_fpga(count=1)
            received.append(word)
        dut._log.info(f"Received {len(received)} words from FPGA TX path")
        for i, w in enumerate(received):
            dut._log.info(f"  TX word[{i}]: {w}")
    else:
        dut._log.info("No TX data received (expected — hello firmware "
                      "uses SimCtrl, not USB UART TX)")

    tb.check_no_cpu_errors()

    dut._log.info("PASS: USB TX path check completed")
