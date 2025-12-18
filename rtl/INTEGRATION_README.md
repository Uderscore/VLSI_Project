# Accelerator Integration Documentation

## Overview

This document describes the integration between the Memory Controller and Systolic Array components of the convolution accelerator.

## Architecture

### Integration Module: `accelerator_integration.v`

The integration module connects three main components:

1. **Memory Controller** (`memory_controller.v`)
   - Manages ping-pong buffered SRAM blocks (2x 1KB)
   - Provides dual-port access for concurrent read/write
   - Implements valid/ready handshaking

2. **Systolic Array** (`systolic_array.v`)
   - 8×8 grid of processing elements (PEs)
   - Weight-stationary dataflow
   - Pipelined MAC operations

3. **Data Path Control**
   - FSM-based orchestration
   - Data format conversion (32-bit ↔ 8-bit)
   - Handshake protocol coordination

### Data Flow

```
External Input → Memory Controller → Systolic Array → External Output
     (32-bit)      (Ping-Pong SRAM)    (8×8 PEs)        (32-bit)
```

## Operating Modes

### 1. LOAD_INPUT Mode
- Loads input image data into SRAM
- Data is written to memory via AGU write path
- Format: 32-bit words containing 4×8-bit pixels
- Address: Auto-incremented linear addressing

### 2. LOAD_WEIGHT Mode
- Loads kernel weights into systolic array PEs
- Weights distributed across PE rows
- Format: 8-bit values broadcast to each row
- Loaded via systolic array's weight loading mechanism

### 3. COMPUTE Mode
- Reads data from SRAM
- Feeds data to systolic array for processing
- Systolic array performs convolution MAC operations
- Results accumulate in PE partial sum registers

### 4. DRAIN Mode
- Extracts results from systolic array
- Converts 32-bit partial sums to 8-bit outputs
- Sends results to external interface
- Handshakes with result_ready signal

## Interface Signals

### Configuration Inputs
- `cfg_N [6:0]` - Input image dimension (8 to 64)
- `cfg_K [2:0]` - Kernel size (3, 5, or 7)

### Control Inputs
- `start` - Pulse to begin operation
- `mode_load` - Enable input data loading
- `mode_weight` - Enable weight loading
- `mode_compute` - Enable computation

### Status Outputs
- `busy` - System is processing
- `done` - Operation complete
- `sa_computing` - Systolic array active
- `mem_writing` - Memory write in progress
- `mem_reading` - Memory read in progress

### Data Interface (Input)
- `ext_data_valid` - External data is valid
- `ext_data_ready` - Integration ready for data
- `ext_data_in [31:0]` - Input data word

### Data Interface (Output)
- `ext_result_valid` - Result data is valid
- `ext_result_ready` - External system ready for result
- `ext_result_out [31:0]` - Output result word

## Usage Example

### Step 1: Load Input Data
```verilog
// Configure
cfg_N = 7'd8;      // 8×8 image
cfg_K = 3'd3;      // 3×3 kernel

// Enter load mode
mode_load = 1;
start = 1;
@(posedge clk);
start = 0;

// Send data
for (i = 0; i < 16; i++) begin
    wait(ext_data_ready);
    ext_data_in = input_data[i];
    ext_data_valid = 1;
    @(posedge clk);
    while (!(ext_data_valid && ext_data_ready)) @(posedge clk);
    ext_data_valid = 0;
end
mode_load = 0;
```

### Step 2: Load Weights
```verilog
// Enter weight mode
mode_weight = 1;
start = 1;
@(posedge clk);
start = 0;

// Send weights (one per row)
for (i = 0; i < 8; i++) begin
    wait(ext_data_ready);
    ext_data_in = {24'd0, weight_data[i]};
    ext_data_valid = 1;
    @(posedge clk);
    while (!(ext_data_valid && ext_data_ready)) @(posedge clk);
    ext_data_valid = 0;
end
mode_weight = 0;
```

