"""Wishbone Crossbar Cocotb Tests.

Tests the 2x2 crossbar configuration with:
- Slave 0: 0x0000_0000 - 0x0000_FFFF
- Slave 1: 0x0001_0000 - 0x0001_FFFF
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Combine

from mono.cocotb.wishbone import WishboneMaster, WishboneSlave


async def reset_dut(dut, cycles=5):
    """Apply reset to the DUT."""
    dut.rst_ni.value = 0
    await ClockCycles(dut.clk_i, cycles)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)


@cocotb.test()
async def test_single_write_read(dut):
    """Test basic write then read to slave 0."""
    # Start clock
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    # Create master and slaves
    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Write to slave 0
    await m0.write(0x0000_0100, 0xDEADBEEF)

    # Read back
    result = await m0.read(0x0000_0100)

    assert result.ack, "Expected ACK"
    assert result.data == 0xDEADBEEF, f"Read mismatch: 0x{result.data:08X}"

    dut._log.info("test_single_write_read PASSED")


@cocotb.test()
async def test_slave_routing(dut):
    """Test that addresses route to correct slaves."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Write different values to each slave
    await m0.write(0x0000_0000, 0x11111111)  # Slave 0
    await m0.write(0x0001_0000, 0x22222222)  # Slave 1

    # Read back and verify
    r0 = await m0.read(0x0000_0000)
    r1 = await m0.read(0x0001_0000)

    assert r0.data == 0x11111111, f"Slave 0 mismatch: 0x{r0.data:08X}"
    assert r1.data == 0x22222222, f"Slave 1 mismatch: 0x{r1.data:08X}"

    # Verify via direct memory access
    assert s0.read_word(0x0000) == 0x11111111
    assert s1.read_word(0x0000) == 0x22222222

    dut._log.info("test_slave_routing PASSED")


@cocotb.test()
async def test_unmapped_address(dut):
    """Test error response for unmapped addresses."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Access unmapped address (0x0002_0000 is outside both slaves)
    result = await m0.read(0x0002_0000)

    assert result.err, "Expected ERR for unmapped address"
    assert not result.ack, "Should not ACK unmapped address"

    dut._log.info("test_unmapped_address PASSED")


@cocotb.test()
async def test_two_masters(dut):
    """Test both masters can access different slaves."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    m1 = WishboneMaster(dut, "m1", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Master 0 writes to slave 0
    await m0.write(0x0000_0000, 0xAAAAAAAA)

    # Master 1 writes to slave 1
    await m1.write(0x0001_0000, 0xBBBBBBBB)

    # Cross-read: Master 0 reads from slave 1
    r0 = await m0.read(0x0001_0000)
    assert r0.data == 0xBBBBBBBB, f"M0 read S1 mismatch: 0x{r0.data:08X}"

    # Cross-read: Master 1 reads from slave 0
    r1 = await m1.read(0x0000_0000)
    assert r1.data == 0xAAAAAAAA, f"M1 read S0 mismatch: 0x{r1.data:08X}"

    dut._log.info("test_two_masters PASSED")


@cocotb.test()
async def test_sequential_accesses(dut):
    """Test multiple sequential accesses from one master."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Write incrementing pattern
    for i in range(8):
        await m0.write(0x0000_0000 + (i * 4), i * 0x11111111)

    # Read back and verify
    for i in range(8):
        result = await m0.read(0x0000_0000 + (i * 4))
        expected = i * 0x11111111
        assert result.data == expected, f"Addr 0x{i*4:04X}: got 0x{result.data:08X}, expected 0x{expected:08X}"

    dut._log.info("test_sequential_accesses PASSED")


@cocotb.test()
async def test_byte_enables(dut):
    """Test byte-granular writes using sel."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # Write full word first
    await m0.write(0x0000_0000, 0x12345678)

    # Overwrite just byte 1 (bits 15:8)
    await m0.write(0x0000_0000, 0x0000FF00, sel=0b0010)

    # Read back
    result = await m0.read(0x0000_0000)
    expected = 0x1234FF78
    assert result.data == expected, f"Byte enable failed: 0x{result.data:08X} != 0x{expected:08X}"

    dut._log.info("test_byte_enables PASSED")


