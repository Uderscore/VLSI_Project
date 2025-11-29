# Create the work library
vlib work

# Compile RTL
vlog -work work ../rtl/core/processing_element.v
vlog -work work ../rtl/core/systolic_array.v

# Compile Testbench
vlog -work work ../rtl/tb/tb_systolic_array.v
vlog -work work ../rtl/tb/tb_systolic_array_2.v

# Load Simulation
vsim -c -voptargs="+acc" work.tb_systolic_array_2

# Run Simulation
run -all

# Quit
quit -f
