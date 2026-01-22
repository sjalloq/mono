# Ibex SoC Implementation - Task Breakdown

## Current State

The core RTL infrastructure is in place but needs refinement and dependencies resolved.

### Completed

| Component | Location | Status |
|-----------|----------|--------|
| XDC Generator Library | `mono/tools/xdc/` | Done (SV parser needs pyslang rewrite) |
| FuseSoC XDC Generator | `hw/generators/xdc_generator.py` | Done |
| Squirrel Board Definition | `hw/boards/squirrel/` | Done |
| TCM Memory | `hw/ip/mem/tcm/` | Done |
| Wishbone Crossbar | `hw/ip/bus/wb_crossbar/` | Done |
| RISC-V Timer | `hw/ip/timer/` | Done |
| OBI-to-WB Bridge | `hw/ip/cpu/ibex/rtl/ibex_obi2wb.sv` | Done |
| USB Etherbone Wrapper | `mono/gateware/wrappers/usb_etherbone.py` | Done |
| SoC CSR Block | `hw/ip/soc/ibex_soc/rtl/ibex_soc_csr.sv` | Done |
| SoC Mailbox | `hw/ip/soc/ibex_soc/rtl/ibex_soc_mailbox.sv` | Done |
| SoC Top Level | `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` | Done |
| Project Top Level | `hw/projects/squirrel/ibex_soc/` | Done |

### Needs Work

| Component | Issue |
|-----------|-------|
| Ibex WB Wrapper | References dm_top/dmi_jtag - needs proper JTAG integration or simplification |
| FuseSoC Dependencies | Need to add lowRISC/ibex and pulp-platform/riscv-dbg as library sources |
| SV Parser | Rewrite with pyslang (separate task, doc at `docs/guides/xdc_generator.md`) |

---

## Remaining Tasks

### Task 1: Fix Ibex Wrapper and Dependencies

**Scope:** Get the Ibex CPU compiling with proper dependencies

**Subtasks:**
1. Stub out debug interface (no JTAG on this board, see `docs/plans/ibex_debug_options.md` for future options)
2. Update `hw/ip/cpu/ibex/ibex.core` with correct dependencies (just lowRISC/ibex)
3. Create `fusesoc.conf` library entries or document how to add them
4. Verify Ibex wrapper compiles with `fusesoc run --target=lint`

**Files:**
- `hw/ip/cpu/ibex/rtl/ibex_wb_top.sv`
- `hw/ip/cpu/ibex/ibex.core`
- `fusesoc.conf`

---

### Task 2: FT601 PHY Integration

**Scope:** Properly integrate the Migen FT601 PHY with the SV toplevel

**Subtasks:**
1. Create FT601 Migen wrapper that exposes clean stream interface
2. Add FuseSoC core for FT601
3. Update project toplevel to instantiate generated FT601 module
4. Handle USB clock domain (100MHz from FT601)
5. Connect FT601 streams to USB Etherbone

**Files:**
- `mono/gateware/wrappers/ft601.py` (new)
- `hw/ip/usb/ft601.core` (new)
- `hw/projects/squirrel/ibex_soc/rtl/squirrel_ibex_top.sv`

---

### Task 3: SystemRDL Register Infrastructure

**Scope:** Set up register generation from SystemRDL

**Subtasks:**
1. Create initial `docs/rdl/ibex_soc.rdl` with CSR definitions
2. Evaluate/choose SystemRDL tool (PeakRDL, etc.)
3. Create SV register exporter or use existing
4. Create SVD exporter for Rust PAC generation
5. Replace hand-written `ibex_soc_csr.sv` with generated version

**Files:**
- `docs/rdl/ibex_soc.rdl` (new)
- `mono/tools/rdl/` (new)
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_regs.sv` (generated)

---

### Task 4: C Software Toolchain

**Scope:** Basic C build environment and hello world

**Subtasks:**
1. Create linker script for TCM memory layout
2. Create RISC-V startup code (crt0.S, vectors)
3. Create minimal runtime (uart stub, timer access)
4. Create CMake build system
5. Write hello world that blinks LED via CSR
6. Document toolchain setup (riscv32-unknown-elf-gcc)

**Files:**
- `sw/device/common/linker.ld`
- `sw/device/common/crt0.S`
- `sw/device/common/vectors.S`
- `sw/device/squirrel/ibex_soc/hello/`
- `docs/guides/software_setup.md`

---

### Task 5: Rust/Embassy Software Support

**Scope:** Rust toolchain with Embassy async runtime

**Subtasks:**
1. Generate SVD from SystemRDL (depends on Task 3)
2. Run svd2rust to create PAC crate
3. Create HAL crate with timer, gpio, mailbox drivers
4. Create runtime crate with linker script and entry point
5. Port hello world to Rust with Embassy
6. Document Rust toolchain setup

**Files:**
- `sw/rust/ibex-pac/` (generated from SVD)
- `sw/rust/ibex-hal/`
- `sw/rust/ibex-rt/`
- `sw/rust/apps/hello-embassy/`

**Dependencies:** Task 3 (SystemRDL), Task 4 (linker script can be shared)

---

### Task 6: Verification Infrastructure

**Scope:** Simulation and testing setup

**Subtasks:**
1. Create Verilator testbench infrastructure
2. Add cocotb tests for individual modules:
   - `test_wb_tcm.py` - Memory read/write
   - `test_wb_timer.py` - Timer functionality
   - `test_obi2wb.py` - Protocol bridge
   - `test_wb_crossbar.py` - Address decode, arbitration
3. Create SoC-level boot test
4. Add CI configuration (GitHub Actions)

**Files:**
- `hw/ip/*/tb/` directories
- `hw/sim/` common simulation utilities
- `.github/workflows/` CI config

---

### Task 7: Hardware Bringup

**Scope:** First hardware test on Squirrel board

**Subtasks:**
1. Synthesize and generate bitstream
2. Load via JTAG/SPI
3. Verify LED blinks (proves CPU running)
4. Test Etherbone access from host
5. Test JTAG debug connection (if implemented)
6. Document bringup procedure

**Dependencies:** Tasks 1, 2, 4

---

## Task Dependency Graph

```
Task 1 (Ibex/Deps) ──┬──► Task 4 (C SW) ──────┬──► Task 7 (Bringup)
                     │                        │
Task 2 (FT601) ──────┤                        │
                     │                        │
Task 3 (SystemRDL) ──┴──► Task 5 (Rust SW) ───┘

Task 6 (Verification) ── independent, can run in parallel

SV Parser (pyslang) ── independent, separate context
```

## Suggested Execution Order

1. **Task 1** - Get Ibex compiling (blocks everything)
2. **Task 2** - FT601 integration (needed for host communication)
3. **Task 4** - C toolchain (fastest path to LED blink)
4. **Task 7** - Hardware bringup (validate RTL works)
5. **Task 3** - SystemRDL (can refine after basic bringup)
6. **Task 5** - Rust support (nice to have)
7. **Task 6** - Verification (ongoing)

## Context Window Recommendations

| Task | Estimated Complexity | Can Split Further? |
|------|---------------------|-------------------|
| Task 1 | Medium | No - tightly coupled |
| Task 2 | Small | No |
| Task 3 | Medium | Yes - tool setup vs RDL authoring |
| Task 4 | Medium | Yes - linker/startup vs application |
| Task 5 | Large | Yes - PAC vs HAL vs app |
| Task 6 | Large | Yes - per-module tests |
| Task 7 | Small | No |
