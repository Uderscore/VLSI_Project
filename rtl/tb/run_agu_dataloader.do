# ModelSim/QuestaSim simulation script for AGU and Data Loader testbench
# Run with: vsim -do run_agu_dataloader.do

# Create work library if it doesn't exist
if {![file exists work]} {
    vlib work
}

# Compile source files
echo "Compiling DRAM module..."
vlog -work work ../mem/dram.v

echo "Compiling SRAM module..."
vlog -work work ../mem/sram.v
vlog -work work ../../third_party/sram_macros/sky130_sram_1kbyte_1rw1r_32x256_8.v

echo "Compiling AGU module..."
vlog -work work ../AGU/agu.v

echo "Compiling Data Loader module..."
vlog -work work ../AGU/data_loader.v

echo "Compiling testbench..."
vlog -work work tb_agu_dataloader.v

# Start simulation
echo "Starting simulation..."
vsim -voptargs=+acc work.tb_agu_dataloader

# Add waves
add wave -noupdate -divider "Clock and Reset"
add wave -noupdate /tb_agu_dataloader/clk
add wave -noupdate /tb_agu_dataloader/rst_n

add wave -noupdate -divider "Control Signals"
add wave -noupdate /tb_agu_dataloader/start
add wave -noupdate /tb_agu_dataloader/go_load
add wave -noupdate /tb_agu_dataloader/go_stream
add wave -noupdate /tb_agu_dataloader/go_unload
add wave -noupdate /tb_agu_dataloader/mode_load_weight

add wave -noupdate -divider "Configuration"
add wave -noupdate -radix unsigned /tb_agu_dataloader/image_width
add wave -noupdate -radix unsigned /tb_agu_dataloader/image_height
add wave -noupdate -radix unsigned /tb_agu_dataloader/kernel_size
add wave -noupdate -radix unsigned /tb_agu_dataloader/current_tile_x
add wave -noupdate -radix unsigned /tb_agu_dataloader/current_tile_y

add wave -noupdate -divider "Status"
add wave -noupdate /tb_agu_dataloader/load_done
add wave -noupdate /tb_agu_dataloader/stream_done
add wave -noupdate /tb_agu_dataloader/unload_done
add wave -noupdate /tb_agu_dataloader/buffer_ready
add wave -noupdate /tb_agu_dataloader/active_buffer

add wave -noupdate -divider "AGU Signals"
add wave -noupdate /tb_agu_dataloader/data_loader_inst/agu_inst/state
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/data_loader_inst/agu_inst/rd_addr
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/data_loader_inst/agu_inst/wr_addr
add wave -noupdate /tb_agu_dataloader/data_loader_inst/agu_inst/rd_enable
add wave -noupdate /tb_agu_dataloader/data_loader_inst/agu_inst/wr_enable
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/agu_inst/tile_width
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/agu_inst/tile_height
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/agu_inst/halo_size
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/agu_inst/x_counter
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/agu_inst/y_counter

add wave -noupdate -divider "Data Loader Signals"
add wave -noupdate /tb_agu_dataloader/data_loader_inst/state
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/load_counter
add wave -noupdate -radix unsigned /tb_agu_dataloader/data_loader_inst/stream_counter
add wave -noupdate /tb_agu_dataloader/data_loader_inst/dram_read_active
add wave -noupdate /tb_agu_dataloader/data_loader_inst/dram_write_active

add wave -noupdate -divider "DRAM Interface"
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/dram_rx_data
add wave -noupdate /tb_agu_dataloader/dram_rx_valid
add wave -noupdate /tb_agu_dataloader/dram_rx_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/dram_tx_data
add wave -noupdate /tb_agu_dataloader/dram_tx_valid
add wave -noupdate /tb_agu_dataloader/dram_tx_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/dram_read_addr
add wave -noupdate /tb_agu_dataloader/dram_read_enable

add wave -noupdate -divider "SRAM Interface"
add wave -noupdate /tb_agu_dataloader/sram_wr_valid
add wave -noupdate /tb_agu_dataloader/sram_wr_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/sram_wr_data
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/sram_wr_addr
add wave -noupdate /tb_agu_dataloader/sram_rd_valid
add wave -noupdate /tb_agu_dataloader/sram_rd_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/sram_rd_data
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/sram_rd_addr
add wave -noupdate /tb_agu_dataloader/sram_wr_buffer_full
add wave -noupdate /tb_agu_dataloader/sram_rd_buffer_empty

add wave -noupdate -divider "Systolic Array Interface"
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/pixel_out
add wave -noupdate /tb_agu_dataloader/pixel_valid
add wave -noupdate -radix hexadecimal /tb_agu_dataloader/psum_in
add wave -noupdate /tb_agu_dataloader/psum_valid

add wave -noupdate -divider "SRAM Buffer Status"
add wave -noupdate /tb_agu_dataloader/sram_inst/ping_active
add wave -noupdate /tb_agu_dataloader/sram_inst/ping_write_active
add wave -noupdate -radix unsigned /tb_agu_dataloader/sram_inst/ping_wr_count
add wave -noupdate -radix unsigned /tb_agu_dataloader/sram_inst/pong_wr_count

# Configure wave window
configure wave -namecolwidth 300
configure wave -valuecolwidth 120
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

puts "Simulation complete. Check waveform and transcript for results."
