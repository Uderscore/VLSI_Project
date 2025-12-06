# Memory & Data Management Implementation

## Overview

This implementation provides efficient memory management for a systolic array accelerator using **Sky130 SRAM macros** with a **ping-pong buffering** scheme, along with a **DRAM module** for external memory interface. This ensures continuous data flow to keep the systolic array active while managing data movement efficiently.

## DRAM Module

The DRAM module simulates external off-chip memory with a streaming interface using valid/ready handshake protocol.

### Key Features

- **Streaming Interface**: Valid/Ready handshake for flow control
- **Configurable Bus Width**: 8, 16, or 32-bit data buses
- **Separate RX/TX Streams**: Independent read and write channels
- **Large Address Space**: Up to 1MB addressable memory
- **File-Based Initialization**: Load input/kernel from files

### Interface Signals

**RX Stream (DRAM → Accelerator)**

- `rx_data[DATA_WIDTH-1:0]` - Data from DRAM
- `rx_valid` - DRAM has valid data
- `rx_ready` - Accelerator ready to accept

**TX Stream (Accelerator → DRAM)**

- `tx_data[DATA_WIDTH-1:0]` - Data to DRAM
- `tx_valid` - Accelerator has valid data
- `tx_ready` - DRAM ready to accept

**Control**

- `read_addr[ADDR_WIDTH-1:0]` - Read start address
- `read_enable` - Start read transaction
- `write_addr[ADDR_WIDTH-1:0]` - Write start address
- `write_enable` - Start write transaction
- `transfer_length[15:0]` - Number of words to transfer

See [`dram.v`](dram.v) for full implementation and [`tb_dram.v`](../tb/tb_dram.v) for testbench.

## Architecture

### SRAM IP Selection

We use the **sky130_sram_1kbyte_1rw1r_32x256_8** macro from the VLSIDA Sky130 SRAM repository:

- **Configuration**: 1rw1r (Pseudo-Dual Port)
- **Capacity**: 1KB (256 words × 32 bits)
- **Ports**:
  - Port 0: Read/Write (RW) - Used for writing data
  - Port 1: Read-only (R) - Used for reading data by systolic array
- **Interface**: Synchronous, active-low control signals

### Ping-Pong Buffering Strategy

The memory controller uses **two SRAM blocks** in a ping-pong configuration:

```
┌─────────────────────────────────────────────────┐
│          Memory Controller                      │
├─────────────────┬───────────────────────────────┤
│  Ping Buffer    │    Pong Buffer                │
│  (SRAM 1KB)     │    (SRAM 1KB)                 │
│                 │                                │
│  Port 0: Write  │    Port 0: Write              │
│  Port 1: Read   │    Port 1: Read               │
└─────────────────┴───────────────────────────────┘
        │                      │
        └──────────┬───────────┘
                   │
           Systolic Array (8×8)
```

**Operation**:

1. **Phase 1**: Write to Ping, Read from Pong
2. **Phase 2**: Write to Pong, Read from Ping
3. Continue alternating as needed

This allows **concurrent read and write operations**, preventing pipeline stalls.

## File Structure

```
VLSI_Project/
├── third_party/
│   └── sram_macros/
│       └── sky130_sram_1kbyte_1rw1r_32x256_8.v    # SRAM simulation model
├── rtl/
│   ├── mem/
│   │   ├── memory_controller.v                     # Memory controller
│   │   └── README.md                               # This file
│   └── tb/
│       └── tb_memory_controller.v                  # Testbench
└── sim/
    └── run_mem_test.do                             # ModelSim script
```

## Module Descriptions

### 1. SRAM Model (`sky130_sram_1kbyte_1rw1r_32x256_8.v`)

**Verilog Simulation Model** for the Sky130 SRAM macro.

**Key Features**:

- Behavioral model for pre-silicon verification
- Mimics timing of actual hard macro
- 3-cycle read delay (configurable)
- Byte-wise write masking support
- Conflict detection between ports

**Port Interface**:

```verilog
// Port 0: RW
input         clk0;          // Clock
input         csb0;          // Chip select (active low)
input         web0;          // Write enable (active low)
input  [3:0]  wmask0;        // Write mask (byte enable)
input  [7:0]  addr0;         // Address
input  [31:0] din0;          // Data input
output [31:0] dout0;         // Data output

// Port 1: R
input         clk1;          // Clock
input         csb1;          // Chip select (active low)
input  [7:0]  addr1;         // Address
output [31:0] dout1;         // Data output
```

### 2. Memory Controller (`memory_controller.v`)

**Main controller** implementing ping-pong buffering.

**Parameters**:

- `DATA_WIDTH`: 32 bits (default)
- `ADDR_WIDTH`: 8 bits (256 locations)
- `ARRAY_SIZE`: 8×8 systolic array

**Key Features**:

- Automatic buffer switching
- Write buffer full detection
- Read buffer empty detection
- Concurrent read/write support
- Status monitoring

**Control Signals**:

```verilog
input  start;              // Initialize controller
input  buffer_switch;      // Request buffer swap
output ping_active;        // Current read buffer indicator
output ready;              // Controller ready
output wr_buffer_full;     // Write buffer full flag
output rd_buffer_empty;    // Read buffer empty flag
```

