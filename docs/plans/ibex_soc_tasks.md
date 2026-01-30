# Ibex SoC Implementation Tasks

## Task Status

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Ibex CPU integration | ✅ Done | Debug stubbed, `third_party/ibex` submodule |
| 2 | FT601 PHY | ✅ Done | Pure SV at `hw/ip/usb/ft601/` |
| 3 | SimCtrl peripheral | ✅ Done | Printf output + sim halt for Verilator |
| 4 | DPI backdoor for TCM | ✅ Done | Program loading + test stimulus |
| 5 | C toolchain (linker + crt0) | ✅ Done | Minimal bringup, SimCtrl integrated |
| 6 | Hello world test | ✅ Done | Cocotb testbench with Verilator |
| 7 | Hardware bringup | ⏳ Pending | Squirrel board |
| 8 | SystemRDL registers | ⏳ Pending | Future: proper CSR generation |
| 9 | Rust/Embassy support | ⏳ Pending | Future: depends on SystemRDL |
| 10 | GPIO peripheral | ✅ Done | Standalone IP with per-bit ops + interrupts |

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
| USB Subsystem | `hw/projects/squirrel/ibex_soc/rtl/usb_subsystem.sv` |
| SoC Top Level | `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` |
| GPIO Peripheral | `hw/ip/gpio/rtl/gpio.sv` |
| Core Level | `hw/projects/squirrel/ibex_soc/rtl/core.sv` |
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

Peripherals are auto-assigned consecutive 4K windows from `PeriphBase = 0x1000_0000`.
No overlap is possible by construction. External slaves continue the sequence.

| Region | Base | Size | Type | Slot |
|--------|------|------|------|------|
| ITCM | `0x0001_0000` | 16KB | Memory | — |
| DTCM | `0x0002_0000` | 16KB | Memory | — |
| Timer | `0x1000_0000` | 4KB | Peripheral | 0 |
| SimCtrl | `0x1000_1000` | 4KB | Peripheral | 1 |
| USB UART | `0x1000_2000` | 4KB | Peripheral (ext) | 2 |

---

## Task 3: SimCtrl Peripheral (DONE)

