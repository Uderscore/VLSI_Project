# ModelSim do-file for Simplified Full System Testbench
# =========================================================
# Usage: vsim -do scripts/sim/run_full_system.do

# Quit any previous simulation
quit -sim

# Create work library (ignore if exists)
vlib work

# Compile the simplified accelerator and testbench
# Note: Simplified version uses internal register arrays, no SRAM needed
vlog -work work -sv \
    rtl/convolution_accelerator_top.v \
    rtl/tb/tb_full_system.v

# Load the testbench
vsim -voptargs=+acc work.tb_full_system

# Add waves for debugging
add wave -divider "Clock & Reset"
add wave sim:/tb_full_system/clk
add wave sim:/tb_full_system/rst_n

add wave -divider "Control"
add wave sim:/tb_full_system/start
add wave sim:/tb_full_system/done
add wave sim:/tb_full_system/busy
add wave sim:/tb_full_system/cfg_N
add wave sim:/tb_full_system/cfg_K
add wave -radix unsigned sim:/tb_full_system/current_state

add wave -divider "Input Stream"
add wave -radix hex sim:/tb_full_system/rx_data
add wave sim:/tb_full_system/rx_valid
add wave sim:/tb_full_system/rx_ready

add wave -divider "Output Stream"
add wave -radix hex sim:/tb_full_system/tx_data
add wave sim:/tb_full_system/tx_valid
add wave sim:/tb_full_system/tx_ready

add wave -divider "Status"
add wave sim:/tb_full_system/loading_data
add wave sim:/tb_full_system/sa_active
add wave sim:/tb_full_system/draining_results

add wave -divider "DUT Internals"
add wave -radix unsigned sim:/tb_full_system/dut/load_counter
add wave -radix unsigned sim:/tb_full_system/dut/weight_counter
add wave -radix unsigned sim:/tb_full_system/dut/drain_counter
add wave -radix unsigned sim:/tb_full_system/dut/out_x
add wave -radix unsigned sim:/tb_full_system/dut/out_y
add wave -radix unsigned sim:/tb_full_system/dut/acc

# Run simulation
run -all

# Print final status
echo "====================================="
echo "Simulation Complete"
echo "====================================="
