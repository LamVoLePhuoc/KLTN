transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+RV32IMFA_DualCore  -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.RV32IMFA_DualCore xil_defaultlib.glbl

do {RV32IMFA_DualCore.udo}

run 1000ns

endsim

quit -force
