vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../bd/RV32IMFA_DualCore/ip/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0/sim/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0.v" \
"../../../bd/RV32IMFA_DualCore/sim/RV32IMFA_DualCore.v" \


vlog -work xil_defaultlib \
"glbl.v"

