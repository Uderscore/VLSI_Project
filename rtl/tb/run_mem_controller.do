# ModelSim DO file for Memory Controller Testbench
# Compiles and simulates the memory controller with ping-pong buffering

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile Sky130 SRAM model
vlog -work work "../../../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v"

# Compile the design files
vlog -work work "../../core/memory_controller.v"

# Compile the testbench
vlog -work work "tb_memory_controller.v"

# Start simulation
vsim -voptargs=+acc work.tb_memory_controller

# Add waves
add wave -position insertpoint -radix hex sim:/tb_memory_controller/*

# Add DUT internal signals
add wave -divider "Controller State"
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/state
add wave -position insertpoint sim:/tb_memory_controller/dut/ping_active
add wave -position insertpoint sim:/tb_memory_controller/dut/ready

add wave -divider "AGU Write Interface"
add wave -position insertpoint sim:/tb_memory_controller/dut/agu_wr_valid
add wave -position insertpoint sim:/tb_memory_controller/dut/agu_wr_ready
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/agu_wr_data
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/agu_wr_addr
add wave -position insertpoint sim:/tb_memory_controller/dut/wr_buffer_full

add wave -divider "AGU Read Interface"
add wave -position insertpoint sim:/tb_memory_controller/dut/agu_rd_data_ready
add wave -position insertpoint sim:/tb_memory_controller/dut/agu_rd_data_valid
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/agu_rd_addr
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/agu_rd_data
add wave -position insertpoint sim:/tb_memory_controller/dut/rd_buffer_empty

add wave -divider "Ping SRAM Signals"
add wave -position insertpoint sim:/tb_memory_controller/dut/ping_csb0
add wave -position insertpoint sim:/tb_memory_controller/dut/ping_web0
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/ping_addr0
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/ping_din0
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/ping_dout0
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/ping_addr1
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/ping_dout1

add wave -divider "Pong SRAM Signals"
add wave -position insertpoint sim:/tb_memory_controller/dut/pong_csb0
add wave -position insertpoint sim:/tb_memory_controller/dut/pong_web0
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/pong_addr0
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/pong_din0
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/pong_dout0
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/pong_addr1
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/pong_dout1

add wave -divider "Internal Control"
add wave -position insertpoint sim:/tb_memory_controller/dut/wr_en
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/wr_addr
add wave -position insertpoint -radix hex sim:/tb_memory_controller/dut/wr_data
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/wr_count
add wave -position insertpoint -radix unsigned sim:/tb_memory_controller/dut/rd_count

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