**Scope:** Simulation control peripheral for Verilator tests (like Ibex's `simulator_ctrl.sv`)

**Registers:**
- `SIM_OUT` (0x00): Write ASCII char [7:0] → `$fwrite` to log file
- `SIM_CTRL` (0x08): Write 1 to bit 0 → halt simulation

**Parameters:**
- `LogName` - Log file path (default: `sim_out.log`)
- `FlushOnChar` - Flush log on every character (default: 1)
- `UseFinish` - Use `$finish` to terminate (default: 0 for Cocotb compatibility)

**Output signals (for Cocotb observability):**
- `sim_halt_o` - High when software requests halt
- `char_valid_o` - Pulse when character written
- `char_data_o` - Character value [7:0]

**Features:**
- Character output via `$fwrite` to configurable log file
- Optional flush on every character for real-time monitoring
- Simulation termination with delay to allow final transactions
- Cocotb-compatible: testbench monitors `sim_halt_o` instead of relying on `$finish`
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

## Task 6: Hello World Test (DONE)

**Scope:** Minimal C program to validate toolchain and RTL in simulation

**Behavior:**
- Write to SimCtrl to print "Hello from ibex_soc!"
- Print memory map info
- Read and print timer value
- Halt simulation

**C program files:**
- `sw/device/squirrel/ibex_soc/hello/main.c`
- `sw/device/squirrel/ibex_soc/hello/Makefile`

**Cocotb testbench files:**
- `hw/ip/soc/ibex_soc/dv/Makefile` - Cocotb/Verilator Makefile
- `hw/ip/soc/ibex_soc/dv/testbench.py` - Cocotb test module
- `hw/ip/soc/ibex_soc/dv/filelist.f` - Generated file list

**Build firmware:** `make -C sw/device/squirrel/ibex_soc/hello`

**Run test:** `cd hw/ip/soc/ibex_soc/dv && make`

**Toolchain:** `riscv32-unknown-elf-gcc` with `-march=rv32imc -mabi=ilp32`

**Dependencies:** Tasks 3, 4, 5

---

## Task 7: Hardware Bringup

**Scope:** First hardware test on Squirrel board with USB communication

### Phase 1: USB Core Integration

**7.1 USB Core via Migen Generator**
- Use FuseSoC migen_netlister to generate USB core Verilog
- USB Packetizer/Depacketizer + Crossbar from existing LiteX code
- Integrate FT601 PHY with USB core

**7.2 USB UART Peripheral (Channel 2)**
- Create SystemRDL: `docs/rdl/usb_uart.rdl`
- Generate CSR block with PeakRDL-sv
- Implement `wb_usb_uart.sv`:
  - Wishbone slave via wb2simple adapter
  - TX FIFO with newline detection and timer flush
  - RX FIFO with packet length tracking
  - Stream interface to USB crossbar
- Spec: `docs/source/usb/usb_uart.rst`

**7.3 SoC Integration**
- Add USB UART to crossbar (Slave 4 at `0x1000_2000`)
- Connect USB core stream interfaces
- Update ibex_soc_pkg.sv memory map
- Tie off SimCtrl in synthesis (keep for simulation)

**7.4 HAL Update**
- Add USB UART driver to `sw/device/ibex_soc/lib/`
- Modify putchar() to use USB UART when not in simulation
- Add readline() for REPL input

### Phase 2: Host Software

**7.5 Channel Multiplexer**
- Rust server to demux USB channels to endpoints
- Channel 0: Etherbone (existing)
- Channel 2: USB UART → PTY or TCP socket

**7.6 REPL Test**
- Simple command parser in firmware
- Verify bidirectional communication

### Phase 3: Synthesis

**7.7 Bitstream Generation**
- Synthesize with Vivado
- Generate programming files

**7.8 Hardware Test**
- Load bitstream via JTAG/SPI
- Verify printf output via USB UART
- Test REPL commands
- Document bringup procedure

**Dependencies:** Task 6 (validated in simulation first)

**Files:**
- `hw/ip/usb/uart/rdl/usb_uart_csr.rdl` - SystemRDL register definition
- `hw/ip/usb/uart/rtl/usb_uart.sv` - USB UART peripheral
- `hw/ip/usb/uart/usb_uart.core` - FuseSoC core file
- `sw/device/ibex_soc/lib/usb_uart.c` - HAL driver

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

- USB subsystem: `docs/source/usb/` (FT601, protocol, Etherbone, USB UART)
- Debug options: `docs/plans/ibex_debug_options.md`
- XDC generator: `docs/guides/xdc_generator.md`
- Verilog coding guidelines: `docs/guides/verilog/`
- Ibex simple_system reference: `third_party/ibex/examples/sw/simple_system/`

---

## Work Log

### 2026-01-29: Move crossbar address map from parameters to input ports

**Work completed:**
- Moved `AddrBase`/`AddrMask` from parameters to input ports (`cfg_addr_base_i`/`cfg_addr_mask_i`) on `wb_crossbar` and `wb_crossbar_decoder`
- Replaced `getSlaveAddrs()`/`getSlaveMasks()` functions in `ibex_soc_top` with simple `assign` statements and a `genvar` loop for peripheral addresses
- Crossbar address map is now configured via port connections instead of compile-time parameters, following the Ibex demo system pattern

**Files modified:**
- `hw/ip/bus/wb_crossbar/rtl/wb_crossbar_decoder.sv` — Removed `AddrBase`/`AddrMask` parameters, added `cfg_addr_base_i`/`cfg_addr_mask_i` input ports, updated address decode logic
- `hw/ip/bus/wb_crossbar/rtl/wb_crossbar.sv` — Same parameter-to-port change, pass through to decoder instances
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` — Replaced functions with `assign` statements and `genvar` loop, updated crossbar instantiation to use port connections
- `docs/plans/ibex_soc_tasks.md` — Added work log entry

**Lint status:** PASS (`mono:ip:ibex_soc`)

---

### 2026-01-29: Fixed 4K Peripheral Address Windows

**Work completed:**
- Formalized peripheral address assignment: all peripherals get consecutive 4K windows from `PeriphBase = 0x1000_0000`
- Split slaves into two categories: memories (ITCM, DTCM) with configurable base/mask, and peripherals with auto-assigned addresses
- Added `PeriphBase`, `PeriphMask`, `NumMemSlaves`, `NumIntPeriphs`, peripheral slot indices (`PeriphTimer`, `PeriphSimCtrl`)
- Derived `TimerBase` and `SimCtrlBase` from slot formula (values unchanged: `0x1000_0000`, `0x1000_1000`)
- Removed `TimerSize`, `TimerMask`, `SimCtrlSize`, `SimCtrlMask` (replaced by shared `PeriphMask`)
- Removed `ExtSlaveBase` and `ExtSlaveMask` parameters from `ibex_soc_top` — external slaves now auto-assigned from slot `NumIntPeriphs` onward
- Removed `getSlaveAddrs()`/`getSlaveMasks()` from package, consolidated into single pair of functions in `ibex_soc_top`
- Functions loop over all peripherals (internal + external) in one pass: `PeriphBase + i * 0x1000`
- No overlap possible by construction

**Files modified:**
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_pkg.sv` — Restructured parameters, loop-based address/mask functions
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` — Removed ExtSlaveBase/ExtSlaveMask, auto-assign external peripheral addresses
- `docs/plans/ibex_soc_tasks.md` — Updated memory map table, added work log

**Lint status:** PASS (`mono:ip:ibex_soc`)

---

### 2026-01-29: Proper Interrupt Registers for USB UART

**Work completed:**
- Moved overflow bits (`rx_overflow`, `len_overflow`) from `status` register to new `irq_status` register
- Moved IRQ enables (`irq_rx_en`, `irq_tx_empty_en`) from `ctrl` register to new `irq_enable` register
- Added `irq_status` (0x20) — 4-bit W1C sticky event flags with HW set via `de` pulse
- Added `irq_enable` (0x24) — 4-bit RW mask, `irq_o = |(irq_status & irq_enable)`
- Added rising-edge detection for `rx_valid` and `tx_empty` level signals
- `status` register is now purely read-only (bits [11:0] only)
- `ctrl` register reduced to bits [7:0] (no IRQ enables)
- Regenerated CSR files from updated RDL (BlockAw increased from 5 to 6)

**Files modified:**
- `hw/ip/usb/uart/rdl/usb_uart_csr.rdl` — Removed overflow/IRQ fields, added irq_status and irq_enable registers
- `hw/ip/usb/uart/rtl/usb_uart.sv` — Edge detect logic, irq_status/irq_enable wiring, new IRQ output
- `hw/ip/usb/uart/rtl/usb_uart_csr_reg_pkg.sv` — Regenerated
- `hw/ip/usb/uart/rtl/usb_uart_csr_reg_top.sv` — Regenerated
- `docs/source/usb/usb_uart.rst` — Updated register docs, memory map, interrupt behavior

**Lint status:** PASS

---

### 2026-01-29: USB UART Reorganization and Feature Additions

**Work completed:**
- Deleted `hw/ip/usb_bridge/` (superseded by usb_uart)
- Moved `hw/ip/usb_uart/` to `hw/ip/usb/uart/`
- Added configurable `flush_char` register at 0x1C (default 0x0A = newline)
- Renamed `nl_flush_en` to `char_flush_en` throughout RDL and RTL
- Added RX overflow tracking: sticky W1C bits `rx_overflow` [16] and `len_overflow` [17] in status register
- Added `tx_clear` singlepulse at ctrl[7] for TX FIFO discard/reset
- Regenerated CSR files from updated RDL
- Updated docs and task plan file paths
- Fixed peakrdl-sv `pkg_resources` dependency (replaced with `importlib.resources`)
- Updated `sourceme` to use `uv sync` instead of manual pip install
- Updated `pyproject.toml` to pin peakrdl-sv at tag 0.1.0

**Files deleted:**
- `hw/ip/usb_bridge/` (entire directory)

**Files moved:**
- `hw/ip/usb_uart/*` → `hw/ip/usb/uart/*`

**Files modified:**
- `hw/ip/usb/uart/rdl/usb_uart_csr.rdl` - flush_char, overflow bits, tx_clear, nl→char rename
- `hw/ip/usb/uart/rtl/usb_uart.sv` - Wire new CSR fields, overflow signals, tx_clear
- `hw/ip/usb/uart/rtl/usb_uart_tx_fifo.sv` - Configurable flush char, sw_clear input
- `hw/ip/usb/uart/rtl/usb_uart_rx_fifo.sv` - Overflow output signals
- `hw/ip/usb/uart/rtl/usb_uart_csr_reg_pkg.sv` - Regenerated
- `hw/ip/usb/uart/rtl/usb_uart_csr_reg_top.sv` - Regenerated
- `docs/source/usb/usb_uart.rst` - Updated file paths, tx_clear in ctrl
- `docs/plans/ibex_soc_tasks.md` - Updated file paths in Task 7
- `sourceme` - Use `uv sync`
- `pyproject.toml` - Pin peakrdl-sv@0.1.0

---

### 2026-01-27: USB UART Channel Specification

**Work completed:**
- Created functional specification for USB UART (Channel 2)
- Designed register interface compatible with PeakRDL-sv CSR generation
- Documented TX path with newline detection and timer-based flush
- Documented RX path with packet length tracking for REPL input

**Design decisions:**
- 32-bit word interface (no byte writes) for efficient bulk transfers
- Auto-flush on newline (`\n`) for interactive printf
- Timer-based flush for partial lines (default 1ms timeout)
- Separate address from SimCtrl (`0x1000_2000`) - SimCtrl kept for simulation
- Uses existing CSR infrastructure (`hw/ip/csr/`) with wb2simple adapter

**Files created:**
- `docs/source/usb/usb_uart.rst` - Full specification with register map and SW examples

**Files modified:**
- `docs/source/usb/index.rst` - Added usb_uart to toctree
- `docs/source/usb/overview.rst` - Updated channel allocation table and architecture diagram
- `docs/plans/ibex_soc_tasks.md` - Expanded Task 7 with USB UART subtasks, updated memory map

**Next:** Create SystemRDL file and implement wb_usb_uart.sv

---

### 2026-01-27: Cocotb Testbench and SimCtrl Cocotb Integration

**Work completed:**
- Created Cocotb testbench for ibex_soc hello world validation
- Enhanced wb_sim_ctrl.sv with output signals for Cocotb observability
- Test passes: CPU boots, runs hello world, halts cleanly

**SimCtrl enhancements for Cocotb:**
- Added `UseFinish` parameter (default 0) - disables `$finish` for Cocotb compatibility
- Added `sim_halt_o` output - goes high when software requests simulation halt
- Added `char_valid_o` / `char_data_o` outputs - pulses when character written
- Cocotb can now monitor these signals instead of relying on `$finish` (which causes test failure)

**Files created:**
- `hw/ip/soc/ibex_soc/dv/Makefile` - Cocotb Makefile for Verilator
- `hw/ip/soc/ibex_soc/dv/testbench.py` - Cocotb test module
- `hw/ip/soc/ibex_soc/dv/filelist.f` - Generated via `flist` tool

**Files modified:**
- `hw/ip/sim/sim_ctrl/rtl/wb_sim_ctrl.sv` - Added Cocotb-friendly outputs and UseFinish parameter
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` - Added sim_halt_o, sim_char_valid_o, sim_char_data_o ports

**Cocotb test pattern:**
- Monitor `sim_char_valid_o` to capture printf output
- Wait on `RisingEdge(dut.sim_halt_o)` instead of `$finish`
- Test completes cleanly without simulator killing itself

**Next:** Task 7 - Hardware bringup on Squirrel board

---

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

---

### 2026-01-29: USB Subsystem + Squirrel core/top Hierarchy

**Work completed:**
- Created `usb_subsystem.sv` integrating USB Core (Migen-generated) with USB UART peripheral
- Channel assignment: ch0 = USB UART (CHANNEL_ID=0), ch1 = Etherbone (tied off, future)
- Etherbone WB master port exists but is tied to `'0` for now
- Restructured Squirrel board hierarchy: `squirrel_ibex_top` (Xilinx prims) -> `core` (functional logic)
- `squirrel_ibex_top` now contains only: MMCM, BUFG, POR SRL16E, reset synchronizer, FT601 IOBUFs
- `core.sv` now contains: FT601 PHY, USB subsystem, Ibex SoC (NumExtSlaves=1), LED heartbeat
- USB UART connected to ibex_soc ext_wb port (address `0x1000_2000`)
- FT601 ports uncommented in top-level (no longer commented out)
- Added `-Wno-MODMISSING` to project lint target for Xilinx primitives

**Known limitations:**
- ~~No CDC between FT601 and USB subsystem~~ — Fixed: async FIFOs added (2026-01-30)
- USB UART IRQ not yet connected to CPU interrupt controller

**Files created:**
- `hw/projects/squirrel/ibex_soc/rtl/usb_subsystem.sv` — Project-specific USB subsystem glue (not a reusable IP — channel assignment and tie-offs are board-specific)

**Files modified:**
- `hw/projects/squirrel/ibex_soc/rtl/squirrel_ibex_top.sv` — Replaced ibex_soc_top with core, added IOBUFs, uncommented FT601 ports
- `hw/projects/squirrel/ibex_soc/rtl/core.sv` — Major rework: ft601_sync + usb_subsystem + ibex_soc_top
- `hw/projects/squirrel/ibex_soc/project.core` — Added ft601, usb_core, usb_uart, wb_pkg deps, added core.sv + usb_subsystem.sv, -Wno-MODMISSING
- `hw/projects/squirrel/ibex_soc/lint/verilator.vlt` — Updated waivers for new hierarchy (includes Migen usb_core.v waivers)
- `docs/plans/ibex_soc_tasks.md` — Updated infrastructure table, added work log

**Lint status:** PASS (`mono:ip:usb_subsystem`, `mono:projects:squirrel_ibex_soc`, `mono:ip:ibex_soc`)

---

### 2026-01-29: Convert all Wishbone interfaces to wb_pkg structs

**Work completed:**
- Converted all module Wishbone ports from individual signals to `wb_m2s_t`/`wb_s2m_t` structs from `wb_pkg`
- Bottom-up approach: leaf slaves/bridges first, then crossbar, then integration modules
- Crossbar internal logic (transpose, decode, arbitrate) keeps individual signals; structs are unpacked/repacked at module boundaries via generate loops
- Removed `AW`/`DW`/`Width`/`AddrWidth`/`DataWidth`/`SelWidth` parameters from all converted modules (fixed at 32-bit by struct definition)
- `ibex_soc_top` massively simplified: ~45 lines of signal declarations and assign statements replaced with 4 struct array declarations and direct connections

**Layer 1 (leaf slaves/bridges):**
- `hw/ip/mem/tcm/rtl/wb_tcm.sv` — Slave: struct ports, removed `Width` parameter, struct output assignment
- `hw/ip/timer/rtl/wb_timer.sv` — Slave: struct ports, removed `AW`/`DW` parameters
- `hw/ip/sim/sim_ctrl/rtl/wb_sim_ctrl.sv` — Slave: both VERILATOR and synthesis stubs converted, removed `AW`/`DW`
- `hw/ip/csr/rtl/wb2simple.sv` — Adapter: struct WB ports, simple bus side unchanged, removed `AW`/`DW`
- `hw/ip/usb/uart/rtl/usb_uart.sv` — Slave: struct ports, removed `AW`/`DW`, passes struct to `wb2simple`
- `hw/ip/cpu/ibex/rtl/ibex_obi2wb.sv` — Master bridge: struct WB ports, removed `AW`/`DW`
- `hw/ip/cpu/ibex/rtl/ibex_wb_top.sv` — Dual master wrapper: struct ports, removed `AW`/`DW`

**Layer 2 (crossbar):**
- `hw/ip/bus/wb_crossbar/rtl/wb_crossbar.sv` — Struct array ports with unpack/repack generate loops, removed `AddrWidth`/`DataWidth`
- `hw/ip/bus/wb_crossbar/rtl/wb_crossbar_decoder.sv` — Removed `AddrWidth`/`DataWidth`/`SelWidth`, hardcoded to 32-bit
- `hw/ip/bus/wb_crossbar/rtl/wb_crossbar_arbiter.sv` — Removed `AddrWidth`/`DataWidth`/`SelWidth`, hardcoded to 32-bit

**Layer 3 (integration):**
- `hw/ip/soc/ibex_soc/rtl/ibex_soc_top.sv` — Direct struct array connections between CPU, crossbar, and slaves
- `hw/projects/squirrel/ibex_soc/rtl/usb_subsystem.sv` — Pass struct directly to `usb_uart` (no manual unpack)

**FuseSoC core files — added `mono:ip:wb_pkg` dependency:**
- `hw/ip/bus/wb_crossbar/wb_crossbar.core`
- `hw/ip/mem/tcm/tcm.core`
- `hw/ip/timer/timer.core`
- `hw/ip/sim/sim_ctrl/sim_ctrl.core`
- `hw/ip/csr/csr.core`
- `hw/ip/cpu/ibex/ibex.core`

**Lint waivers:**
- `hw/ip/soc/ibex_soc/lint/verilator.vlt` — Updated signal name matches from `wb_adr_i`/`wb_sel_i`/`wb_dat_i` to `wb_m2s_i`

**Lint status:** PASS (`mono:ip:wb_crossbar`, `mono:ip:ibex_soc`, `mono:ip:usb_uart`, `mono:projects:squirrel_ibex_soc`)

### 2026-01-29: GPIO Peripheral Implementation

**Work completed:**
- Created standalone GPIO peripheral at `hw/ip/gpio/` with PeakRDL-generated CSR block
- Standard CSR registers: GPIO_OUT (external), GPIO_OE, GPIO_IN (external), GPIO_IE, IRQ_STATUS (W1C), IRQ_ENABLE, IRQ_EDGE, IRQ_TYPE
- Per-bit atomic operations via address-decoded write regions: SET (0x100), CLEAR (0x180), TOGGLE (0x200)
- GPIO_OUT storage lives in `gpio_bit_ctrl.sv` (external to PeakRDL) for unified direct/per-bit access
- 2-stage input synchronizer with configurable input enable masking
- Per-pin interrupt support: edge (rising/falling) or level (active-high/active-low), sticky W1C status, enable mask
- Parameterized `NumGpio` (default 32)
- Uses struct-based Wishbone interface (`wb_m2s_t`/`wb_s2m_t` from `wb_pkg`)
- Fixed `csr.core` to declare `wb_pkg` dependency (was missing since `wb2simple` was updated to use struct ports)

**Files created:**
- `hw/ip/gpio/rdl/gpio_csr.rdl` — SystemRDL register definitions
- `hw/ip/gpio/rdl/Makefile` — PeakRDL-sv generation
- `hw/ip/gpio/rtl/gpio_csr_reg_pkg.sv` — Generated CSR package
- `hw/ip/gpio/rtl/gpio_csr_reg_top.sv` — Generated CSR block
- `hw/ip/gpio/rtl/gpio_bit_ctrl.sv` — Per-bit SET/CLR/TOGGLE decoder and output register
- `hw/ip/gpio/rtl/gpio.sv` — Top-level GPIO peripheral
- `hw/ip/gpio/gpio.core` — FuseSoC core file
- `hw/ip/gpio/lint/verilator.vlt` — Lint waivers for generated CSR code
- `hw/ip/gpio/dv/gpio_tb.sv` — Testbench (19 checks)

**Files modified:**
- `hw/ip/csr/csr.core` — Added `mono:ip:wb_pkg` dependency (required by `wb2simple.sv`)
- `docs/plans/ibex_soc_tasks.md` — Added task status, infrastructure entry, work log

**Issues found and resolved:**
1. **Address routing bug**: `is_perbit_region = reg_addr[8]` missed TOGGLE bank (0x200+) since bit 8 is 0 for those addresses. Fixed to `|reg_addr[9:8]`.
2. **Verilator UNSIGNED warning**: `gpio_idx < NumGpio[4:0]` is constant-true when NumGpio=32. Added compile-time check.
3. **Verilator UNUSEDSIGNAL**: Narrowed `perbit_addr_i` port to `[9:2]` instead of full bus width.

**Lint status:** PASS (`mono:ip:gpio`)
**Sim status:** PASS (19/19 tests — direct OUT, SET/CLR/TOGGLE, input sync, OE, edge/level IRQ, W1C)

---

### 2026-01-30: CDC FIFOs and Cocotb Testbench for core.sv

**Work completed:**
- Added CDC async FIFOs (`prim_fifo_async`) between FT601 PHY (usb_clk) and USB subsystem (sys_clk) in `core.sv`
- RX path: FT601 → prim_fifo_async (usb_clk→sys_clk) → USB subsystem
- TX path: USB subsystem → prim_fifo_async (sys_clk→usb_clk) → FT601
- Both FIFOs: Width=32, Depth=4, separate reset per clock domain
- Created Cocotb testbench for end-to-end USB-to-CPU path testing via FT601 PHY
- SV wrapper (`core_tb.sv`) handles tristate bus emulation for FT601 bidirectional data/BE
- Python tests use existing `FT601Driver` BFM from `mono.cocotb.ft601`
- Three test cases: boot heartbeat, USB RX path, USB TX path

**Files created:**
- `hw/projects/squirrel/ibex_soc/dv/tb/core_tb.sv` — SV wrapper with tristate bus emulation
- `hw/projects/squirrel/ibex_soc/dv/test_core.py` — Cocotb test module with CoreTestbench class
- `hw/projects/squirrel/ibex_soc/dv/Makefile` — Standalone Cocotb/Verilator Makefile

**Files modified:**
- `hw/projects/squirrel/ibex_soc/rtl/core.sv` — Added two `prim_fifo_async` CDC FIFOs, removed CDC TODO comments
- `hw/projects/squirrel/ibex_soc/project.core` — Added `lowrisc:prim:fifo` dependency
- `hw/projects/squirrel/ibex_soc/lint/verilator.vlt` — Added waivers for CDC FIFO unconnected diagnostic outputs
