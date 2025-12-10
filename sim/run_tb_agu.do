# ModelSim DO file for AGU Testbench
# Compiles and simulates the Address Generation Unit

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile the AGU module
vlog -work work "../rtl/control/address_generator.v"

# Compile the testbench
vlog -work work "../rtl/tb/tb_agu.v"

# Start simulation
vsim -voptargs=+acc work.tb_agu

# Add waves
add wave -position insertpoint -radix hex sim:/tb_agu/*

# Add DUT internal signals
add wave -divider "AGU State Machine"
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/state
add wave -position insertpoint sim:/tb_agu/dut/busy
add wave -position insertpoint sim:/tb_agu/dut/tile_done
add wave -position insertpoint sim:/tb_agu/dut/frame_done

add wave -divider "Configuration"
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/cfg_N_reg
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/cfg_K_reg
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/input_tile_size

add wave -divider "Tile Tracking"
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/current_tile_x
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/current_tile_y
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/tile_row
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/tile_col

add wave -divider "Kernel Position (STREAM mode)"
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/kernel_row
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/kernel_col

add wave -divider "Address Output"
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/addr_out
add wave -position insertpoint sim:/tb_agu/dut/addr_valid
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/x_coord
add wave -position insertpoint -radix unsigned sim:/tb_agu/dut/y_coord

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
