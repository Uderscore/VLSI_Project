# Quick Start Guide - Accelerator Integration

## What Was Created

### 1. Integration Module
**File**: `rtl/accelerator_integration.v`
- Connects Memory Controller + Systolic Array
- Manages data flow between components
- Implements FSM for operation modes
- Handles format conversions (32-bit ↔ 8-bit)

### 2. Comprehensive Testbench
**File**: `rtl/tb/tb_accelerator_integration.v`
- Tests basic data flow
- Validates handshake protocols
- Verifies back-pressure handling
- Includes self-checking test cases

### 3. Simulation Script
**File**: `sim/run_integration.do`
- Automated compilation and simulation
- Pre-configured waveform viewer
- Detailed signal monitoring

### 4. Documentation
**File**: `rtl/INTEGRATION_README.md`
- Complete architecture description
- Usage examples
- Debugging guide
- Performance metrics

## Running the Simulation

### Method 1: Using the DO Script
```bash
cd sim
vsim -do run_integration.do
```

### Method 2: GUI Mode
```bash
cd sim
vsim -gui
# In ModelSim console:
do run_integration.do
```

### Method 3: Manual Compilation
```bash
cd sim
vlib work
vlog +define+SIMULATION ../rtl/core/processing_element.v
vlog +define+SIMULATION ../rtl/core/systolic_array.v
vlog +define+SIMULATION ../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v
vlog +define+SIMULATION ../rtl/mem/memory_controller.v
vlog +define+SIMULATION ../rtl/accelerator_integration.v
vlog +define+SIMULATION ../rtl/tb/tb_accelerator_integration.v
vsim work.tb_accelerator_integration
run -all
```

## Expected Output

```
================================================================================
        ACCELERATOR INTEGRATION TESTBENCH
================================================================================
Testing integration of Memory Controller + Systolic Array
================================================================================

========================================
TEST 1: Basic Data Flow
========================================
Time 0: Applying reset...
Time 70: Reset complete
Time 70: Loading test data into arrays...
Time 70: Test data loaded
Time 70: TEST - Loading input data to memory
  Loaded word 1: 0x03020100
  Loaded word 2: 0x07060504
  ...
Time XXX: Input data loading complete (16 words)
Time XXX: TEST - Loading weights to systolic array
  Loaded weight row 0: 0x01
  Loaded weight row 1: 0x00
  ...
Time XXX: Weight loading complete
Time XXX: TEST - Starting computation
Time XXX: Systolic array computing...
Time XXX: Computation complete
Time XXX: TEST - Collecting results
  Result[0] = 0xXXXXXXXX
  ...
Time XXX: Collected XX results
Time XXX: *** TEST PASSED ***

========================================
TEST 2: Memory Handshake Protocol
========================================
Testing write handshake...
  Handshake 0: SUCCESS
  Handshake 1: SUCCESS
  ...

========================================
TEST 3: Back-pressure Handling
========================================
  Received result during back-pressure test: 0xXXXXXXXX
  ...
SUCCESS: Back-pressure handled correctly

================================================================================
                           SIMULATION SUMMARY
================================================================================
Total Tests Run: 3
Total Errors:    0

*** ALL TESTS PASSED ***

================================================================================
```

## Key Signals to Monitor

### Top-Level Control
- `clk`, `rst_n` - Clock and reset
- `start` - Operation trigger
- `mode_load`, `mode_weight`, `mode_compute` - Operation modes
- `busy`, `done` - Status indicators

### Data Interfaces
- `ext_data_valid`, `ext_data_ready` - Input handshake
- `ext_data_in[31:0]` - Input data
- `ext_result_valid`, `ext_result_ready` - Output handshake
- `ext_result_out[31:0]` - Output results

### Internal State
- `dut/state` - FSM state (0=IDLE, 1=LOAD_INPUT, 2=LOAD_WEIGHT, 3=COMPUTE, 4=DRAIN, 5=DONE)
- `dut/write_addr_counter` - Write address progress
- `dut/read_addr_counter` - Read address progress

### Memory Controller
- `dut/mem_ctrl/ping_active` - Active read buffer
- `dut/mem_ctrl/ping_write_active` - Active write buffer
- `dut/mem_ctrl/agu_wr_valid`, `agu_wr_ready` - Write handshake
- `dut/mem_ctrl/sa_rd_data_valid`, `sa_rd_data_ready` - Read handshake

### Systolic Array
- `dut/sa/enable` - Processing enabled
- `dut/sa/load_weight` - Weight loading mode
- `dut/sa/data_valid`, `data_ready` - Input handshake
- `dut/sa/result_valid`, `result_ready` - Output handshake

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                 accelerator_integration                      │
│                                                              │
│  ┌────────────────┐         ┌──────────────────┐           │
│  │                │         │                  │           │
│  │   Memory       │◄───────►│   Systolic       │           │
│  │   Controller   │         │   Array          │           │
│  │   (Ping-Pong)  │         │   (8×8 PEs)      │           │
│  │                │         │                  │           │
│  └────────┬───────┘         └────────┬─────────┘           │
│           │                          │                      │
│           │                          │                      │
│  ┌────────▼──────────────────────────▼─────────┐           │
│  │         FSM Control & Data Conversion        │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
└──────────┬───────────────────────────────┬──────────────────┘
           │                               │
    ext_data_in                     ext_result_out
    (32-bit input)                  (32-bit output)
```

## Troubleshooting

### Simulation doesn't start
- Check that all file paths are correct
- Verify SRAM macro exists at `third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v`
- Ensure work library is created

### No results output
- Verify `ext_result_ready = 1` in testbench
- Check that computation completes (`done` signal)
- Look for `sa_computing` signal activity

### Compilation errors
- Ensure all dependent modules are compiled first
- Check for syntax errors in integration module
- Verify +define+SIMULATION is set for debug output

### Waveform viewer issues
- Use `wave zoom full` to see entire simulation
- Check signal hierarchy matches actual design
- Reload waveform if signals don't appear

## Next Steps

1. **Add AGU Integration**: Connect the address generator for automatic tiling
2. **Expand Test Cases**: Add tests for different image and kernel sizes
3. **Golden Model**: Create Python reference for result validation
4. **Performance Testing**: Measure throughput and latency
5. **Full System Integration**: Connect all components including control unit

## File Locations

```
VLSI_Project/
├── rtl/
│   ├── accelerator_integration.v          ← NEW: Top integration
│   ├── INTEGRATION_README.md              ← NEW: Detailed docs
│   ├── core/
│   │   ├── systolic_array.v               ← Existing
│   │   └── processing_element.v           ← Existing
│   ├── mem/
│   │   └── memory_controller.v            ← Existing
│   └── tb/
│       └── tb_accelerator_integration.v   ← NEW: Testbench
├── sim/
│   └── run_integration.do                 ← NEW: Sim script
├── third_party/
│   └── sram_macros/
│       └── sky130_sram_1kbyte_1rw1r_32x256_8.v
└── QUICK_START.md                         ← NEW: This file
```

## Support

For detailed architecture and usage information, see:
- `rtl/INTEGRATION_README.md` - Complete technical documentation
- `rtl/mem/README.md` - Memory controller details
- `rtl/core/README.md` - Systolic array details
- `project_doc.pdf` - Project specifications
