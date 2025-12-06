# ModelSim/QuestaSim simulation script for AGU and Data Loader with Real Data
# Run with: vsim -do run_agu_dataloader_real.do

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
vlog -work work tb_agu_dataloader_real.v

# Start simulation
echo "Starting simulation..."
vsim -voptargs=+acc work.tb_agu_dataloader_real

# Add waves
add wave -noupdate -divider "Clock and Reset"
add wave -noupdate /tb_agu_dataloader_real/clk
add wave -noupdate /tb_agu_dataloader_real/rst_n

add wave -noupdate -divider "Test Status"
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/test_passed
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/test_failed
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/num_input_pixels
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/num_kernel_weights
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/output_count

add wave -noupdate -divider "Control Signals"
add wave -noupdate /tb_agu_dataloader_real/start
add wave -noupdate /tb_agu_dataloader_real/go_load
add wave -noupdate /tb_agu_dataloader_real/go_stream
add wave -noupdate /tb_agu_dataloader_real/go_unload
add wave -noupdate /tb_agu_dataloader_real/mode_load_weight

add wave -noupdate -divider "Configuration"
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/image_width
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/image_height
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/kernel_size
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/current_tile_x
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/current_tile_y

add wave -noupdate -divider "Status"
add wave -noupdate /tb_agu_dataloader_real/load_done
add wave -noupdate /tb_agu_dataloader_real/stream_done
add wave -noupdate /tb_agu_dataloader_real/unload_done
add wave -noupdate /tb_agu_dataloader_real/buffer_ready
add wave -noupdate /tb_agu_dataloader_real/active_buffer

add wave -noupdate -divider "AGU State"
add wave -noupdate /tb_agu_dataloader_real/data_loader_inst/agu_inst/state
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/data_loader_inst/agu_inst/tile_width
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/data_loader_inst/agu_inst/tile_height
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/data_loader_inst/agu_inst/halo_size
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/data_loader_inst/agu_inst/tile_start_x
add wave -noupdate -radix unsigned /tb_agu_dataloader_real/data_loader_inst/agu_inst/tile_start_y

add wave -noupdate -divider "AGU Addresses"
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/data_loader_inst/agu_inst/dram_rd_addr
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/data_loader_inst/agu_inst/dram_wr_addr
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/data_loader_inst/agu_inst/wr_addr
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/data_loader_inst/agu_inst/rd_addr
add wave -noupdate /tb_agu_dataloader_real/data_loader_inst/agu_inst/dram_rd_req
add wave -noupdate /tb_agu_dataloader_real/data_loader_inst/agu_inst/dram_wr_req

add wave -noupdate -divider "DRAM Interface"
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/dram_read_addr
add wave -noupdate /tb_agu_dataloader_real/dram_read_enable
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/dram_rx_data
add wave -noupdate /tb_agu_dataloader_real/dram_rx_valid
add wave -noupdate /tb_agu_dataloader_real/dram_rx_ready

add wave -noupdate -divider "SRAM Interface"
add wave -noupdate /tb_agu_dataloader_real/sram_wr_valid
add wave -noupdate /tb_agu_dataloader_real/sram_wr_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/sram_wr_data
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/sram_wr_addr
add wave -noupdate /tb_agu_dataloader_real/sram_rd_valid
add wave -noupdate /tb_agu_dataloader_real/sram_rd_ready
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/sram_rd_data
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/sram_rd_addr

add wave -noupdate -divider "Pixel Output"
add wave -noupdate /tb_agu_dataloader_real/pixel_valid
add wave -noupdate -radix hexadecimal /tb_agu_dataloader_real/pixel_out

# Configure wave window
configure wave -namecolwidth 350
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
puts "Output file: ../../sim/data/results/agu_dataloader_output.txt"
