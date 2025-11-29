#!/bin/bash

echo "===================================="
echo "Running PE Testbench"
echo "===================================="

# Create results directory if it doesn't exist
mkdir -p results

# Compile
iverilog -o pe_test \
    ../../rtl/core/processing_element.v \
    ../../rtl/tb/tb_processing_element.v

# Run
vvp pe_test > results/pe_test.log

# Check results
if grep -q "FAIL" results/pe_test.log; then
    echo "❌ Tests FAILED"
    cat results/pe_test.log  # Show the errors
    exit 1
else
    echo "✅ All tests PASSED"
fi

# Move waveform
mv pe_test.vcd results/ 2>/dev/null || true

echo "Results saved to sim/results/"