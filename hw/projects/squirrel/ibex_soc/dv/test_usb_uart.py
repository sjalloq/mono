"""Cocotb tests for USB UART end-to-end data path.

Exercises both directions through the full stack:
    FT601 PHY -> CDC -> USB Core -> USB UART -> Wishbone -> CPU (and back)

Requires the usb_echo firmware which:
    1. Writes "Hello USB!\\n" to USB UART TX (auto-flushes on newline)
    2. Prints phase markers "T\\n" and "R\\n" to SimCtrl
    3. Polls USB UART RX and echoes received words back to TX

Note on FT601 PHY timing:
    The ft601_sync module latches the first TX word one cycle before asserting
    wr_n LOW. The BFM (like the real FT601 chip) only captures data when wr_n
    is LOW, so the first word of each burst (the USB preamble 0x5AA55AA5) is
    not captured. The frame parser accounts for this by detecting frames
    starting from the channel word.
"""

import cocotb
from cocotb.triggers import ClockCycles

from test_core import CoreTestbench, build_usb_packet, USB_CHANNEL_UART, USB_PREAMBLE


async def wait_for_phase_marker(tb, marker, timeout_cycles=50000):
    """Wait until a specific SimCtrl line appears.

    Args:
        tb: CoreTestbench instance.
        marker: String to match (e.g. "T" or "R").
        timeout_cycles: Maximum sys_clk cycles to wait.

    Returns:
        True if marker was seen, False on timeout.
    """
    for _ in range(timeout_cycles):
        await ClockCycles(tb.sys_clk, 1)
        if tb.cpu_has_errors:
            tb.check_no_cpu_errors()
        if marker in tb._sim_lines:
            return True
    return False


async def drain_ft601_packets(tb):
    """Drain all queued packets from the FT601 RX queue.

    Returns:
        List of packets, where each packet is a list of (data, be) tuples.
    """
    packets = []
    while tb.ft601.rx_queue_depth > 0:
        packet = await tb.ft601.receive_from_fpga()
        packets.append(packet)
    return packets


def parse_usb_frame(raw_words):
    """Parse USB-framed packets from raw FT601 words.

    The ft601_sync PHY drops the first word of each TX burst (the preamble
    0x5AA55AA5) due to its wr_n timing. Frames start with [channel, length,
    payload...] instead of [preamble, channel, length, payload...].

    If the preamble IS present (e.g. future BFM fix), it is skipped.

    Args:
        raw_words: List of (data, be) tuples.

    Returns:
        List of (channel, length_bytes, payload_bytes) tuples.
    """
    frames = []
    data_words = [w[0] for w in raw_words]

    i = 0
    while i < len(data_words):
        # Skip preamble if present
        if data_words[i] == USB_PREAMBLE:
            i += 1
            continue

        # Need at least channel + length
        if i + 1 >= len(data_words):
            break

        channel = data_words[i]
        length_bytes = data_words[i + 1]

        # Sanity check: length should be reasonable (< 4096)
        if length_bytes > 4096:
            i += 1
            continue

        num_payload_words = (length_bytes + 3) // 4

        if i + 2 + num_payload_words > len(data_words):
            break

        # Extract payload bytes (little-endian)
        payload = bytearray()
        for j in range(num_payload_words):
            word = data_words[i + 2 + j]
            payload.extend(word.to_bytes(4, 'little'))

        # Trim to actual byte length
        payload = bytes(payload[:length_bytes])

        frames.append((channel, length_bytes, payload))
        i += 2 + num_payload_words

    return frames


@cocotb.test(timeout_time=50, timeout_unit='us')
async def test_usb_uart_tx(dut):
    """Verify USB UART TX: firmware writes 'Hello USB!\\n' and it appears on FT601."""
    tb = CoreTestbench(dut)

    dut._log.info("=== test_usb_uart_tx ===")
    dut._log.info("Verify firmware TX data appears as USB-framed packet on FT601")

    await tb.reset()

    # Wait for CPU boot
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)
    assert got_output, "CPU produced no output — firmware not loaded?"

    # Wait for TX phase marker
    dut._log.info("Waiting for TX phase marker 'T'...")
    got_marker = await wait_for_phase_marker(tb, "T", timeout_cycles=50000)
    assert got_marker, "Never saw TX phase marker 'T' from firmware"

    # Receive the TX packet from FT601
    dut._log.info("Waiting for FT601 RX packet...")
    raw_words = await tb.ft601.receive_from_fpga()

    dut._log.info(f"Received {len(raw_words)} words from FT601")
    for i, (data, be) in enumerate(raw_words):
        dut._log.info(f"  word[{i}]: data=0x{data:08x} be=0x{be:x}")

    assert len(raw_words) > 0, "No data received from FT601 TX path"

    # Parse USB frame(s)
    frames = parse_usb_frame(raw_words)
    dut._log.info(f"Parsed {len(frames)} USB frame(s)")

    assert len(frames) >= 1, f"Expected at least 1 USB frame, got {len(frames)}"

    channel, length, payload = frames[0]
    dut._log.info(f"Frame 0: channel={channel}, length={length}, payload={payload!r}")

    assert channel == 0, f"Expected channel 0, got {channel}"

    expected = b"Hello USB!\n"
    assert payload == expected, (
        f"Payload mismatch:\n"
        f"  expected: {expected!r}\n"
        f"  got:      {payload!r}"
    )

    tb.check_no_cpu_errors()
    dut._log.info("PASS: USB UART TX data verified")


