# core

Description: Stage 1 compute core: single Processing Element (PE) and the parameterized systolic array built from it.

## Files

- `processing_element.v`  – Weight‑stationary PE implementing an 8‑bit × 8‑bit MAC with 32‑bit accumulation.
- `systolic_array.v`      – ROWS × COLS grid of PEs with pixel data flowing West→East and partial sums flowing North→South.

## Stage 1: Compute core goals

- Implement the **compute core only** (no SRAM or control FSM here):
  - A single, reusable PE.
  - A parameterized systolic array (default 8×8) that instantiates the PE grid.
- Support the **Weight Stationary (WS)** dataflow as required by the project:
  - Weights are loaded once into each PE and held in place.
  - Input pixels stream across the array.
  - Partial sums flow vertically and accumulate as data moves.

## Interfaces and dataflow

Both `processing_element` and `systolic_array` share the same high‑level control interface:

- `clk`, `rst_n`          – Global clock and active‑low reset.
- `enable`                – Enables MAC updates when high.
- `load_weight`           – When asserted, each PE latches `weight_in` into its local `weight_reg` (weight‑stationary).
- `clear_acc`             – Clears the accumulated partial sums (used at the start of a new computation phase).

For the array:

- `pixel_in_bus`  – Flattened input pixels, ordered by row: `[Row0, Row1, …, Row(ROWS-1)]`.
- `psum_in_bus`   – Flattened input partial sums, ordered by column: `[Col0, Col1, …, Col(COLS-1)]`.
- `pixel_out_bus` – Pixels emerging on the East edge of the array.
- `psum_out_bus`  – Final partial sums on the South edge of the array (one 32‑bit value per column).

### Weight‑stationary PE behavior

- Each PE has an internal `weight_reg` that is **only updated when `load_weight` is high**.
- During normal compute cycles (`enable = 1`, `load_weight = 0`):
  - The incoming pixel is forwarded to `pixel_out` every cycle (creates a horizontal pipeline).
  - The PE multiplies `pixel_in` by `weight_reg` and accumulates the product into the vertical partial sum path.
  - Partial sums flow from North (`psum_in`) to South (`psum_out`).
- `clear_acc` is used to zero out accumulators between independent computations, without touching the stored weights.

### Array assembly (systolic_array.v)

- The array is constructed using 2D generate loops:
  - Horizontal pixel wires: `pixel_conn[ROWS][COLS+1]` connect West→East through each row of PEs.
  - Vertical psum wires: `psum_conn[ROWS+1][COLS]` connect North→South through each column of PEs.
- Boundary wiring:
  - West edge (`pixel_conn[*,0]`) is driven by `pixel_in_bus` (one 8‑bit lane per row).
  - North edge (`psum_conn[0,*]`) is driven by `psum_in_bus` (one 32‑bit lane per column).
  - East edge (`pixel_conn[*,COLS]`) is exposed as `pixel_out_bus`.
  - South edge (`psum_conn[ROWS,*]`) is exposed as `psum_out_bus`.
- Each PE instance receives its own slice of these horizontal and vertical connections and shares the global control signals.

## Size and optimization decisions

- **Array size (ROWS = COLS = 8)**
  - Matches the project requirement for an 8×8 systolic array.
  - Implemented as parameters so the same RTL can be reused for other sizes if needed.

- **Data and accumulation widths**
  - `DATA_WIDTH = 8` bits (unsigned pixels/weights).
  - `PSUM_WIDTH = 32` bits to safely accommodate the growth from repeated MAC operations without overflow in typical convolution settings.

- **Dataflow choice: Weight Stationary (WS)**
  - Weights are pre‑loaded once per kernel into each PE and reused across all input tiles.
  - This minimizes weight memory traffic and matches the course recommendation for convolution accelerators.

- **Simplicity first (Stage 1)**
  - No clock gating or extra micro‑architectural optimizations are applied yet; focus is on correctness and clean dataflow.
  - Later stages (memory integration, control, and physical design) can add power/area optimizations without changing this core PE/array contract.
