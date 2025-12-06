# Stage 4: System Verification Tools

This directory contains the Python scripts and automation tools for verifying the hardware implementation against a golden reference model.

## Overview

The verification flow consists of three main components:

1. **Golden Model** (`golden_model.py`) - Generates test vectors and computes expected outputs
2. **Result Verifier** (`verify_results.py`) - Compares hardware results against expected outputs
3. **Automation Script** (`../sim/run_verification.sh`) - Orchestrates the complete verification workflow

## Quick Start

### Generate Test Vectors

Generate the full test suite (recommended):
```bash
python3 golden_model.py --suite
```

Generate a single test case:
```bash
python3 golden_model.py 32 3        # 32×32 input, 3×3 kernel
python3 golden_model.py 64 8 42     # With specific random seed
```

### Verify Results

After running hardware simulation:
```bash
python3 verify_results.py --suite
python3 verify_results.py --suite 2  # With tolerance ±2
```

Verify a single test:
```bash
python3 verify_results.py sim/data/expected/expected_out.txt sim/data/results/results_hw.txt
```

### Automated Workflow

Run the complete flow (when hardware is ready):
```bash
cd ../../scripts/sim
./run_verification.sh                    # Full test suite
./run_verification.sh --single 32 3      # Single test case
./run_verification.sh --verify-only      # Only verify existing results
```

## File Structure

```
sim/data/
├── inputs/
│   ├── input_matrix.txt    # Input test data (N×N)
│   └── kernel.txt          # Kernel weights (K×K)
├── expected/
│   └── expected_out.txt    # Golden model output
└── results/
    └── results_hw.txt      # Hardware simulation output (to be generated)
```

For test suites:
```
sim/data/
├── test_1_N16_K2/
│   ├── inputs/
│   ├── expected/
│   └── results/
├── test_2_N32_K3/
│   └── ...
└── ...
```

## Golden Model Details

### Features
- Configurable matrix sizes: N ∈ [16, 64], K ∈ [2, 16]
- 8-bit unsigned integer arithmetic
- 32-bit internal accumulation
- Output truncation to 8-bit with saturation
- Reproducible test generation (seeded random)

### Test Cases
The default test suite includes:
1. **Minimum dimensions**: 16×16 input, 2×2 kernel
2. **Small with medium kernel**: 16×16 input, 8×8 kernel
3. **Typical CNN layer**: 32×32 input, 3×3 kernel
4. **Medium dimensions**: 32×32 input, 5×5 kernel
5. **Large with small kernel**: 64×64 input, 3×3 kernel
6. **Large with medium kernel**: 64×64 input, 8×8 kernel
7. **Maximum dimensions**: 64×64 input, 16×16 kernel

### Output Format
All matrices are saved as space-separated ASCII text files with decimal integers:
```
  12  45  78 ...
  34  67  89 ...
  ...
```

## Verification Details

### Comparison Method
- Element-wise absolute difference: |expected - actual|
- Configurable tolerance (default: ±1) to account for fixed-point rounding
- Reports all mismatches with position and values

### Pass Criteria
- Shape must match exactly
- All elements must be within tolerance
- 100% match required (no partial pass)

### Example Output
```
══════════════════════════════════════════════════════════════════════
VERIFICATION RESULT: test_3_N32_K3
══════════════════════════════════════════════════════════════════════
Status:          ✅ PASSED
Total Elements:  900
Mismatches:      0 (0.00%)
Max Error:       0 (tolerance: ±1)
══════════════════════════════════════════════════════════════════════
```

## Integration with Hardware

Once your hardware testbench is ready:

1. **Load test vectors** from `sim/data/inputs/`
2. **Configure accelerator** with N and K from `test_config.txt`
3. **Run simulation** and capture outputs
4. **Save results** to `sim/data/results/results_hw.txt`
5. **Run verification** to compare against expected output

### Expected Testbench Structure
```verilog
// Pseudo-code for testbench integration
initial begin
    // Read configuration
    read_file("sim/data/test_config.txt", N, K);
    
    // Load test vectors
    read_matrix("sim/data/inputs/input_matrix.txt", input_data);
    read_matrix("sim/data/inputs/kernel.txt", kernel_data);
    
    // Run accelerator
    configure_accelerator(N, K);
    stream_input_data(input_data);
    wait_for_done();
    
    // Capture results
    capture_output(output_data);
    write_matrix("sim/data/results/results_hw.txt", output_data);
    
    $finish;
end
```

## Dependencies

- Python 3.6 or higher
- NumPy library

Install dependencies:
```bash
pip3 install numpy
```

## Troubleshooting

### "No test cases found"
- Run the golden model first: `python3 golden_model.py --suite`
- Check that files exist in `sim/data/expected/`

### "File not found" errors
- Ensure you're running from the correct directory
- Check that relative paths match the project structure

### Verification failures
- Review mismatch positions and values in the output
- Check fixed-point arithmetic implementation
- Verify truncation/saturation logic
- Ensure proper data alignment in streaming

### Tolerance too strict
- Increase tolerance if minor rounding differences are acceptable:
  ```bash
  python3 verify_results.py --suite 2  # ±2 tolerance
  ```

## Command Reference

### Golden Model
```bash
python3 golden_model.py <N> <K> [seed]    # Single test
python3 golden_model.py --suite           # Full test suite
```

### Verification
```bash
python3 verify_results.py <expected> <actual> [tolerance]  # Single file
python3 verify_results.py --suite [tolerance]              # All tests
```

### Automation
```bash
./run_verification.sh [--suite|--single N K] [--sim] [--verify-only] [--tolerance N]
```

## Next Steps

1. ✅ **Golden model implemented** - Test vector generation working
2. ✅ **Verification script ready** - Comparison logic complete
3. ⏳ **Hardware testbench** - Stage 3 (to be implemented)
4. ⏳ **Integration** - Connect hardware simulation with verification flow

Once the hardware testbench is complete (Stage 3), the verification flow will be fully automated!

## Support

For questions or issues with the verification tools, refer to the main project documentation or consult the VLSI Project specification document.

---
**Stage 4 Status**: Golden Model & Verification Tools Complete ✅
