transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xil_defaultlib

vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../../AMDDesignTools/2025.2/Vivado/data/rsb/busdef" -l xil_defaultlib \
"../../../bd/RV32IMFA_DualCore/ip/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0/sim/RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0.v" \
"../../../bd/RV32IMFA_DualCore/sim/RV32IMFA_DualCore.v" \


vlog -work xil_defaultlib \
"glbl.v"

