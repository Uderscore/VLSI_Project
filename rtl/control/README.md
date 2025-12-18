# Control Module

## Overview

This directory contains the control logic modules for the systolic array accelerator:

- **Address Generation Unit (AGU)**: Generates memory addresses for tiled convolution
- **Data Loader**: Bridges external DRAM and internal SRAM with proper handshaking
- **Control FSM**: Top-level state machine (to be implemented)

## Modules

### 1. Address Generation Unit (AGU)

**File**: `address_generator.v`  
**Documentation**: `agu_explanation.md`

**Purpose**: Generates memory addresses for:

- Loading input tiles (with halo overlap)
- Streaming sliding windows to systolic array
- Unloading output results

**Key Features**:

- 2D to 1D address mapping
- Tile-based processing (8×8 output tiles)
- Supports kernel sizes: 3×3, 5×5, 7×7
- Image sizes: 8×8 to 64×64

**Interface Highlights**:

```verilog
input  [6:0] cfg_N;           // Image dimension
input  [2:0] cfg_K;           // Kernel size
input        next_addr;       // Request next address
output [7:0] addr_out;        // Generated address
output       addr_valid;      // Address valid
```

### 2. Data Loader

**File**: `data_loader.v`  
**Documentation**:

- `data_loader_fix_explanation.md` (detailed timing fix)
- `data_loader_integration.md` (integration guide)

**Purpose**: Manages data flow between external DRAM and internal SRAM

**Modes**:

- **LOAD**: DRAM → SRAM (input/weights loading)
- **UNLOAD**: SRAM → DRAM (result output with 8-bit truncation)

**Key Features**:

- FSM-based UNLOAD handling for 3-cycle SRAM read latency
- Proper AGU address stepping synchronization
- Back-pressure support on all interfaces
- 32-bit to 8-bit saturation logic

**Recent Fix** (Dec 2024):
Implemented 4-state FSM in UNLOAD mode to ensure AGU address advancement only occurs after successful data handshake with external interface. This fixes the critical timing alignment issue noted in the original code.

### 3. Control FSM (TBD)

**File**: `control_fsm.v` (to be implemented)  
**Purpose**: Top-level orchestration of:

- Tile iteration
- Mode switching (LOAD → STREAM → UNLOAD)
- System-level handshaking

## Testing

### AGU Testbench

```bash
cd sim
vsim -do run_tb_agu.do
```

Tests: Configuration, address generation patterns, tile management

### Data Loader Testbench

```bash
cd sim
vsim -do run_tb_data_loader.do
```

Tests:

- LOAD mode handshaking
- UNLOAD mode with 3-cycle latency
- Back-pressure scenarios
- Data truncation/saturation

## Integration

### Typical Connection Flow

```
External DRAM
    ↕
Data Loader ←→ AGU
    ↕              ↓
Memory Controller  Control FSM
    ↕
SRAM (Ping-Pong Buffers)
    ↕
Systolic Array
```

### Handshaking Protocol

All interfaces use **valid/ready** handshaking:

- **Producer** asserts `valid` when data available
- **Consumer** asserts `ready` when ready to accept
- **Transaction** occurs when both high on same cycle

## Design Notes

### AGU Address Stepping

The AGU uses an internal `addr_consumed` flag to manage handshaking:

1. Assert `addr_valid` when address ready
2. When `next_addr` received, invalidate address and update counters
3. Re-validate address on next cycle

### Data Loader FSM

UNLOAD mode uses 4-state FSM:

```
IDLE → REQUEST → WAIT_DATA → OUTPUT → IDLE
  ↑                                      ↓
  └─────── (when tx_ready) ──────────────┘
         (assert agu_next_addr)
```

This ensures:

- Address stability during SRAM read
- Data latching for back-pressure handling
- Synchronization with AGU stepping

### Timing Considerations

- **Clock frequency**: Target 100 MHz
- **SRAM read latency**: 3 cycles (from Memory Controller)
- **Critical paths**:
  - LOAD: rx_data → agu_wr_data (combinational)
  - UNLOAD: FSM transitions (registered)

## Files

| File                             | Description          | Status               |
| -------------------------------- | -------------------- | -------------------- |
| `address_generator.v`            | AGU implementation   | ✅ Complete          |
| `agu_explanation.md`             | AGU documentation    | ✅ Complete          |
| `data_loader.v`                  | Data loader with FSM | ✅ Fixed & Tested    |
| `data_loader_fix_explanation.md` | Timing fix details   | ✅ Complete          |
| `data_loader_integration.md`     | Integration guide    | ✅ Complete          |
| `control_fsm.v`                  | Top-level FSM        | ⚠️ To be implemented |

## Next Steps

1. **Control FSM Implementation**:

   - Define states for full convolution pipeline
   - Coordinate AGU, Data Loader, and Systolic Array
   - Handle tile iteration and buffer management

2. **Integration Testing**:

   - Combined AGU + Data Loader + Memory Controller test
   - End-to-end data flow verification

3. **Performance Optimization**:
   - Pipeline optimization for higher throughput
   - Power gating for unused states

## References

- Memory Controller: `rtl/mem/memory_controller.v`
- Systolic Array: `rtl/core/systolic_array.v`
- SRAM Spec: `third_party/sram_macros/`
