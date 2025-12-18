# Bug Fix Summary - Accelerator Integration

## Problem
Simulation was timing out with continuous "Read buffer empty" warnings at ~200us.

## Root Causes Identified

### 1. Multiple Driver Conflict
**Location**: `accelerator_integration.v` lines 301-302 and 335
- `sa_pixel_in_bus` had two assign statements
- One for memory data conversion (line 301-302)
- One for weight loading (line 335)
- **Impact**: Synthesis error, unpredictable behavior

### 2. Buffer Management Issue
**Location**: Memory controller ping-pong buffer switching
- Data was written to PING buffer during LOAD_INPUT
- System tried to read from PONG buffer during COMPUTE
- PONG buffer was never filled, hence "Read buffer empty"
- **Impact**: No data available for computation

### 3. Missing Buffer Switch Signal
**Location**: FSM state transitions
- No buffer switch triggered after loading data
- `mem_buffer_switch` signal not properly asserted
- **Impact**: Buffers never swapped roles

### 4. Testbench Flow Issues
**Location**: `tb_accelerator_integration.v`
- No timeout protection in data collection loop
- Handshake timing could cause deadlocks
- **Impact**: Simulation hangs without useful error messages

## Fixes Applied

### Fix 1: Resolve Multiple Driver Conflict

**File**: `rtl/accelerator_integration.v`

**Before**:
```verilog
// Line 301-302: Memory data mapping
assign sa_pixel_in_bus[(g+1)*DATA_WIDTH-1 : g*DATA_WIDTH] = 
       sa_rd_data[(g % 4 + 1)*DATA_WIDTH - 1 : (g % 4)*DATA_WIDTH];

// Line 335: Weight loading mapping  
assign sa_pixel_in_bus = {ARRAY_SIZE{ext_data_in[DATA_WIDTH-1:0]}};
```

**After**:
```verilog
// Create intermediate wires
wire [ARRAY_SIZE*DATA_WIDTH-1:0] sa_pixel_from_mem;
wire [ARRAY_SIZE*DATA_WIDTH-1:0] sa_pixel_from_ext;

// Memory data mapping
assign sa_pixel_from_mem[(g+1)*DATA_WIDTH-1 : g*DATA_WIDTH] = 
       sa_rd_data[(g % 4 + 1)*DATA_WIDTH - 1 : (g % 4)*DATA_WIDTH];

// Weight data mapping
assign sa_pixel_from_ext = {ARRAY_SIZE{ext_data_in[DATA_WIDTH-1:0]}};

// MUX based on state
assign sa_pixel_in_bus = (state == LOAD_WEIGHT) ? sa_pixel_from_ext : sa_pixel_from_mem;
```

### Fix 2: Add Buffer Switch Tracking

**File**: `rtl/accelerator_integration.v`

**Added**:
```verilog
reg buffer_switched;   // Track if buffer was switched after load

// In reset:
buffer_switched <= 1'b0;

// In LOAD_INPUT state:
if (write_addr_counter >= 8'd16 && !buffer_switched) begin
    buffer_switched <= 1'b1;
end
if (buffer_switched && write_addr_counter >= 8'd16) begin
    state <= IDLE;
end
```

### Fix 3: Correct Buffer Switch Signal

**File**: `rtl/accelerator_integration.v`

**Before**:
```verilog
assign mem_buffer_switch = (state == COMPUTE) && (read_addr_counter == 8'd63);
```

**After**:
```verilog
assign mem_buffer_switch = (state == LOAD_INPUT) && buffer_switched && (write_addr_counter >= 8'd16);
```

**Explanation**: Buffer must switch AFTER loading completes, not during computation.

### Fix 4: Improve External Ready Signal

**File**: `rtl/accelerator_integration.v`

**Before**:
```verilog
assign ext_data_ready = agu_wr_ready && (state == LOAD_INPUT);
```

**After**:
```verilog
assign ext_data_ready = (state == LOAD_INPUT) ? agu_wr_ready : 
                       (state == LOAD_WEIGHT) ? sa_weight_ready : 1'b0;
```

