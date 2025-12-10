# ModelSim DO file for Systolic Array Handshake Testbench
# Compiles and simulates the systolic array with handshake protocol

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile the design files
vlog -work work "../rtl/core/processing_element.v"
vlog -work work "../rtl/core/systolic_array.v"

# Compile the testbench
vlog -work work "../rtl/tb/tb_systolic_array_handshake.v"

# Start simulation
vsim -voptargs=+acc work.tb_systolic_array_handshake

# Add waves
add wave -position insertpoint -radix hex sim:/tb_systolic_array_handshake/*

# Add DUT internal signals
add wave -divider "Handshake Signals"
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/data_valid
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/data_ready
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/weight_valid
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/weight_ready
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/result_valid
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/result_ready

add wave -divider "Control Signals"
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/enable
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/load_weight
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/clear_acc
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/internal_enable
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/internal_load_weight

add wave -divider "Pipeline Status"
add wave -position insertpoint -radix unsigned sim:/tb_systolic_array_handshake/dut/pipeline_count
add wave -position insertpoint sim:/tb_systolic_array_handshake/dut/processing_active

add wave -divider "Data Buses"
add wave -position insertpoint -radix hex sim:/tb_systolic_array_handshake/dut/pixel_in_bus
add wave -position insertpoint -radix hex sim:/tb_systolic_array_handshake/dut/psum_out_bus

# Configure wave window
configure wave -namecolwidth 300
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