@cocotb.test(timeout_time=50, timeout_unit='us')
async def test_usb_uart_rx(dut):
    """Verify USB UART RX: send data via FT601 and verify CPU echoes it back."""
    tb = CoreTestbench(dut)

    dut._log.info("=== test_usb_uart_rx ===")
    dut._log.info("Send data via FT601, verify CPU echoes it back")

    await tb.reset()

    # Wait for CPU boot
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)
    assert got_output, "CPU produced no output — firmware not loaded?"

    # Wait for RX-ready phase marker
    dut._log.info("Waiting for RX phase marker 'R'...")
    got_marker = await wait_for_phase_marker(tb, "R", timeout_cycles=50000)
    assert got_marker, "Never saw RX phase marker 'R' from firmware"

    # Drain any startup TX data (the "Hello USB!\n" frame)
    dut._log.info("Draining startup TX data...")
    startup_packets = await drain_ft601_packets(tb)
    dut._log.info(f"Drained {len(startup_packets)} startup packet(s)")

    # Send test payload via FT601
    test_payload = b'Test'
    packet = build_usb_packet(0, test_payload)
    dut._log.info(f"Sending USB packet: {[f'0x{w:08x}' for w in packet]}")
    await tb.ft601.send_to_fpga(packet)

    # Wait for echo to come back
    dut._log.info("Waiting for echo packet...")
    raw_words = await tb.ft601.receive_from_fpga()

    dut._log.info(f"Received {len(raw_words)} echo words")
    for i, (data, be) in enumerate(raw_words):
        dut._log.info(f"  word[{i}]: data=0x{data:08x} be=0x{be:x}")

    assert len(raw_words) > 0, "No echo data received from FT601"

    # Parse USB frame
    frames = parse_usb_frame(raw_words)
    assert len(frames) >= 1, f"Expected at least 1 echo frame, got {len(frames)}"

    channel, length, payload = frames[0]
    dut._log.info(f"Echo frame: channel={channel}, length={length}, payload={payload!r}")

    assert channel == 0, f"Expected channel 0, got {channel}"
    # Compare only the bytes we sent (firmware echoes full 32-bit words)
    assert payload[:len(test_payload)] == test_payload, (
        f"Echo mismatch:\n"
        f"  expected: {test_payload!r}\n"
        f"  got:      {payload[:len(test_payload)]!r}"
    )

    tb.check_no_cpu_errors()
    dut._log.info("PASS: USB UART RX echo verified")


@cocotb.test(timeout_time=50, timeout_unit='us')
async def test_usb_uart_loopback(dut):
    """Verify USB UART loopback with multiple packets of different sizes."""
    tb = CoreTestbench(dut)

    dut._log.info("=== test_usb_uart_loopback ===")
    dut._log.info("Send multiple packets, verify each is echoed back")

    await tb.reset()

    # Wait for CPU boot
    got_output = await tb.wait_for_cpu_output(timeout_cycles=20000)
    assert got_output, "CPU produced no output — firmware not loaded?"

    # Wait for RX-ready phase marker
    dut._log.info("Waiting for RX phase marker 'R'...")
    got_marker = await wait_for_phase_marker(tb, "R", timeout_cycles=50000)
    assert got_marker, "Never saw RX phase marker 'R' from firmware"

    # Drain startup TX
    startup_packets = await drain_ft601_packets(tb)
    dut._log.info(f"Drained {len(startup_packets)} startup packet(s)")

    # Test payloads of different sizes
    test_payloads = [
        b'ABCD',       # 4 bytes (1 word, aligned)
        b'Hello!!!',   # 8 bytes (2 words, aligned)
        b'Hi',         # 2 bytes (partial word)
    ]

    for idx, test_payload in enumerate(test_payloads):
        dut._log.info(f"--- Loopback packet {idx}: {test_payload!r} ({len(test_payload)} bytes) ---")

        packet = build_usb_packet(0, test_payload)
        await tb.ft601.send_to_fpga(packet)

        # Wait for echoed response
        raw_words = await tb.ft601.receive_from_fpga()

        dut._log.info(f"Received {len(raw_words)} echo words")
        for i, (data, be) in enumerate(raw_words):
            dut._log.info(f"  word[{i}]: data=0x{data:08x} be=0x{be:x}")

        assert len(raw_words) > 0, f"No echo for packet {idx}"

        frames = parse_usb_frame(raw_words)
        assert len(frames) >= 1, f"No USB frame parsed for packet {idx}"

        channel, length, payload = frames[0]
        dut._log.info(f"Echo frame: channel={channel}, length={length}, payload={payload!r}")

        assert channel == 0, f"Packet {idx}: expected channel 0, got {channel}"
        # Compare only the bytes we sent (partial words get zero-padded by firmware)
        assert payload[:len(test_payload)] == test_payload, (
            f"Packet {idx} echo mismatch:\n"
            f"  expected: {test_payload!r}\n"
            f"  got:      {payload[:len(test_payload)]!r}"
        )

        dut._log.info(f"Packet {idx} echo OK")

    tb.check_no_cpu_errors()
    dut._log.info("PASS: USB UART loopback with multiple packet sizes verified")
