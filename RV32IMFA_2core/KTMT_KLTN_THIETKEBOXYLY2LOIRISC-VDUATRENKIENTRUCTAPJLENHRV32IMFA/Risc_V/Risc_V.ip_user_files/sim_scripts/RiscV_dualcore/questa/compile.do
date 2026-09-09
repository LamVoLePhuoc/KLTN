vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xil_defaultlib
vlib questa_lib/msim/axi_bram_ctrl_v4_1_13
vlib questa_lib/msim/blk_mem_gen_v8_4_12
vlib questa_lib/msim/proc_sys_reset_v5_0_17
vlib questa_lib/msim/generic_baseblocks_v2_1_2
vlib questa_lib/msim/axi_infrastructure_v1_1_0
vlib questa_lib/msim/axi_register_slice_v2_1_36
vlib questa_lib/msim/fifo_generator_v13_2_14
vlib questa_lib/msim/axi_data_fifo_v2_1_36
vlib questa_lib/msim/axi_crossbar_v2_1_38

vmap xil_defaultlib questa_lib/msim/xil_defaultlib
vmap axi_bram_ctrl_v4_1_13 questa_lib/msim/axi_bram_ctrl_v4_1_13
vmap blk_mem_gen_v8_4_12 questa_lib/msim/blk_mem_gen_v8_4_12
vmap proc_sys_reset_v5_0_17 questa_lib/msim/proc_sys_reset_v5_0_17
vmap generic_baseblocks_v2_1_2 questa_lib/msim/generic_baseblocks_v2_1_2
vmap axi_infrastructure_v1_1_0 questa_lib/msim/axi_infrastructure_v1_1_0
vmap axi_register_slice_v2_1_36 questa_lib/msim/axi_register_slice_v2_1_36
vmap fifo_generator_v13_2_14 questa_lib/msim/fifo_generator_v13_2_14
vmap axi_data_fifo_v2_1_36 questa_lib/msim/axi_data_fifo_v2_1_36
vmap axi_crossbar_v2_1_38 questa_lib/msim/axi_crossbar_v2_1_38

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/ALU.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/ALU_Decoder.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/Control_Unit.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FPU.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FPU_Decoder.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FP_Add.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FP_Div.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FP_Mul.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/FP_Register_File.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/Main_Decoder.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/Mux_3_by_1.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/PC_Adder.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/PC_module.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/RV32IMFA.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/Register_File.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/Sign_Extend.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/decode_stage.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/ex_mem_registers.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/execute_stage.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/fetch_stage.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/hazard_unit.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/id_ex_registers.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/if_id_registers.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/mem_wb_registers.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/memory_stage.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/mux.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/writeback_stage.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9e55/src/RV32_IP_Wrapper.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_RV32IMFA_IP_Wrapper_0_2/sim/RiscV_dualcore_RV32IMFA_IP_Wrapper_0_2.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_RV32IMFA_IP_Wrapper_0_3/sim/RiscV_dualcore_RV32IMFA_IP_Wrapper_0_3.v" \

vcom -work axi_bram_ctrl_v4_1_13  -93  \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/2f03/hdl/axi_bram_ctrl_v4_1_rfs.vhd" \

vcom -work xil_defaultlib  -93  \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_axi_bram_ctrl_0_1/sim/RiscV_dualcore_axi_bram_ctrl_0_1.vhd" \

vlog -work blk_mem_gen_v8_4_12  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/42f3/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_axi_bram_ctrl_0_bram_0_1/sim/RiscV_dualcore_axi_bram_ctrl_0_bram_0.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_clk_wiz_0_1/RiscV_dualcore_clk_wiz_0_clk_wiz.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_clk_wiz_0_1/RiscV_dualcore_clk_wiz_0.v" \

vcom -work proc_sys_reset_v5_0_17  -93  \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/9438/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib  -93  \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_rst_clk_wiz_100M_0_1/sim/RiscV_dualcore_rst_clk_wiz_100M_0.vhd" \

vlog -work generic_baseblocks_v2_1_2  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/0c28/hdl/generic_baseblocks_v2_1_vl_rfs.v" \

vlog -work axi_infrastructure_v1_1_0  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_register_slice_v2_1_36  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/bc4b/hdl/axi_register_slice_v2_1_vl_rfs.v" \

vlog -work fifo_generator_v13_2_14  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/d654/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_14  -93  \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/d654/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_14  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/d654/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work axi_data_fifo_v2_1_36  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/fb46/hdl/axi_data_fifo_v2_1_vl_rfs.v" \

vlog -work axi_crossbar_v2_1_38  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/f084/hdl/axi_crossbar_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/a415" "+incdir+../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ipshared/ec67/hdl" "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/ip/RiscV_dualcore_axi_interconnect_0_imp_xbar_0/sim/RiscV_dualcore_axi_interconnect_0_imp_xbar_0.v" \
"../../../../Risc-V.gen/sources_1/bd/RiscV_dualcore/sim/RiscV_dualcore.v" \

vlog -work xil_defaultlib \
"glbl.v"