### Step 3: Execute Computation
```verilog
// Enter compute mode
mode_compute = 1;
start = 1;
@(posedge clk);
start = 0;

// Wait for completion
wait(done);
mode_compute = 0;
```

### Step 4: Collect Results
```verilog
// Ready to receive
ext_result_ready = 1;

// Collect results
while (result_count < expected_results) begin
    @(posedge clk);
    if (ext_result_valid && ext_result_ready) begin
        output_data[result_count] = ext_result_out;
        result_count++;
    end
end
```

## Memory Organization

### SRAM Layout
- **Total Capacity**: 2KB (2× 1KB blocks)
- **Word Size**: 32 bits
- **Depth**: 256 words per block
- **Access Pattern**: Ping-pong buffering

### Address Mapping
- Linear addressing for input/output
- `addr = row * N + col` for 2D to 1D mapping
- Auto-incrementing counters manage addresses

## Timing Considerations

### Pipeline Delays
- **SRAM Read Latency**: 3 cycles
- **Systolic Array Fill**: 15 cycles (ROWS + COLS - 1)
- **Result Propagation**: Pipeline depth dependent

### Handshake Protocol
- Valid/Ready signals must be synchronized
- Data transfer occurs when both signals are HIGH
- Back-pressure supported via ready signal

## Testing

### Testbench: `tb_accelerator_integration.v`

Three main test scenarios:

1. **Basic Data Flow Test**
   - Loads test data
   - Executes computation
   - Verifies results received

2. **Memory Handshake Test**
   - Validates write handshaking
   - Checks ready/valid protocol
   - Ensures data integrity

3. **Back-pressure Test**
   - Random ready signal toggling
   - Verifies no data loss
   - Confirms proper stalling

### Running Simulation

Using ModelSim/QuestaSim:
```bash
cd sim
vsim -do run_integration.do
```

Or using GUI:
```bash
cd sim
vsim -gui
do run_integration.do
```

### Expected Output
```
========================================
TEST 1: Basic Data Flow
========================================
Time 0: Applying reset...
Time 70: Reset complete
Time 70: Loading test data into arrays...
Time 70: Test data loaded
Time 70: TEST - Loading input data to memory
...
*** TEST PASSED ***
```

## Debugging Tips

### Common Issues

1. **No results output**
   - Check that computation mode completes
   - Verify sa_computing goes HIGH
   - Ensure result_ready is asserted

2. **Handshake deadlock**
   - Check valid/ready signal timing
   - Verify FSM state transitions
   - Look for buffer full/empty conditions

3. **Incorrect results**
   - Verify weight loading order
   - Check data format conversions
   - Validate address generation

### Debug Signals

Monitor these signals in waveform viewer:
- `state` - FSM state
- `sa_computing` - Array activity
- `mem_ping_active` - Buffer selection
- `write_addr_counter` - Write progress
- `read_addr_counter` - Read progress

## Performance Metrics

### Throughput
- **Peak**: 8 pixels/cycle (once pipeline filled)
- **Effective**: Depends on memory bandwidth and tiling

### Latency
- **Setup**: ~100 cycles (data + weight loading)
- **Compute**: ~80 cycles for 8×8 tile
- **Total**: ~200 cycles for small convolution

## Future Enhancements

1. **AGU Integration**: Connect address generator for automatic tiling
2. **Result Write-back**: Store results in memory for larger outputs
3. **Multiple Buffers**: Expand beyond ping-pong for deeper pipelining
4. **DMA Support**: Direct memory access for faster data transfer

## File Organization

```
rtl/
├── accelerator_integration.v          # Top-level integration
├── core/
│   ├── systolic_array.v               # 8×8 SA
│   └── processing_element.v           # Single PE
├── mem/
│   └── memory_controller.v            # SRAM controller
└── tb/
    └── tb_accelerator_integration.v   # Integration testbench

sim/
└── run_integration.do                 # Simulation script
```

## References

- Memory Controller: `rtl/mem/README.md`
- Systolic Array: `rtl/core/README.md`
- Project Specification: `project_doc.pdf`