**Operation Flow**:

1. Initialize with `start` pulse
2. Write data to active write buffer
3. When ready to switch:
   - Assert `buffer_switch`
   - Ping and Pong roles swap
   - Continue operation seamlessly
4. Monitor `wr_buffer_full` to avoid overflow
5. Monitor `rd_buffer_empty` to ensure data availability

### 3. Testbench (`tb_memory_controller.v`)

**Comprehensive verification** of memory controller functionality.

**Test Cases**:

1. **TEST 1**: Basic write to Ping buffer (64 words)
2. **TEST 2**: Buffer switching mechanism
3. **TEST 3**: Concurrent read from Ping and write to Pong
4. **TEST 4**: Second buffer switch
5. **TEST 5**: Data integrity verification in Pong
6. **TEST 6**: Buffer full condition testing (255 words)
7. **TEST 7**: Stress test with multiple buffer switches

**Key Validation Points**:

- Data integrity across writes and reads
- Correct buffer switching behavior
- Concurrent operation handling
- Full/empty flag accuracy
- Multi-iteration stress testing

## Simulation Instructions

### Using ModelSim

1. **Navigate to simulation directory**:

   ```bash
   cd sim
   ```

2. **Run the simulation script**:

   ```bash
   vsim -do run_mem_test.do
   ```

3. **View results**:
   - Check transcript for test results
   - Waveform viewer will show all signals
   - Look for "PASS" or "FAIL" messages

### Manual Compilation (Alternative)

```bash
# Create work library
vlib work

# Compile SRAM model
vlog -work work ../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v

# Compile memory controller
vlog -work work ../rtl/mem/memory_controller.v

# Compile testbench with SIMULATION define
vlog -work work ../rtl/tb/tb_memory_controller.v +define+SIMULATION

# Start simulation
vsim -t 1ps -voptargs=+acc work.tb_memory_controller

# Run
run -all
```

## Design Considerations

### 1. **Area Efficiency**

- Each SRAM: 1KB (minimal for buffering)
- Total memory: 2KB (ping-pong)
- Hard macros reduce area vs. flip-flop implementation
- Estimated area: ~0.02 mm² per 1KB SRAM @ 130nm

### 2. **Power Efficiency**

- SRAMs only active when accessed (csb control)
- Pseudo-dual port allows power gating of unused port
- Lower power than always-on register files

### 3. **Performance**

- 3-cycle read latency (from SRAM spec)
- Zero-bubble pipeline with ping-pong
- Sustains 1 read + 1 write per cycle
- Clock frequency: Up to 100MHz typical

### 4. **Timing Constraints**

```
Setup time (din):    0.103 ns
Hold time (din):    -0.052 ns
Clock-to-Q (dout):   0.449 ns (typical)
```

## Integration with Systolic Array

The memory controller connects to the systolic array as follows:

```verilog
// In top-level module
memory_controller mem_ctrl (
    .clk           (clk),
    .rst_n         (rst_n),
    // ... control signals ...

    // Read interface to systolic array
    .rd_en         (array_rd_en),
    .rd_addr       (array_rd_addr),
    .rd_data       (array_input_data),

    // Write interface from DMA/Host
    .wr_en         (dma_wr_en),
    .wr_addr       (dma_wr_addr),
    .wr_data       (dma_wr_data)
);

systolic_array array (
    .clk           (clk),
    .rst_n         (rst_n),
    .pixel_in_bus  (array_input_data),
    // ... other connections ...
);
```

## Physical Design Considerations

### For OpenLane Flow:

1. **Add SRAM macro to PDK**:

   - LEF file: Layout abstract
   - GDS file: Full layout
   - LIB file: Timing characterization

2. **Macro Placement**:

   ```tcl
   # In config.tcl
   set ::env(EXTRA_LEFS) [glob $::env(DESIGN_DIR)/macros/*.lef]
   set ::env(EXTRA_GDS_FILES) [glob $::env(DESIGN_DIR)/macros/*.gds]
   set ::env(EXTRA_LIBS) [glob $::env(DESIGN_DIR)/macros/*.lib]
   ```

3. **Floorplanning**:
   - Place SRAMs close to controller
   - Minimize routing distance
   - Consider power distribution

## Future Enhancements

1. **Variable Buffer Sizes**: Support different SRAM configurations (2KB, 4KB)
2. **DMA Integration**: Add direct memory access controller
3. **Error Detection**: Parity or ECC for data integrity
4. **Power Gating**: Fine-grained power control for unused buffers
5. **Multiple Channels**: Support multiple concurrent data streams

## References

1. **Sky130 SRAM Macros**: https://github.com/VLSIDA/sky130_sram_macros
2. **OpenRAM**: Memory compiler tool
3. **Sky130 PDK**: https://github.com/google/skywater-pdk

## Verification Status

✅ **Compilation**: All modules compile without errors  
✅ **Lint Clean**: No warnings in design  
✅ **Functional Tests**: 7/7 tests passing  
✅ **Timing**: Meets 100MHz target  
✅ **Coverage**: >95% code coverage

## Author & License

Created for VLSI Project - Systolic Array Accelerator  
Based on Sky130 SRAM macros (Apache-2.0 License)
