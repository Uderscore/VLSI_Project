# Systolic Array Handshake Protocol

## Overview

The systolic array now implements a Valid/Ready handshake protocol for proper data flow control with the memory controller. This ensures data is only transferred when both source and destination are ready.

## Handshake Signals

### Input Data Handshake (SRAM → SA)
| Signal | Direction | Description |
|--------|-----------|-------------|
| `data_valid` | Input | Memory has valid input data |
| `data_ready` | Output | SA ready to accept data |

### Weight Loading Handshake
| Signal | Direction | Description |
|--------|-----------|-------------|
| `weight_valid` | Input | Memory has valid weight data |
| `weight_ready` | Output | SA ready to accept weights |

### Output Result Handshake (SA → SRAM)
| Signal | Direction | Description |
|--------|-----------|-------------|
| `result_valid` | Output | SA has valid output results |
| `result_ready` | Input | Memory ready to accept results |

---

## Handshake Protocol

### Transfer Rule
Data transfer occurs on the rising clock edge when **BOTH** valid and ready are HIGH.

```
CLK        ____/----\____/----\____/----\____
valid      ________/--------------------\____
ready      ____/----------------------------\
DATA       XXXXXXXX|  VALID DATA  |XXXXXXXXXX
                   ^ Transfer happens here
```

### Back-Pressure Handling
When `result_ready` is LOW, the SA stalls output. The `data_ready` signal can also deassert to apply back-pressure to the memory controller.

---

## Integration with Memory Controller

Map systolic array signals to memory controller SA interface:

```verilog
// Memory Controller <-> Systolic Array
.sa_rd_data_valid  --> .data_valid      // Input data valid
.sa_rd_data_ready  <-- .data_ready      // Input data ready
.sa_rd_data        --> .pixel_in_bus    // Input data

.sa_wr_valid       <-- .result_valid    // Output results valid
.sa_wr_ready       --> .result_ready    // Output results ready
.sa_wr_data        <-- .psum_out_bus    // Output results
```

---

## Pipeline Timing

- Pipeline depth: `ROWS + COLS - 1 = 15` cycles for 8×8 array
- `result_valid` asserts after pipeline fills
- Results available continuously once pipeline is primed

---

## Usage Example

```verilog
// Weight Loading Phase
load_weight  = 1;
weight_valid = 1;
@(posedge clk);
while (!weight_ready) @(posedge clk);  // Wait for ready
@(posedge clk);  // Handshake complete
weight_valid = 0;
load_weight  = 0;

// Compute Phase
enable       = 1;
data_valid   = 1;
result_ready = 1;

while (computing) begin
    @(posedge clk);
    if (data_valid && data_ready) begin
        // Input data consumed
    end
    if (result_valid && result_ready) begin
        // Output result available
        capture_result(psum_out_bus);
    end
end
```

---

## Running the Testbench

```bash
cd c:/Users/ASUS/Desktop/SWE_Ass/VLSI_Project/sim
vsim -do run_tb_sa_handshake.do
```

### Test Cases
1. Data ready signal assertion
2. Weight loading handshake
3. Data input handshake
4. Result valid after pipeline fill
5. Back-pressure handling
6. Result handshake completion
