# Ibex SoC Implementation Tasks

## Task Status

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Ibex CPU integration | ✅ Done | Debug stubbed, `third_party/ibex` submodule |
| 2 | FT601 PHY | ✅ Done | Pure SV at `hw/ip/usb/ft601/` |
| 3 | SimCtrl peripheral | ✅ Done | Printf output + sim halt for Verilator |
| 4 | DPI backdoor for TCM | ✅ Done | Program loading + test stimulus |
| 5 | C toolchain (linker + crt0) | ✅ Done | Minimal bringup, SimCtrl integrated |
| 6 | Hello world test | ⏳ Pending | Validate RTL in simulation |
| 7 | Hardware bringup | ⏳ Pending | Squirrel board |
| 8 | SystemRDL registers | ⏳ Pending | Future: proper CSR generation |
| 9 | Rust/Embassy support | ⏳ Pending | Future: depends on SystemRDL |

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
| SimCtrl | `hw/ip/sim/sim_ctrl/rtl/wb_sim_ctrl.sv` |
| SoC Top Level | `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` |
| Board Top Level | `hw/projects/squirrel/ibex_soc/rtl/squirrel_ibex_top.sv` |
| C Toolchain | `sw/device/ibex_soc/` (linker, crt0, HAL) |

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
│  │                     wb_crossbar (3x4)                │  │
│  │                  Priority: ibus > dbus > eb          │  │
│  └──────┬─────────────────┬────────────┬────────┬───────┘  │
│         │                 │            │        │          │
│     Slave 0           Slave 1      Slave 2   Slave 3       │
│         │                 │            │        │          │
│         ▼                 ▼            ▼        ▼          │
│  ┌──────────┐ ┌─────────┐ ┌───────┐ ┌─────────┐            │
│  │   ITCM   │ │   DTCM  │ │ Timer │ │ SimCtrl │            │
│  │  16KB    │ │  16KB   │ │       │ │         │            │
│  └──────────┘ └─────────┘ └───────┘ └─────────┘            │
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
| SimCtrl | `0x1000_1000` | 4KB | Simulation control (printf + halt) |

---

## Task 3: SimCtrl Peripheral (DONE)

