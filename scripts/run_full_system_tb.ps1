# Run Full System Testbench
# ===========================
# This script compiles and runs the comprehensive full system testbench

# Create simulation output directory
New-Item -ItemType Directory -Force -Path "sim/out" | Out-Null

# Define source files
$sources = @(
    "rtl/core/processing_element.v",
    "rtl/core/systolic_array.v",
    "rtl/mem/memory_controller.v",
    "rtl/control/address_generator.v",
    "rtl/control/control_unit.v",
    "rtl/control/data_loader.v",
    "rtl/convolution_accelerator_top.v",
    "third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v",
    "rtl/tb/tb_full_system.v"
)

Write-Host "=============================================="
Write-Host "Full System Testbench - Compilation & Run"
Write-Host "=============================================="

# Check for Icarus Verilog
$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
if ($iverilog) {
    Write-Host "Using Icarus Verilog..."
    $sourceList = $sources -join " "
    iverilog -o sim/out/tb_full_system.vvp -I rtl/include $sources
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Compilation successful. Running simulation..."
        vvp sim/out/tb_full_system.vvp
    } else {
        Write-Host "Compilation failed!"
    }
}
# Check for ModelSim
elseif (Get-Command vlog -ErrorAction SilentlyContinue) {
    Write-Host "Using ModelSim..."
    
    # Create work library
    vlib work 2>$null
    
    # Compile sources
    foreach ($src in $sources) {
        Write-Host "Compiling $src..."
        vlog -work work $src
    }
    
    # Run simulation
    Write-Host "Running simulation..."
    vsim -c -do "run -all; quit" work.tb_full_system
}
else {
    Write-Host "ERROR: No Verilog simulator found!"
    Write-Host "Please install Icarus Verilog or ModelSim."
    Write-Host ""
    Write-Host "To install Icarus Verilog:"
    Write-Host "  winget install icarus.IcarusVerilog"
    Write-Host ""
    Write-Host "Or run manually with ModelSim if installed elsewhere."
    exit 1
}

Write-Host ""
Write-Host "=============================================="
Write-Host "Simulation Complete"
Write-Host "=============================================="
