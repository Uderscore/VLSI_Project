# Stage 1 – Compute Core (Systolic Array) Interface

This document describes the **inputs and outputs of Stage 1** (the compute core / systolic array) and how they will be used by the later stages:

- Stage 2 – Memory Subsystem
- Stage 3 – Control Unit & AGU
- Stage 4 – System Verification
- Stage 5 – Optimization & Physical Design

Stage 1 in this design consists of:

- [processing_element.v](cci:7://file:///c:/Users/ASUS/Desktop/SWE_Ass/VLSI_Project/rtl/core/processing_element.v:0:0-0:0)
- [systolic_array.v](cci:7://file:///c:/Users/ASUS/Desktop/SWE_Ass/VLSI_Project/rtl/core/systolic_array.v:0:0-0:0)
- [tb_systolic_array_stage1.v](cci:7://file:///c:/Users/ASUS/Desktop/SWE_Ass/VLSI_Project/rtl/tb/tb_systolic_array_stage1.v:0:0-0:0) (verification for Stage 1 only)

---

## 1. Stage 1 Modules

### 1.1 `processing_element`

**Role:** Atomic MAC unit in the systolic array (weight-stationary).

**Ports:**

- **Clock / Reset**
  - `input  wire        clk`
  - `input  wire        rst_n`  
    Active-low async reset.

- **Control from Control Unit (Stage 3)**
  - `input  wire        enable`  
    When `1`, PE performs MAC update each cycle.
  - `input  wire        load_weight`  
    When `1`, PE latches `weight_in` into `weight_reg`.
  - `input  wire        clear_acc`  
    When `1`, accumulator and `psum_out` are cleared to zero.

- **Data Inputs**
  - `input  wire [7:0]  pixel_in`  
    Pixel stream from **West neighbor** (or from array input on the West edge).
  - `input  wire [7:0]  weight_in`  
    Weight value used **only during weight loading** (driven via the same bus as `pixel_in` in this design).
  - `input  wire [31:0] psum_in`  
    Partial sum from **North neighbor** (or from array input on the North edge).

- **Data Outputs**
  - `output reg  [7:0]  pixel_out`  
    Forwarded pixel to **East neighbor**.
  - `output reg  [31:0] psum_out`  
    Updated partial sum to **South neighbor**.

**Internal behavior (summary):**

- `weight_reg` (8‑bit) holds the stationary weight.
- `product = pixel_in * weight_reg` (8×8→16 bits).
- `new_psum = psum_in + zero_extend(product)` (→32 bits).
- On `enable=1` and `clear_acc=0`, `psum_out <= new_psum` each cycle.

---

### 1.2 `systolic_array`

**Role:** 2D grid of `processing_element`s. In final config, typically `ROWS=8`, `COLS=8`.

```verilog
module systolic_array #(
    parameter ROWS = 8,
    parameter COLS = 8,
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // Global Control
    input  wire                                enable,
    input  wire                                load_weight,
    input  wire                                clear_acc,

    // Array Inputs
    input  wire [ROWS*DATA_WIDTH-1:0]          pixel_in_bus,
    input  wire [COLS*PSUM_WIDTH-1:0]          psum_in_bus,

    // Array Outputs
    output wire [ROWS*DATA_WIDTH-1:0]          pixel_out_bus,
    output wire [COLS*PSUM_WIDTH-1:0]          psum_out_bus
);

```*
3. Summary
Stage 1 implements the 8×8 weight-stationary systolic array.
It exposes a clean, bus-level interface:
Control: enable, load_weight, clear_acc
Data in: pixel_in_bus (West), psum_in_bus (North)
Data out: pixel_out_bus (East), psum_out_bus (South)
Stage 2 (memory) and Stage 3 (control + AGU) are responsible for:
Supplying correctly ordered pixels and weights.
Managing accumulation windows and tiles.
Moving data between DRAM/SRAM and *_bus signals.
Stage 4 uses these same signals in the verification environment.
Stage 5 optimizes the implementation but does not change these functional interfaces.*_