**Scope:** Simulation control peripheral for Verilator tests (like Ibex's `simulator_ctrl.sv`)

**Registers:**
- `SIM_OUT` (0x00): Write ASCII char [7:0] → `$fwrite` to log file
- `SIM_CTRL` (0x08): Write 1 to bit 0 → `$finish` after 2-cycle delay

**Features:**
- Character output via `$fwrite` to configurable log file (default: `sim_out.log`)
- Optional flush on every character for real-time monitoring
- Simulation termination with delay to allow final transactions
- Wishbone pipelined interface (stall=0, single-cycle response)
- Synthesis stub: responds to bus but no functionality

**Files:**
- `hw/ip/sim/sim_ctrl/rtl/wb_sim_ctrl.sv`
- `hw/ip/sim/sim_ctrl/sim_ctrl.core`

**Reference:** `third_party/ibex/shared/rtl/sim/simulator_ctrl.sv`

---

## Task 4: DPI Backdoor for TCM (DONE)

**Scope:** Add DPI backdoor functions to TCM for Verilator test stimulus injection

**Approach:** Include `prim_util_memload.svh` from Ibex via FuseSoC dependency

**DPI Functions (provided by prim_util_memload.svh):**
- `simutil_memload(file)` - Load VMEM file via `$readmemh`
- `simutil_set_mem(index, val)` - Backdoor write single word
- `simutil_get_mem(index, val)` - Backdoor read single word

**Usage:**
- C++ testbench uses `svSetScope()` to select ITCM or DTCM instance
- Load ELF/VMEM into ITCM before simulation starts
- Inject test data into DTCM during tests
- Read back results without bus transactions
- Use `+show_mem_paths` plusarg to print hierarchical paths

**Files:**
- `hw/ip/mem/tcm/rtl/wb_tcm.sv` - Added include and parameter aliases
- `hw/ip/mem/tcm/tcm.core` - Added `lowrisc:prim:util_memload` dependency

**Reference:** `third_party/ibex/vendor/lowrisc_ip/ip/prim/rtl/prim_util_memload.svh`

---

## Task 5: C Toolchain (Linker + crt0) (DONE)

**Scope:** Minimal C runtime for hardware validation

**Subtasks:**
1. Integrate SimCtrl into SoC (add to memory map and instantiate)
2. Create linker script for TCM memory layout
3. Create crt0.S startup code (zero regs, init stack, copy .data, clear BSS, call main)
4. Create minimal HAL (putchar, puts, puthex, sim_halt, timer functions)
5. Vector table with reset at 0x80

**Memory layout:**
- ITCM: 0x0001_0000, 16KB (code + rodata)
- DTCM: 0x0002_0000, 16KB (data + bss + stack)

**Files:**
- `sw/device/ibex_soc/link.ld` - Linker script
- `sw/device/ibex_soc/crt0.S` - Startup code
- `sw/device/ibex_soc/common.mk` - Shared Makefile
- `sw/device/ibex_soc/lib/ibex_soc_regs.h` - Register definitions
- `sw/device/ibex_soc/lib/ibex_soc.h` - HAL header
- `sw/device/ibex_soc/lib/ibex_soc.c` - HAL implementation

**Toolchain:** lowRISC prebuilt from https://github.com/lowRISC/lowrisc-toolchains/releases

**Reference:** `third_party/ibex/examples/sw/simple_system/common/`

---

## Task 6: Hello World Test

**Scope:** Minimal C program to validate toolchain and RTL in simulation

**Behavior:**
- Write to SimCtrl to print "Hello from ibex_soc!"
- Print memory map info
- Read and print timer value
- Halt simulation

**Files:**
- `sw/device/squirrel/ibex_soc/hello/main.c`
- `sw/device/squirrel/ibex_soc/hello/Makefile`

**Build:** `make -C sw/device/squirrel/ibex_soc/hello`

**Toolchain:** `riscv32-unknown-elf-gcc` with `-march=rv32imc -mabi=ilp32`

**Dependencies:** Tasks 3, 4, 5

---

## Task 7: Hardware Bringup

**Scope:** First hardware test on Squirrel board

**Subtasks:**
1. Synthesize and generate bitstream
2. Load via JTAG/SPI
3. Verify CPU running (LED blink or UART output)
4. Document bringup procedure

**Dependencies:** Task 6 (validated in simulation first)

---

## Task 8: SystemRDL Register Infrastructure (Future)

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

## Task 9: Rust/Embassy Support (Future)

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

**Dependencies:** Task 8 (SystemRDL)

---

## Dependency Graph

```
Task 3 (SimCtrl) ───┬─► Task 6 (Hello) ─► Task 7 (Bringup)
                    │
Task 4 (DPI) ───────┤
                    │
Task 5 (C toolchain)┘

Task 8 (SystemRDL) ─► Task 9 (Rust)
```

## Suggested Order

1. **Task 3** - SimCtrl peripheral (printf for debug)
2. **Task 4** - DPI backdoor (program loading)
3. **Task 5** - Linker + crt0 (C runtime)
4. **Task 6** - Hello world (validate in sim)
5. **Task 7** - Hardware bringup
6. **Task 8** - SystemRDL (future)
7. **Task 9** - Rust support (future)

---

## Related Documentation

- Debug options: `docs/plans/ibex_debug_options.md`
- XDC generator: `docs/guides/xdc_generator.md`
- Verilog coding guidelines: `docs/guides/verilog/`
- Ibex simple_system reference: `third_party/ibex/examples/sw/simple_system/`

---

## Work Log

### 2026-01-26: C Toolchain and SimCtrl Integration

**Work completed:**
- Integrated SimCtrl peripheral into ibex_soc (slave 3 at 0x1000_1000)
- Created C toolchain for ibex_soc bringup
- Created hello world test program

**RTL changes:**
- `ibex_soc_pkg.sv`: Added SimCtrl to memory map (NumSlaves 3→4)
- `ibex_soc_top.sv`: Instantiated wb_sim_ctrl
- `ibex_soc.core`: Added mono:ip:sim_ctrl dependency
- `lint/verilator.vlt`: Added waivers for sim_ctrl unused signal bits

**SW files created:**
- `sw/device/ibex_soc/link.ld` - Linker script (ITCM for code, DTCM for data/stack)
- `sw/device/ibex_soc/crt0.S` - Startup code (vector table, register init, .data copy, BSS clear)
- `sw/device/ibex_soc/common.mk` - Shared Makefile for apps
- `sw/device/ibex_soc/lib/ibex_soc_regs.h` - Register definitions (for C and asm)
- `sw/device/ibex_soc/lib/ibex_soc.h` - HAL header
- `sw/device/ibex_soc/lib/ibex_soc.c` - HAL implementation (putchar, puts, puthex, sim_halt, timer)
- `sw/device/squirrel/ibex_soc/hello/main.c` - Hello world test
- `sw/device/squirrel/ibex_soc/hello/Makefile` - Test Makefile

**SW directory structure decision:**
- `sw/device/ibex_soc/` for SoC-specific toolchain (shared across boards)
- `sw/device/<board>/<soc>/<app>/` for board+SoC-specific apps
- This C runtime is for bringup only; Rust/Embassy is the long-term target

**Lint status:** PASS

**Next:** Install lowRISC toolchain and build hello world (Task 6)

---

### 2026-01-26: SimCtrl Peripheral and TCM DPI Backdoor

**Work completed:**
- Created `wb_sim_ctrl.sv` - Wishbone pipelined simulation control peripheral
- Updated `wb_tcm.sv` - Include `prim_util_memload.svh` from Ibex for DPI backdoor
- Created FuseSoC core file for sim_ctrl
- Added lint waivers for expected unused signals

**SimCtrl features:**
- Register map: 0x00 (SIM_OUT), 0x08 (SIM_CTRL) - matches Ibex spacing
- Character output via `$fwrite` to configurable log file
- Simulation halt via `$finish` with 2-cycle delay
- Synthesis stub (responds to bus but no functionality)
- Wrapped in `ifdef VERILATOR` / `else` for synthesis

**TCM DPI functions (via lowRISC prim_util_memload.svh):**
- `simutil_memload(file)` - Load VMEM file via `$readmemh`
- `simutil_set_mem(index, val)` - Backdoor write single word
- `simutil_get_mem(index, val)` - Backdoor read single word
- `+show_mem_paths` plusarg to print hierarchical memory paths
- Added parameter aliases (Width, MemInitFile) for include compatibility

**Files created:**
- `hw/ip/sim/sim_ctrl/rtl/wb_sim_ctrl.sv`
- `hw/ip/sim/sim_ctrl/sim_ctrl.core`

**Files modified:**
- `hw/ip/mem/tcm/rtl/wb_tcm.sv` - Added include and parameter aliases
- `hw/ip/mem/tcm/tcm.core` - Added toplevel, lint waiver, `lowrisc:prim:util_memload` dependency
- `hw/ip/soc/ibex_soc/lint/verilator.vlt` - Added Ibex FPGA regfile waivers

**Lint status:** PASS (sim_ctrl, tcm, ibex_soc)

---

### 2026-01-26: Removed WB Pipelined-to-Classic Bridge Task

**Decision:** Removed Task 3 (WB pipelined-to-classic bridge) from the plan.

**Rationale:**
- Simple peripherals like SimCtrl can use "trivial pipelined" WB interface (same pattern as `wb_timer.sv`)
- Just tie `wb_stall_o = 1'b0` and respond with ack one cycle after request
- The crossbar already handles stall signal routing
- No need for a bridge when writing fresh RTL - only useful for integrating legacy classic-only IP

**Impact:**
- Renumbered Tasks 4-10 → Tasks 3-9
- SimCtrl (now Task 3) has no dependencies
- Critical path shortened by one task

---

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
