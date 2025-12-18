# ModelSim simulation script for Data Loader testbench
# Usage: vsim -do run_tb_data_loader.do

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile the design files
vlog -work work ../rtl/control/data_loader.v
if {[catch {vlog -work work ../rtl/control/data_loader.v} result]} {
    echo "ERROR: Failed to compile data_loader.v"
    echo $result
    quit -f
}

# Compile the testbench
vlog -work work ../rtl/tb/tb_data_loader.v +define+SIMULATION
if {[catch {vlog -work work ../rtl/tb/tb_data_loader.v +define+SIMULATION} result]} {
    echo "ERROR: Failed to compile tb_data_loader.v"
    echo $result
    quit -f
}

# Start simulation
vsim -t 1ps -voptargs=+acc work.tb_data_loader

# Add waves
add wave -divider "Clock & Reset"
add wave -format Logic /tb_data_loader/clk
add wave -format Logic /tb_data_loader/rst_n
add wave -format Literal /tb_data_loader/test_num

add wave -divider "Control"
add wave -format Logic /tb_data_loader/is_loading
add wave -format Literal -radix unsigned /tb_data_loader/dut/unload_state
add wave -format Logic /tb_data_loader/dut/unload_next_state

add wave -divider "External Interface (DRAM)"
add wave -format Literal -radix hex /tb_data_loader/rx_data
add wave -format Logic /tb_data_loader/rx_valid
add wave -format Logic /tb_data_loader/rx_ready
add wave -format Literal -radix hex /tb_data_loader/tx_data
add wave -format Logic /tb_data_loader/tx_valid
add wave -format Logic /tb_data_loader/tx_ready

add wave -divider "AGU Interface"
add wave -format Literal -radix hex /tb_data_loader/agu_addr
add wave -format Logic /tb_data_loader/agu_addr_valid
add wave -format Logic /tb_data_loader/agu_next_addr
add wave -format Literal -radix unsigned /tb_data_loader/agu_counter

add wave -divider "Memory Controller Write"
add wave -format Literal -radix hex /tb_data_loader/agu_wr_data
add wave -format Literal -radix hex /tb_data_loader/agu_wr_addr
add wave -format Logic /tb_data_loader/agu_wr_valid
add wave -format Logic /tb_data_loader/agu_wr_ready

add wave -divider "Memory Controller Read"
add wave -format Literal -radix hex /tb_data_loader/agu_rd_addr
add wave -format Logic /tb_data_loader/agu_rd_data_ready
add wave -format Literal -radix hex /tb_data_loader/agu_rd_data
add wave -format Logic /tb_data_loader/agu_rd_data_valid
add wave -format Literal -radix unsigned /tb_data_loader/read_delay_counter
add wave -format Logic /tb_data_loader/read_pending

add wave -divider "Internal Signals"
add wave -format Literal -radix hex /tb_data_loader/dut/latched_data
add wave -format Literal -radix hex /tb_data_loader/dut/truncated_result

# Configure wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Run simulation
echo "Starting Data Loader Testbench..."
run -all

# Zoom to fit
wave zoom full

echo "Simulation complete. Check transcript for results."