**Explanation**: Properly route ready signal based on current state.

### Fix 5: Add Testbench Timeout Protection

**File**: `rtl/tb/tb_accelerator_integration.v`

**Changes**:
1. Added timeout counters to all test tasks
2. Improved handshake timing (removed unnecessary waits)
3. Added buffer switch delay (20 cycles) after loading
4. Added status reporting on timeouts

**Example**:
```verilog
// In collect_results task:
integer timeout_counter;
timeout_counter = 0;

while (result_count < 16 && timeout_counter < 1000) begin
    @(posedge clk);
    if (ext_result_valid && ext_result_ready) begin
        // Collect result
        timeout_counter = 0;  // Reset on success
    end else begin
        timeout_counter = timeout_counter + 1;
    end
end

if (timeout_counter >= 1000) begin
    $display("WARNING - Timeout collecting results (got %0d)", result_count);
end
```

## Expected Behavior After Fixes

### Data Flow Sequence

1. **LOAD_INPUT State**:
   - External data → Memory Controller (AGU write path)
   - Data written to PING buffer
   - After 16 words loaded, `buffer_switched` = 1
   - Buffer switch signal asserted
   - State → IDLE

2. **After Buffer Switch**:
   - PING buffer becomes read buffer
   - PONG buffer becomes write buffer
   - Data now available for reading

3. **COMPUTE State**:
   - Memory reads from PING buffer (now readable)
   - Data flows to Systolic Array
   - Computation proceeds normally

4. **DRAIN/DONE States**:
   - Results propagate from SA
   - External interface collects results
   - System returns to IDLE

## Testing

### Run Simulation
```bash
cd sim
vsim -do run_integration.do
```

### Expected Output
```
TEST 1: Basic Data Flow
Time 70: Applying reset...
Time 70: Loading test data...
Time XX: Loading input data to memory
  Loaded word 0: 0x03020100
  ...
  Loaded word 15: 0x3f3e3d3c
Time XX: Input data loading complete (16 words)
Time XX: Loading weights...
  Loaded weight row 0: 0x01
  ...
Time XX: Weight loading complete
Time XX: Starting computation
Time XX: Systolic array computing...
Time XX: Computation complete
Time XX: Collecting results
  Result[0] = 0xXXXXXXXX
  ...
*** TEST PASSED ***
```

### Debug Signals to Monitor

1. **Buffer Status**:
   - `dut/mem_ctrl/ping_active` - Should toggle after load
   - `dut/buffer_switched` - Should go HIGH after 16 words

2. **State Machine**:
   - `dut/state` - Should progress: IDLE→LOAD_INPUT→IDLE→LOAD_WEIGHT→IDLE→COMPUTE→DRAIN→DONE

3. **Data Flow**:
   - `dut/agu_wr_valid` && `agu_wr_ready` - Write transactions
   - `dut/sa_rd_data_valid` && `sa_rd_data_ready` - Read transactions

4. **Address Counters**:
   - `dut/write_addr_counter` - Should count 0→16
   - `dut/read_addr_counter` - Should count during COMPUTE

## Additional Notes

### Memory Controller Timing
- SRAM read latency: 3 cycles
- Must account for read pipeline when checking `sa_rd_data_valid`

### Systolic Array Timing
- Pipeline fill: 15 cycles (ROWS + COLS - 1)
- Results appear after this delay

### Recommended Next Steps
1. Run simulation and verify no "Read buffer empty" warnings
2. Confirm data flows through all stages
3. Add more comprehensive test cases
4. Integrate with AGU for automatic address generation

## Files Modified

1. `rtl/accelerator_integration.v` - Core integration fixes
2. `rtl/tb/tb_accelerator_integration.v` - Testbench improvements
3. `BUGFIX_SUMMARY.md` - This document

## Verification Checklist

- [ ] Simulation runs without timeout
- [ ] No "Read buffer empty" warnings
- [ ] Data loads successfully into memory
- [ ] Weights load into systolic array
- [ ] Computation executes
- [ ] Results are produced and collected
- [ ] All test cases pass
