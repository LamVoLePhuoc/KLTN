transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+RiscV_dualcore  -L xil_defaultlib -L axi_bram_ctrl_v4_1_13 -L blk_mem_gen_v8_4_12 -L proc_sys_reset_v5_0_17 -L generic_baseblocks_v2_1_2 -L axi_infrastructure_v1_1_0 -L axi_register_slice_v2_1_36 -L fifo_generator_v13_2_14 -L axi_data_fifo_v2_1_36 -L axi_crossbar_v2_1_38 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.RiscV_dualcore xil_defaultlib.glbl

do {RiscV_dualcore.udo}

run 1000ns

endsim

quit -force
