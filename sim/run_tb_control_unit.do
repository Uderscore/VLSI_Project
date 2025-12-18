# ModelSim DO file for Control Unit Testbench
# Compiles and simulates the Control Unit (Main FSM)

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile the Control Unit module
vlog -work work "../rtl/control/control_unit.v"

# Compile the testbench
vlog -work work "../rtl/tb/tb_control_unit.v"

# Start simulation
vsim -voptargs=+acc work.tb_control_unit

# Add waves
add wave -position insertpoint -radix hex sim:/tb_control_unit/*

# Add DUT internal signals
add wave -divider "FSM State"
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/state
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/next_state
add wave -position insertpoint sim:/tb_control_unit/dut/busy
add wave -position insertpoint sim:/tb_control_unit/dut/done

add wave -divider "Host Interface"
add wave -position insertpoint sim:/tb_control_unit/dut/host_start
add wave -position insertpoint sim:/tb_control_unit/dut/host_data_valid
add wave -position insertpoint sim:/tb_control_unit/dut/host_ack

add wave -divider "Configuration"
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/cfg_N_latched
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/cfg_K_latched
add wave -position insertpoint sim:/tb_control_unit/dut/cfg_valid

add wave -divider "AGU Control"
add wave -position insertpoint sim:/tb_control_unit/dut/agu_start
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/agu_mode
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/agu_tile_x
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/agu_tile_y
add wave -position insertpoint sim:/tb_control_unit/dut/agu_busy
add wave -position insertpoint sim:/tb_control_unit/dut/agu_tile_done
add wave -position insertpoint sim:/tb_control_unit/dut/agu_next_tile

add wave -divider "Tile Tracking"
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/current_tile_x
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/current_tile_y
add wave -position insertpoint -radix unsigned sim:/tb_control_unit/dut/num_tiles_x
add wave -position insertpoint sim:/tb_control_unit/dut/all_tiles_loaded
add wave -position insertpoint sim:/tb_control_unit/dut/all_tiles_computed
add wave -position insertpoint sim:/tb_control_unit/dut/all_tiles_drained

add wave -divider "Systolic Array Control"
add wave -position insertpoint sim:/tb_control_unit/dut/sa_enable
add wave -position insertpoint sim:/tb_control_unit/dut/sa_load_weight
add wave -position insertpoint sim:/tb_control_unit/dut/sa_clear_acc

add wave -divider "Memory Control"
add wave -position insertpoint sim:/tb_control_unit/dut/mem_start
add wave -position insertpoint sim:/tb_control_unit/dut/mem_buffer_switch
add wave -position insertpoint sim:/tb_control_unit/dut/loader_is_loading

# Configure wave window
configure wave -namecolwidth 280
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
