# Address Generation Unit (AGU) Explanation

## Overview

The AGU (`address_generator.v`) generates memory addresses to feed data to the systolic array for convolution operations. It maps 2D image coordinates to 1D linear SRAM addresses and produces the sliding window patterns required for convolution.

## Key Concepts

### 2D to 1D Address Mapping
```
addr = y × image_width + x
```
For a 16×16 image, pixel (3, 5) maps to address: 3 × 16 + 5 = 53

### Tile-Based Processing
Large images (up to 64×64) are divided into 8×8 output tiles:
- **Tile Stride**: 8 pixels (output size)
- **Halo Overlap**: For 3×3 kernel, each tile reads 10×10 input pixels to produce 8×8 outputs

```
Tile 0: reads x=[0:9], produces output [0:7]
Tile 1: reads x=[8:17], produces output [8:15]
         ^ 2 pixel overlap (halo)
```

### Input Tile Size Formula
```
input_tile_size = ARRAY_SIZE + (K - 1)
```
| Kernel (K) | Input Tile Size |
|------------|-----------------|
| 3×3        | 10×10           |
| 5×5        | 12×12           |
| 7×7        | 14×14           |

---

## Operation Modes

### MODE_LOAD_INPUT (2'b01)
Generates sequential addresses to load an input tile into SRAM.
- Addresses: Row-major order within tile
- Count: `input_tile_size²` addresses per tile

### MODE_STREAM (2'b10)
Generates sliding window addresses to feed the systolic array.
- For each output position: generates K² addresses (receptive field)
- Total: `ARRAY_SIZE² × K²` addresses per tile
- Order: For each (out_row, out_col), iterate through (kernel_row, kernel_col)

### MODE_UNLOAD (2'b11)
Generates addresses to read results from SRAM.
- Addresses: Row-major order for output tile
- Count: `ARRAY_SIZE²` (64) addresses per tile

---

## State Machine

```
IDLE → CONFIG → IDLE → LOAD/STREAM/UNLOAD → TILE_DONE → IDLE → ... → FRAME_DONE
```

| State | Description |
|-------|-------------|
| IDLE | Waiting for start signal |
| CONFIG | Latch N, K configuration |
| LOAD | Generating load addresses |
| STREAM | Generating sliding window addresses |
| UNLOAD | Generating output addresses |
| TILE_DONE | Current tile complete |
| FRAME_DONE | All tiles processed |

---

## Interface Signals

### Inputs
| Signal | Width | Description |
|--------|-------|-------------|
| `cfg_N` | 7 | Image dimension (8-64) |
| `cfg_K` | 3 | Kernel size (3, 5, or 7) |
| `cfg_valid` | 1 | Latch configuration |
| `start` | 1 | Begin address generation |
| `mode` | 2 | Operation mode |
| `next_addr` | 1 | Request next address |
| `tile_x/y` | 3 | Current tile coordinates |
| `next_tile` | 1 | Advance to next tile |

### Outputs
| Signal | Width | Description |
|--------|-------|-------------|
| `addr_out` | 8 | Generated address |
| `addr_valid` | 1 | Address is valid |
| `row_idx` | 3 | Row within tile |
| `col_idx` | 3 | Column within tile |
| `busy` | 1 | AGU active |
| `tile_done` | 1 | Current tile complete |
| `frame_done` | 1 | All tiles processed |

---

## Integration with Memory Controller

The AGU interfaces with `memory_controller.v` through handshaking:

1. AGU asserts `addr_valid` with `addr_out`
2. Memory controller uses address for read/write
3. After operation, assert `next_addr` to get next address
4. When `tile_done`, control logic asserts `next_tile` to proceed

---

## Usage Example

```verilog
// Configure for 16×16 image with 3×3 kernel
cfg_N = 16; cfg_K = 3; cfg_valid = 1;
@(posedge clk); cfg_valid = 0;

// Load first tile
tile_x = 0; tile_y = 0;
mode = MODE_LOAD_INPUT;
start = 1;
@(posedge clk); start = 0;

// Process addresses
while (!tile_done) begin
    if (addr_valid) begin
        // Use addr_out for memory access
        next_addr = 1;
        @(posedge clk);
        next_addr = 0;
    end
    @(posedge clk);
end
```

---

## Running the Testbench

```bash
cd c:/Users/ASUS/Desktop/SWE_Ass/VLSI_Project/sim
vsim -do run_tb_agu.do
```

The testbench verifies:
1. Configuration latching
2. LOAD mode address sequence (100 addresses for 10×10 tile)
3. STREAM mode sliding window (576 addresses = 64 outputs × 9 kernel)
4. UNLOAD mode (64 addresses)
5. Tile offset for halo overlap
6. Different N/K configurations
