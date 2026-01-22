# Ibex Debug Options

Future reference for adding debug capability to the Ibex SoC.

## Background

The Squirrel/CaptainDMA board has no dedicated JTAG pins exposed. Debug access must come through USB via the FT601 interface.

## Option A: Debug Module via Wishbone/Etherbone

Connect the PULP debug module's slave interface to the Wishbone crossbar, enabling debug access over USB.

### Architecture

```
Host PC                         FPGA
┌──────────┐                   ┌─────────────────────────────────┐
│ OpenOCD  │◄── USB/Etherbone ─┼──► Wishbone ──► dm_top ──► Ibex │
└──────────┘                   └─────────────────────────────────┘
```

### Implementation

1. Add dm_top slave interface to crossbar as another slave
2. Assign debug module address region (e.g., `0x1000_2000`)
3. Remove JTAG/DMI interface from dm_top (or leave unconnected)
4. Write OpenOCD configuration for remote bitbang over Etherbone

### Memory Map Addition

| Region | Base | Size |
|--------|------|------|
| Debug Module | `0x1000_2000` | 4KB |

### Pros
- Full debug capability (halt, step, breakpoints, register access)
- No physical pins required
- Standard OpenOCD/GDB workflow
- Can inspect CPU state when firmware crashes

### Cons
- Adds ~2-3KB logic
- Debug module is complex IP with dependencies
- Need custom OpenOCD transport layer

### Dependencies
- pulp-platform/riscv-dbg (dm_top)

---

## Option B: Minimal Debug via Mailbox

Use the existing mailbox for basic debug communication.

### Architecture

```
Host PC                         FPGA
┌──────────┐                   ┌─────────────────────────────────┐
│ Python   │◄── USB/Etherbone ─┼──► Mailbox ◄──► Firmware debug  │
│ script   │                   │              stub               │
└──────────┘                   └─────────────────────────────────┘
```

### Implementation

1. Firmware includes a debug stub that polls mailbox
2. Host sends commands (read mem, write mem, dump regs)
3. Firmware executes and responds via mailbox

### Pros
- No additional RTL
- Simple host-side tooling
- Works with existing infrastructure

### Cons
- Requires cooperative firmware (won't help with crashes/hangs)
- No hardware breakpoints
- Slower than real debug interface
- Must be compiled into every firmware image

---

## Option C: USB-JTAG Bridge

Implement JTAG-over-USB using a dedicated USB channel.

### Architecture

```
Host PC                         FPGA
┌──────────┐                   ┌─────────────────────────────────────┐
│ OpenOCD  │◄── USB channel ──►│ JTAG-USB ──► DMI ──► dm_top ──► Ibex│
│ (remote  │                   │ bridge                              │
│ bitbang) │                   └─────────────────────────────────────┘
└──────────┘
```

### Implementation

1. Allocate USB channel for JTAG traffic
2. Create RTL bridge: USB packets ↔ JTAG bit-banging ↔ DMI
3. Use OpenOCD remote_bitbang driver

### Pros
- Standard JTAG/DMI path (well-tested)
- OpenOCD works with minimal config

### Cons
- Additional RTL for USB-JTAG bridge
- Slower than native JTAG (USB latency)
- Still need debug module dependencies

---

## Recommendation

**For initial bringup:** Stub out debug completely. The Ibex core is well-proven RTL and can be simulated. Use printf-style debugging via mailbox or LED.

**For development convenience:** Option A (Debug via Wishbone) provides the best trade-off. It reuses existing Etherbone infrastructure and enables proper GDB debugging without additional USB protocol complexity.

**Implementation order:**
1. Get SoC running without debug
2. Add Option B (mailbox debug stub) in firmware for basic visibility
3. Add Option A (dm_top via Wishbone) when real debugging is needed
