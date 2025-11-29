vlib work
vlog ../rtl/core/processing_element.v
vlog ../rtl/core/systolic_array.v
vlog ../rtl/tb/tb_systolic_array_stage1.v

vsim -c work.tb_systolic_array_stage1
run -all
quit -f