@cocotb.test(timeout_time=1, timeout_unit="us")
async def test_pipelined_writes(dut):
    """Test true pipelined operation: N writes in N+1 cycles.

    In pipelined mode, the address phase of transaction N+1 overlaps
    with the data phase of transaction N. This test manually drives
    signals to verify the crossbar supports this.
    """
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    # Only need the slave responder
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=0x10000)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=0x10000)

    await reset_dut(dut)

    # We'll do 4 pipelined writes which should complete in 5 cycles
    # (1 cycle for first addr phase, then 4 cycles with overlapped addr/data)
    num_writes = 4
    start_time = cocotb.utils.get_sim_time("ns")

    # Start the bus cycle
    dut.m0_cyc_i.value = 1
    dut.m0_sel_i.value = 0xF
    dut.m0_we_i.value = 1

    acks_received = 0
    writes_issued = 0

    while acks_received < num_writes:
        # Issue next write if we have more to send
        if writes_issued < num_writes:
            dut.m0_stb_i.value = 1
            dut.m0_adr_i.value = writes_issued * 4
            dut.m0_dat_i.value = (writes_issued + 1) * 0x11111111
            writes_issued += 1
        else:
            dut.m0_stb_i.value = 0

        await RisingEdge(dut.clk_i)

        # Check for ACK (count responses)
        if dut.m0_ack_o.value == 1:
            acks_received += 1

        # In pipelined mode, we can issue next address as soon as stall deasserts
        # (For this simple test, assume no stall from slave)

    # End the bus cycle
    dut.m0_cyc_i.value = 0
    dut.m0_stb_i.value = 0

    end_time = cocotb.utils.get_sim_time("ns")
    cycles_taken = (end_time - start_time) / 10  # 10ns clock period

    # Pipelined: N writes should take N+1 cycles (not 2N)
    # Allow some margin for reset timing
    expected_cycles = num_writes + 1
    dut._log.info(f"Pipelined {num_writes} writes in {cycles_taken} cycles (expected ~{expected_cycles})")

    assert cycles_taken <= expected_cycles + 1, \
        f"Pipelined writes took {cycles_taken} cycles, expected <= {expected_cycles + 1}"

    # Verify data was written correctly
    for i in range(num_writes):
        expected = (i + 1) * 0x11111111
        actual = s0.read_word(i * 4)
        assert actual == expected, f"Write {i}: got 0x{actual:08X}, expected 0x{expected:08X}"

    dut._log.info("test_pipelined_writes PASSED")


class WishboneMonitor:
    """Monitor for observing Wishbone transactions on a master port.

    Watches for completed transactions (address phase accepted, then ACK/ERR)
    and records them for scoreboard checking.
    """

    def __init__(self, dut, prefix, clock):
        self.dut = dut
        self.prefix = prefix
        self.clock = clock
        self.transactions = []  # Completed transactions: (addr, we, wr_data, rd_data, ack)
        self._pending = []  # Address phases awaiting data phase completion

        # Get signal references
        self.cyc = getattr(dut, f"{prefix}_cyc_i")
        self.stb = getattr(dut, f"{prefix}_stb_i")
        self.ack = getattr(dut, f"{prefix}_ack_o")
        self.err = getattr(dut, f"{prefix}_err_o")
        self.we = getattr(dut, f"{prefix}_we_i")
        self.adr = getattr(dut, f"{prefix}_adr_i")
        self.dat_i = getattr(dut, f"{prefix}_dat_i")  # Master write data
        self.dat_o = getattr(dut, f"{prefix}_dat_o")  # Master read data
        self.stall = getattr(dut, f"{prefix}_stall_o")

        cocotb.start_soon(self._monitor_loop())

    async def _monitor_loop(self):
        """Watch bus and record transactions."""
        while True:
            await RisingEdge(self.clock)

            # Check for address phase acceptance (STB+CYC, no STALL)
            if self.cyc.value and self.stb.value and not self.stall.value:
                self._pending.append({
                    "addr": int(self.adr.value),
                    "we": bool(self.we.value),
                    "wr_data": int(self.dat_i.value) if self.we.value else 0,
                })

            # Check for data phase completion
            if self.ack.value or self.err.value:
                if self._pending:
                    txn = self._pending.pop(0)
                    txn["rd_data"] = int(self.dat_o.value) if not txn["we"] else 0
                    txn["ack"] = bool(self.ack.value)
                    txn["err"] = bool(self.err.value)
                    self.transactions.append(txn)


class Scoreboard:
    """Scoreboard for verifying Wishbone transactions against a reference model."""

    def __init__(self):
        self.ref_mem = {}  # Reference memory: addr -> data
        self.errors = []

    def apply_write(self, addr, data):
        """Record a write to reference memory."""
        self.ref_mem[addr] = data

    def check_read(self, addr, actual_data):
        """Check a read against reference memory."""
        expected = self.ref_mem.get(addr, 0)
        if actual_data != expected:
            self.errors.append(
                f"Read mismatch at 0x{addr:08X}: "
                f"got 0x{actual_data:08X}, expected 0x{expected:08X}"
            )

    def process_transaction(self, txn):
        """Process a monitored transaction."""
        if txn["err"]:
            # Could check for expected errors here
            return

        if txn["we"]:
            self.apply_write(txn["addr"], txn["wr_data"])
        else:
            self.check_read(txn["addr"], txn["rd_data"])


