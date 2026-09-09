vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xil_defaultlib

vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" \
"../../../bd/RV32IMFA_DualCore/ip/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0/sim/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0.v" \
"../../../bd/RV32IMFA_DualCore/sim/RV32IMFA_DualCore.v" \


vlog -work xil_defaultlib \
"glbl.v"

