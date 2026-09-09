onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc"  -L xil_defaultlib -L axi_bram_ctrl_v4_1_13 -L blk_mem_gen_v8_4_12 -L proc_sys_reset_v5_0_17 -L generic_baseblocks_v2_1_2 -L axi_infrastructure_v1_1_0 -L axi_register_slice_v2_1_36 -L fifo_generator_v13_2_14 -L axi_data_fifo_v2_1_36 -L axi_crossbar_v2_1_38 -L unisims_ver -L unimacro_ver -L secureip -lib xil_defaultlib xil_defaultlib.RiscV_dualcore xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {RiscV_dualcore.udo}

run 1000ns

quit -force