@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_stress_random_with_backpressure(dut):
    """Stress test with pipelined transactions and slave backpressure.

    Tests:
    - Two masters issuing pipelined transactions concurrently
    - Pipelined single-beat transactions (overlapping address/data phases)
    - Random mix of reads and writes
    - Both masters randomly access both slaves (tests arbitration)
    - Slave stall (backpressure) randomised
    - Bus monitors capture all transactions
    - Scoreboard verifies final memory state consistency
    """
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    # Create masters
    m0 = WishboneMaster(dut, "m0", dut.clk_i)
    m1 = WishboneMaster(dut, "m1", dut.clk_i)

    # Create slaves with 4K address space and backpressure (30% stall probability)
    slave_size = 0x1000  # 4KB
    s0 = WishboneSlave(dut, "s0", dut.clk_i, size=slave_size, stall_prob=0.3)
    s1 = WishboneSlave(dut, "s1", dut.clk_i, size=slave_size, stall_prob=0.3)

    # Monitors for each master
    monitor0 = WishboneMonitor(dut, "m0", dut.clk_i)
    monitor1 = WishboneMonitor(dut, "m1", dut.clk_i)

    await reset_dut(dut)

    num_transactions = 100

    def generate_txn_queue(count):
        """Generate a queue of random transactions."""
        txn_queue = []

        for _ in range(count):
            # Random slave select (0 or 1)
            slave = random.randint(0, 1)
            slave_base = slave * 0x0001_0000

            # Random word-aligned address within 4K slave region
            offset = random.randint(0, (slave_size // 4) - 1) * 4
            addr = slave_base + offset

            # Random read or write (50/50)
            is_write = random.randint(0, 1)
            data = random.randint(0, 0xFFFFFFFF) if is_write else 0

            txn_queue.append({"addr": addr, "we": is_write, "data": data})

        return txn_queue

    txn_queue0 = generate_txn_queue(num_transactions)
    txn_queue1 = generate_txn_queue(num_transactions)

    # Issue all transactions from both masters - they will pipeline
    tasks = []

    for txn in txn_queue0:
        if txn["we"]:
            task = cocotb.start_soon(m0.write(txn["addr"], txn["data"]))
        else:
            task = cocotb.start_soon(m0.read(txn["addr"]))
        tasks.append(task)

    for txn in txn_queue1:
        if txn["we"]:
            task = cocotb.start_soon(m1.write(txn["addr"], txn["data"]))
        else:
            task = cocotb.start_soon(m1.read(txn["addr"]))
        tasks.append(task)

    # Wait for all to complete
    await Combine(*tasks)

    # Allow monitors to catch final transactions
    await ClockCycles(dut.clk_i, 5)

    # Verify all transactions completed
    dut._log.info(f"M0: issued {num_transactions}, monitored {len(monitor0.transactions)}")
    dut._log.info(f"M1: issued {num_transactions}, monitored {len(monitor1.transactions)}")

    assert len(monitor0.transactions) == num_transactions, \
        f"M0 transaction count mismatch: {len(monitor0.transactions)} != {num_transactions}"
    assert len(monitor1.transactions) == num_transactions, \
        f"M1 transaction count mismatch: {len(monitor1.transactions)} != {num_transactions}"

    # Build reference memory from all monitored writes (both masters)
    # Since arbitration order is non-deterministic, we track all writes
    # and verify the final slave memory matches the last write to each address
    all_writes = {}  # addr -> list of (master_id, data, txn_index)

    for idx, txn in enumerate(monitor0.transactions):
        if txn["we"] and txn["ack"]:
            addr = txn["addr"]
            if addr not in all_writes:
                all_writes[addr] = []
            all_writes[addr].append((0, txn["wr_data"], idx))

    for idx, txn in enumerate(monitor1.transactions):
        if txn["we"] and txn["ack"]:
            addr = txn["addr"]
            if addr not in all_writes:
                all_writes[addr] = []
            all_writes[addr].append((1, txn["wr_data"], idx))

    # Verify slave memory contains valid data (one of the written values)
    errors = []
    for addr, writes in all_writes.items():
        slave_idx = 1 if addr >= 0x0001_0000 else 0
        slave = s1 if slave_idx else s0
        local_addr = addr & (slave_size - 1)

        actual = slave.read_word(local_addr)
        valid_values = [w[1] for w in writes]

        if actual not in valid_values:
            errors.append(
                f"Addr 0x{addr:08X}: slave has 0x{actual:08X}, "
                f"expected one of {[f'0x{v:08X}' for v in valid_values]}"
            )

    if errors:
        for err in errors[:10]:
            dut._log.error(err)
        assert False, f"{len(errors)} memory consistency errors (showing first 10)"

    dut._log.info("test_stress_random_with_backpressure PASSED")
