# ModelSim/QuestaSim simulation script for DRAM module
# Run with: vsim -do run_dram_test.do

# Create work library if it doesn't exist
if {![file exists work]} {
    vlib work
}

# Compile source files
vlog -work work ../mem/dram.v
vlog -work work tb_dram.v

# Start simulation
vsim -voptargs=+acc work.tb_dram

# Add waves
add wave -noupdate -divider "Clock and Reset"
add wave -noupdate /tb_dram/clk
add wave -noupdate /tb_dram/rst_n

add wave -noupdate -divider "RX Stream (DRAM → Accelerator)"
add wave -noupdate -radix hexadecimal /tb_dram/rx_data
add wave -noupdate /tb_dram/rx_valid
add wave -noupdate /tb_dram/rx_ready

add wave -noupdate -divider "TX Stream (Accelerator → DRAM)"
add wave -noupdate -radix hexadecimal /tb_dram/tx_data
add wave -noupdate /tb_dram/tx_valid
add wave -noupdate /tb_dram/tx_ready

add wave -noupdate -divider "Control Interface"
add wave -noupdate -radix hexadecimal /tb_dram/read_addr
add wave -noupdate /tb_dram/read_enable
add wave -noupdate -radix hexadecimal /tb_dram/write_addr
add wave -noupdate /tb_dram/write_enable
add wave -noupdate -radix unsigned /tb_dram/transfer_length

add wave -noupdate -divider "Status"
add wave -noupdate /tb_dram/read_complete
add wave -noupdate /tb_dram/write_complete
add wave -noupdate /tb_dram/dram_busy

add wave -noupdate -divider "Internal State"
add wave -noupdate /tb_dram/dut/state
add wave -noupdate -radix hexadecimal /tb_dram/dut/current_addr
add wave -noupdate -radix unsigned /tb_dram/dut/transfers_remaining

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
run -all

# Zoom to fit
wave zoom full

puts "Simulation complete. Check waveform for results."
