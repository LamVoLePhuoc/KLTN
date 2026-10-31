# The project currently targets the generic xc7z030fbv676-1 part, not a named
# board. Constrain timing here, but do not guess physical pins: the earlier Y9
# and P16 locations belong to another package and Vivado correctly rejected
# them. Add PACKAGE_PIN/IOSTANDARD constraints once the actual board is fixed.
# The generated soc_4core_trial_wrapper port is named sys_clk.  Do not use
# -quiet here: a renamed/missing clock port must be visible as a constraint
# error instead of silently leaving every sequential path unconstrained.
create_clock -name sys_clk_in -period 9.800 [get_ports sys_clk]

# -----------------------------------------------------------------------------
# BOARD-SPECIFIC I/O -- intentionally left commented until the exact board and
# its official master XDC/schematic are known.  Replace each <...> value with
# the value from that board's documentation, then remove the leading '#'.
# Never copy pin names from a different Zynq-7000 board/package.
# -----------------------------------------------------------------------------
# set_property PACKAGE_PIN <BOARD_100MHZ_CLOCK_PIN> [get_ports sys_clk]
# set_property IOSTANDARD  <BOARD_CLOCK_IOSTANDARD> [get_ports sys_clk]
#
# set_property PACKAGE_PIN <BOARD_RESET_PIN>         [get_ports ext_reset_in]
# set_property IOSTANDARD  <BOARD_RESET_IOSTANDARD>  [get_ports ext_reset_in]

# If the physical reset button is active-low, do not compensate by guessing an
# XDC property.  Confirm the schematic first, then invert/synchronize reset in
# RTL or the Block Design so simulation and hardware use the same polarity.
