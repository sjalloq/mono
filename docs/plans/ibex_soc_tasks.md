# Ibex SoC Implementation Tasks

## Task Status

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Ibex CPU integration | ✅ Done | Debug stubbed, `third_party/ibex` submodule |
| 2 | FT601 PHY | ✅ Done | Pure SV at `hw/ip/usb/ft601/` |
| 3 | WB pipelined-to-classic bridge | ⏳ Pending | For CSR peripheral bus |
| 4 | SimCtrl peripheral | ⏳ Pending | Printf output + sim halt for Verilator |
| 5 | DPI backdoor for TCM | ⏳ Pending | Program loading + test stimulus |
| 6 | C toolchain (linker + crt0) | ⏳ Pending | Minimal bringup |
| 7 | Hello world test | ⏳ Pending | Validate RTL in simulation |
| 8 | Hardware bringup | ⏳ Pending | Squirrel board |
| 9 | SystemRDL registers | ⏳ Pending | Future: proper CSR generation |
| 10 | Rust/Embassy support | ⏳ Pending | Future: depends on SystemRDL |

---

## Completed Infrastructure

| Component | Location |
|-----------|----------|
| XDC Generator | `mono/tools/xdc/`, `hw/generators/xdc_generator.py` |
| Squirrel Board | `hw/boards/squirrel/` |
| TCM Memory | `hw/ip/mem/tcm/rtl/wb_tcm.sv` |
| Wishbone Crossbar | `hw/ip/bus/wb_crossbar/rtl/` |
| RISC-V Timer | `hw/ip/timer/rtl/wb_timer.sv` |
| OBI-to-WB Bridge | `hw/ip/cpu/ibex/rtl/ibex_obi2wb.sv` |
| Ibex WB Wrapper | `hw/ip/cpu/ibex/rtl/ibex_wb_top.sv` |
| FT601 PHY | `hw/ip/usb/ft601/rtl/ft601_sync.sv` |
| SoC Top Level | `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` |
| Board Top Level | `hw/projects/squirrel/ibex_soc/rtl/squirrel_ibex_top.sv` |

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                              ibex_soc_top                  │
│                                                            │
│  ┌─────────────────────┐                                   │
│  │    ibex_wb_top      │                                   │
│  │  ┌───────────────┐  │                                   │
│  │  │   ibex_top    │  │   ┌───────────────┐               │
│  │  └───────────────┘  │   │ Etherbone     |               │
│  │    │           │    │   | (USB host)    |               │
│  │  ibus        dbus   │   └──────┬────────┘               │
│  └────┼───────────┼────┘          │                        |
│       │           │               |                        |
│       │  Master 0 │  Master 1     │ Master 2               │
│       ▼           ▼               ▼                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                     wb_crossbar (3x3)                │  │
│  │                  Priority: ibus > dbus > eb          │  │
│  └──────┬─────────────────┬─────────────────┬───────────┘  │
│         │                 │                 │              │
│     Slave 0           Slave 1           Slave 2            │
│         │                 │                 │              │
│         ▼                 ▼                 ▼              │
│  ┌──────────┐ ┌─────────┐ ┌───────┐                        │
│  │   ITCM   │ │   DTCM  │ │ Timer │                        │
│  │  16KB    │ │  16KB   │ │       │                        │
│  └──────────┘ └─────────┘ └───────┘                        │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

Both ibus and dbus can access ITCM (required for `.rodata`/constant loads via D-port).

---

## Memory Map

| Region | Base | Size | Description |
|--------|------|------|-------------|
| ITCM | `0x0001_0000` | 16KB | Instruction memory |
| DTCM | `0x0002_0000` | 16KB | Data memory |
| Timer | `0x1000_0000` | 4KB | RISC-V timer |

---

## Task 3: WB Pipelined-to-Classic Bridge

**Scope:** Convert pipelined WB to classic 2-cycle WB for simple peripherals

**Purpose:** Allow CSR peripherals to use simpler classic WB interface while main crossbar uses pipelined WB for high-throughput DMA.

**Interface:**
- Slave side: WB pipelined (stall-based flow control)
- Master side: WB classic (cyc+stb held until ack, no stall)

**Behavior:**
- Accept pipelined request, hold request on classic side until ack
- Assert stall on slave side while classic transaction in progress
- Single outstanding transaction (no pipelining on classic side)

**Files:**
- `hw/ip/bus/wb_p2c/rtl/wb_pipelined_to_classic.sv` (new)

---

## Task 4: SimCtrl Peripheral

