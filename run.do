vlib work
#vlog -reportprogress 300 -work work Data_Cache.sv +acc
#vlog -reportprogress 300 -work work Instruction_Cache.sv +acc
#vlog -reportprogress 300 -work work Testbench.sv +acc
vlog -reportprogress 300 -work work /u/maheshn/ECE585/Project/*.sv
vsim -voptargs="+acc" work.SplitL1_TB +Tracefile=tracefile1.txt
run -all

