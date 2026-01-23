# Ibex SoC Implementation Tasks

## Task Status

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Ibex CPU integration | ✅ Done | Debug stubbed, `third_party/ibex` submodule |
| 2 | FT601 PHY | ✅ Done | Pure SV at `hw/ip/usb/ft601/` |
| 3 | SystemRDL registers | ⏳ Pending | |
| 4 | C toolchain | ⏳ Pending | crt0, linker script, hello world |
| 5 | Rust/Embassy support | ⏳ Pending | Depends on SystemRDL |
| 6 | Verification (cocotb) | ⏳ Pending | |
| 7 | Hardware bringup | ⏳ Pending | |

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
| SoC CSR Block | `hw/ip/soc/ibex_soc/rtl/ibex_soc_csr.sv` |
| SoC Mailbox | `hw/ip/soc/ibex_soc/rtl/ibex_soc_mailbox.sv` |
| SoC Top Level | `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` |
| Board Top Level | `hw/projects/squirrel/ibex_soc/rtl/squirrel_ibex_top.sv` |

---

## Memory Map

| Region | Base | Size | Description |
|--------|------|------|-------------|
| ITCM | `0x0001_0000` | 16KB | Instruction memory |
| DTCM | `0x0002_0000` | 16KB | Data memory |
| CSR | `0x1000_0000` | 4KB | Control/status registers |
| Timer | `0x1000_1000` | 4KB | RISC-V timer |
| Mailbox | `0x2000_0000` | 4KB | Host↔CPU communication |

---

## Task 3: SystemRDL Register Infrastructure

**Scope:** Set up register generation from SystemRDL

**Subtasks:**
1. Create `docs/rdl/ibex_soc.rdl` with CSR definitions
2. Evaluate SystemRDL tools (PeakRDL recommended)
3. Create SV register exporter
4. Create SVD exporter for Rust PAC generation
5. Replace hand-written `ibex_soc_csr.sv` with generated version

**Files:**
- `docs/rdl/ibex_soc.rdl` (new)
- `mono/tools/rdl/` (new)
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_regs.sv` (generated)

---

## Task 4: C Software Toolchain

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

## Task 5: Rust/Embassy Software Support

**Scope:** Rust toolchain with Embassy async runtime

**Subtasks:**
1. Generate SVD from SystemRDL (depends on Task 3)
2. Run svd2rust to create PAC crate
3. Create HAL crate with timer, gpio, mailbox drivers
4. Create runtime crate with linker script and entry point
5. Port hello world to Rust with Embassy

**Files:**
- `sw/rust/ibex-pac/` (generated from SVD)
- `sw/rust/ibex-hal/`
- `sw/rust/ibex-rt/`
- `sw/rust/apps/hello-embassy/`

**Dependencies:** Task 3 (SystemRDL)

---

## Task 6: Verification Infrastructure

**Scope:** Simulation and testing setup

**Subtasks:**
1. Create Verilator testbench infrastructure
2. Add cocotb tests for modules:
   - `test_wb_tcm.py`
   - `test_wb_timer.py`
   - `test_obi2wb.py`
   - `test_wb_crossbar.py`
   - `test_ft601_sync.py`
3. Create SoC-level boot test
4. Add CI configuration

**Files:**
- `hw/ip/*/tb/` directories
- `hw/sim/` common utilities
- `.github/workflows/`

---

## Task 7: Hardware Bringup

**Scope:** First hardware test on Squirrel board

**Subtasks:**
1. Synthesize and generate bitstream
2. Load via JTAG/SPI
3. Verify LED blinks (proves CPU running)
4. Test USB UART communication
5. Document bringup procedure

**Dependencies:** Task 4

---

## Dependency Graph

```
Task 3 (SystemRDL) ─► Task 5 (Rust SW)

Task 4 (C SW) ─► Task 7 (Bringup)

Task 6 (Verification) - independent
```

## Suggested Order

1. **Task 4** - C toolchain (fastest path to LED blink)
2. **Task 7** - Hardware bringup (validate RTL)
3. **Task 3** - SystemRDL (refine after basic bringup)
4. **Task 5** - Rust support
5. **Task 6** - Verification (ongoing)

---

## Related Documentation

- Debug options: `docs/plans/ibex_debug_options.md`
- XDC generator pyslang rewrite: `docs/guides/xdc_generator.md`
- Verilog coding guidelines: `docs/guides/verilog/`