**Scope:** Simulation control peripheral for Verilator tests (like Ibex's `simulator_ctrl.sv`)

**Registers:**
- `SIM_OUT` (0x00): Write ASCII char → DPI call to print
- `SIM_CTRL` (0x04): Write 1 to halt simulation

**Features:**
- DPI functions for character output
- Simulation termination flag/`$finish`
- Classic WB interface (sits behind p2c bridge)

**Files:**
- `hw/ip/sim/sim_ctrl/rtl/sim_ctrl.sv` (new)

**Reference:** `third_party/ibex/shared/rtl/sim/simulator_ctrl.sv`

---

## Task 5: DPI Backdoor for TCM

**Scope:** Add DPI backdoor functions to TCM for Verilator test stimulus injection

**Approach (like Ibex):**
- Include `prim_util_memload.svh` equivalent in `wb_tcm.sv`
- Export `simutil_set_mem` / `simutil_get_mem` DPI functions
- C++ testbench uses `svSetScope()` + DPI calls for direct array access

**Usage:**
- Load ELF/VMEM into ITCM before simulation starts
- Inject test data into DTCM during tests
- Read back results without bus transactions

**Files:**
- `hw/ip/mem/tcm/rtl/wb_tcm.sv` (modify)
- `hw/dv/verilator/memutil.svh` (new, or reuse Ibex's)

**Reference:** `third_party/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_util_memload.svh`

---

## Task 6: C Toolchain (Linker + crt0)

**Scope:** Minimal C runtime for hardware validation

**Subtasks:**
1. Create linker script for TCM memory layout
2. Create crt0.S startup code (zero regs, init stack, clear BSS, call main)
3. Vector table with reset at 0x80

**Memory layout:**
- ITCM: 0x0001_0000, 16KB (code + rodata)
- DTCM: 0x0002_0000, 16KB (data + bss + stack)

**Files:**
- `sw/device/common/link.ld` (new)
- `sw/device/common/crt0.S` (new)

**Reference:** `third_party/ibex/examples/sw/simple_system/common/`

---

## Task 7: Hello World Test

**Scope:** Minimal C program to validate toolchain and RTL in simulation

**Behavior:**
- Write to SimCtrl to print "Hello"
- Loop with timer delay
- Halt simulation

**Files:**
- `sw/device/squirrel/ibex_soc/hello/main.c` (new)
- `sw/device/squirrel/ibex_soc/hello/Makefile` (new)

**Toolchain:** `riscv32-unknown-elf-gcc` with `-march=rv32imc -mabi=ilp32`

**Dependencies:** Tasks 4, 5, 6

---

## Task 8: Hardware Bringup

**Scope:** First hardware test on Squirrel board

**Subtasks:**
1. Synthesize and generate bitstream
2. Load via JTAG/SPI
3. Verify CPU running (LED blink or UART output)
4. Document bringup procedure

**Dependencies:** Task 7 (validated in simulation first)

---

## Task 9: SystemRDL Register Infrastructure (Future)

**Scope:** Set up register generation from SystemRDL

**Subtasks:**
1. Create `docs/rdl/ibex_soc.rdl` with CSR definitions
2. Evaluate SystemRDL tools (PeakRDL recommended)
3. Create SV register exporter
4. Create SVD exporter for Rust PAC generation

**Files:**
- `docs/rdl/ibex_soc.rdl` (new)
- `mono/tools/rdl/` (new)

---

## Task 10: Rust/Embassy Support (Future)

**Scope:** Rust toolchain with Embassy async runtime

**Subtasks:**
1. Generate SVD from SystemRDL (depends on Task 9)
2. Run svd2rust to create PAC crate
3. Create HAL crate with timer drivers
4. Create runtime crate with linker script and entry point
5. Port hello world to Rust with Embassy

**Files:**
- `sw/rust/ibex-pac/` (generated from SVD)
- `sw/rust/ibex-hal/`
- `sw/rust/ibex-rt/`
- `sw/rust/apps/hello-embassy/`

**Dependencies:** Task 9 (SystemRDL)

---

## Dependency Graph

```
Task 3 (WB p2c) ─┬─► Task 4 (SimCtrl) ─┬─► Task 7 (Hello) ─► Task 8 (Bringup)
                 │                      │
Task 5 (DPI) ────┘                      │
                                        │
Task 6 (C toolchain) ───────────────────┘

Task 9 (SystemRDL) ─► Task 10 (Rust)
```

## Suggested Order

1. **Task 3** - WB p2c bridge (enables simple peripherals)
2. **Task 4** - SimCtrl peripheral (printf for debug)
3. **Task 5** - DPI backdoor (program loading)
4. **Task 6** - Linker + crt0 (C runtime)
5. **Task 7** - Hello world (validate in sim)
6. **Task 8** - Hardware bringup
7. **Task 9** - SystemRDL (future)
8. **Task 10** - Rust support (future)

---

## Related Documentation

- Debug options: `docs/plans/ibex_debug_options.md`
- XDC generator: `docs/guides/xdc_generator.md`
- Verilog coding guidelines: `docs/guides/verilog/`
- Ibex simple_system reference: `third_party/ibex/examples/sw/simple_system/`

---

## Work Log

### 2026-01-25: SoC Cleanup

**Work completed:**
- Deleted `ibex_soc_mailbox.sv` (not needed - using DPI backdoor for test stimulus)
- Deleted `ibex_soc_csr.sv` (placeholder - will use SystemRDL-generated registers later)
- Updated `ibex_soc_pkg.sv`: reduced to 3 slaves (ITCM, DTCM, Timer), converted to CamelCase parameters
- Updated `ibex_soc_top.sv`: removed mailbox/CSR instances, CamelCase parameters
- Updated `wb_tcm.sv`: CamelCase parameters, removed redundant range check (crossbar handles address decode)
- Created `lint/verilator.vlt` waiver file with documented justifications
- Updated `ibex_soc.core`: removed deleted files, added conditional waiver fileset
- Added FuseSoC usage instructions to `CLAUDE.md`

**Files changed:**
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_pkg.sv`
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv`
- `hw/ip/soc/ibex_soc/ibex_soc.core`
- `hw/ip/soc/ibex_soc/lint/verilator.vlt` (new)
- `hw/ip/mem/tcm/rtl/wb_tcm.sv`
- `CLAUDE.md`

**Issues found and resolved:**
1. **Verilator UNOPTFLAT in crossbar**: False positive - transpose pattern and arbiter priority logic are intentional. Added waiver with justification.
2. **Verilator UNSIGNED in wb_tcm**: Range check `< Depth` was always true for power-of-2 sizes. Removed redundant check - crossbar ensures address is in range.
3. **Verilator comment parsing**: `// Verilator ...` in .vlt files is parsed as a pragma. Changed comment wording to avoid triggering.
4. **FuseSoC must run from repo root**: Added instructions to CLAUDE.md.

**Lint status:** PASS (with documented waivers)
