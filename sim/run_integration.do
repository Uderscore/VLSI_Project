# ModelSim/QuestaSim TCL Script for Accelerator Integration Testbench
# This script compiles and simulates the integrated memory + systolic array system

# Clear previous compilation
if {[file exists work]} {
    vdel -all
}

# Create work library
vlib work
vmap work work

# Set simulation define for debug output
set SIMULATION_DEFINE "+define+SIMULATION"

echo "=========================================="
echo "Compiling RTL Files..."
echo "=========================================="

# Compile Processing Element
vlog -work work ${SIMULATION_DEFINE} ../rtl/core/processing_element.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../rtl/core/processing_element.v}]} {
    echo "ERROR: Failed to compile processing_element.v"
    quit -f
}

# Compile Systolic Array
vlog -work work ${SIMULATION_DEFINE} ../rtl/core/systolic_array.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../rtl/core/systolic_array.v}]} {
    echo "ERROR: Failed to compile systolic_array.v"
    quit -f
}

# Compile SRAM Macro Model
vlog -work work ${SIMULATION_DEFINE} ../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v}]} {
    echo "ERROR: Failed to compile SRAM macro"
    quit -f
}

# Compile Memory Controller
vlog -work work ${SIMULATION_DEFINE} ../rtl/mem/memory_controller.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../rtl/mem/memory_controller.v}]} {
    echo "ERROR: Failed to compile memory_controller.v"
    quit -f
}

# Compile Accelerator Integration Module
vlog -work work ${SIMULATION_DEFINE} ../rtl/accelerator_integration.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../rtl/accelerator_integration.v}]} {
    echo "ERROR: Failed to compile accelerator_integration.v"
    quit -f
}

# Compile Testbench
vlog -work work ${SIMULATION_DEFINE} ../rtl/tb/tb_accelerator_integration.v
if {[catch {vlog -work work ${SIMULATION_DEFINE} ../rtl/tb/tb_accelerator_integration.v}]} {
    echo "ERROR: Failed to compile tb_accelerator_integration.v"
    quit -f
}

echo "=========================================="
echo "Compilation Successful!"
echo "=========================================="

# Start simulation
vsim -voptargs=+acc work.tb_accelerator_integration

# Configure wave window
echo "=========================================="
echo "Configuring Wave Window..."
echo "=========================================="

# Add waves - Top Level
add wave -noupdate -divider "Clock and Reset"
add wave -format Logic /tb_accelerator_integration/clk
add wave -format Logic /tb_accelerator_integration/rst_n

add wave -noupdate -divider "Control Signals"
add wave -format Logic /tb_accelerator_integration/start
add wave -format Logic /tb_accelerator_integration/mode_load
add wave -format Logic /tb_accelerator_integration/mode_weight
add wave -format Logic /tb_accelerator_integration/mode_compute
add wave -format Logic /tb_accelerator_integration/busy
add wave -format Logic /tb_accelerator_integration/done

add wave -noupdate -divider "Configuration"
add wave -format Literal -radix unsigned /tb_accelerator_integration/cfg_N
add wave -format Literal -radix unsigned /tb_accelerator_integration/cfg_K

add wave -noupdate -divider "External Data Interface"
add wave -format Logic /tb_accelerator_integration/ext_data_valid
add wave -format Logic /tb_accelerator_integration/ext_data_ready
add wave -format Literal -radix hexadecimal /tb_accelerator_integration/ext_data_in

add wave -noupdate -divider "External Result Interface"
add wave -format Logic /tb_accelerator_integration/ext_result_valid
add wave -format Logic /tb_accelerator_integration/ext_result_ready
add wave -format Literal -radix hexadecimal /tb_accelerator_integration/ext_result_out

add wave -noupdate -divider "Status Signals"
add wave -format Logic /tb_accelerator_integration/sa_computing
add wave -format Logic /tb_accelerator_integration/mem_writing
add wave -format Logic /tb_accelerator_integration/mem_reading

add wave -noupdate -divider "DUT Internal - FSM State"
add wave -format Literal -radix unsigned /tb_accelerator_integration/dut/state
add wave -format Literal -radix unsigned /tb_accelerator_integration/dut/write_addr_counter
add wave -format Literal -radix unsigned /tb_accelerator_integration/dut/read_addr_counter

add wave -noupdate -divider "Memory Controller Signals"
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/ping_active
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/ping_write_active
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/agu_wr_valid
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/agu_wr_ready
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/sa_rd_data_valid
add wave -format Logic /tb_accelerator_integration/dut/mem_ctrl/sa_rd_data_ready

add wave -noupdate -divider "Systolic Array Signals"
add wave -format Logic /tb_accelerator_integration/dut/sa/enable
add wave -format Logic /tb_accelerator_integration/dut/sa/load_weight
add wave -format Logic /tb_accelerator_integration/dut/sa/data_valid
add wave -format Logic /tb_accelerator_integration/dut/sa/data_ready
add wave -format Logic /tb_accelerator_integration/dut/sa/result_valid
add wave -format Logic /tb_accelerator_integration/dut/sa/result_ready

add wave -noupdate -divider "Test Control"
add wave -format Literal -radix unsigned /tb_accelerator_integration/test_num
add wave -format Literal -radix unsigned /tb_accelerator_integration/errors
add wave -format Literal -radix unsigned /tb_accelerator_integration/result_count

# Configure wave window properties
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Update wave window
WaveRestoreZoom {0 ns} {5000 ns}

echo "=========================================="
echo "Starting Simulation..."
echo "=========================================="

# Run simulation
run -all

echo "=========================================="
echo "Simulation Complete!"
echo "=========================================="

# Zoom to fit
wave zoom full
