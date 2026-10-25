# The project currently targets the generic xc7z030fbv676-1 part, not a named
# board. Constrain timing here, but do not guess physical pins: the earlier Y9
# and P16 locations belong to another package and Vivado correctly rejected
# them. Add PACKAGE_PIN/IOSTANDARD constraints once the actual board is fixed.
# The generated soc_4core_trial_wrapper port is named sys_clk.  Do not use
# -quiet here: a renamed/missing clock port must be visible as a constraint
# error instead of silently leaving every sequential path unconstrained.
create_clock -name sys_clk_in -period 10.000 [get_ports sys_clk]
