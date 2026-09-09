onbreak {quit -f}
onerror {quit -f}

vsim  -lib xil_defaultlib RV32IMFA_DualCore_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {RV32IMFA_DualCore.udo}

run 1000ns

quit -force
