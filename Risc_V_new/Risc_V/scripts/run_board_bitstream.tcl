# Board-release gate for the active four-core physical-address design.
#
# Prerequisites:
#   1. Fill the board-specific PACKAGE_PIN and IOSTANDARD lines in
#      constraints/riscv.xdc from the exact board's official master XDC.
#   2. Run scripts/run_mdu_pipeline_impl.tcl and obtain route_design Complete.
#
# Run from the Vivado Tcl Console:
#   source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_board_bitstream.tcl}

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_xpr [file join $project_dir Risc_V.xpr]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set output_dir  [file join $project_dir reports "board-bitstream-$stamp"]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_xpr
}

puts "=== Four-core board-release gate ==="
puts "Project: [get_property NAME [current_project]]"
puts "Part:    [get_property PART [current_project]]"
puts "Output:  $output_dir"

set impl_run [get_runs -quiet impl_1]
if {[llength $impl_run] != 1} {
    error "impl_1 was not found. Run run_mdu_pipeline_impl.tcl first."
}

set impl_status [get_property STATUS $impl_run]
if {[string first "route_design Complete" $impl_status] < 0} {
    error "impl_1 is '$impl_status'. Run run_mdu_pipeline_impl.tcl first."
}

if {[llength [get_designs -quiet]] > 0} {
    close_design
}
open_run impl_1

# Stop before DRC/bitstream generation if the electrical constraints are
# incomplete.  DEFAULT is not an acceptable board I/O standard.
set io_errors {}
foreach port_name {sys_clk ext_reset_in} {
    set port_obj [get_ports -quiet $port_name]
    if {[llength $port_obj] != 1} {
        lappend io_errors "$port_name: top-level port not found"
        continue
    }

    set package_pin [string trim [get_property PACKAGE_PIN $port_obj]]
    set io_standard [string trim [get_property IOSTANDARD $port_obj]]
    set loc_fixed   [get_property IS_LOC_FIXED $port_obj]

    # Vivado may assign a temporary PACKAGE_PIN/IOSTANDARD during placement.
    # IS_LOC_FIXED distinguishes that temporary placement from an explicit
    # PACKAGE_PIN supplied by the board XDC.
    if {$package_pin eq "" || !$loc_fixed} {
        lappend io_errors "$port_name: PACKAGE_PIN is not fixed by XDC"
    }
    if {$io_standard eq "" || $io_standard eq "DEFAULT"} {
        lappend io_errors "$port_name: IOSTANDARD is missing or DEFAULT"
    }
}

if {[llength $io_errors] != 0} {
    puts ""
    puts "BOARD I/O CHECK: FAIL"
    foreach item $io_errors {
        puts "  - $item"
    }
    puts ""
    puts "Fill constraints/riscv.xdc from the exact board's official XDC."
    puts "Do not lower NSTD-1/UCIO-1 severity and do not guess package pins."
    error "Board pin constraints are incomplete; bitstream was not generated."
}

# Confirm the intended 100 MHz clock constraint exists on the physical port.
set board_clock [get_clocks -quiet -of_objects [get_ports sys_clk]]
if {[llength $board_clock] != 1} {
    error "Expected exactly one clock on sys_clk, found: $board_clock"
}
set clock_period [get_property PERIOD $board_clock]
if {[expr {abs(double($clock_period) - 10.0)}] > 0.001} {
    error "sys_clk period is $clock_period ns; expected 10.000 ns (100 MHz)."
}

# Sign-off timing must pass on both setup and hold before bitstream generation.
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path  [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [llength $hold_path] == 0} {
    error "No complete setup/hold timing path was found in impl_1."
}
set wns [get_property SLACK $setup_path]
set whs [get_property SLACK $hold_path]
puts "Post-route WNS: $wns ns"
puts "Post-route WHS: $whs ns"
if {[expr {double($wns)}] < 0.0 || [expr {double($whs)}] < 0.0} {
    error "Timing sign-off failed (WNS=$wns ns, WHS=$whs ns); bitstream was not generated."
}

file mkdir $output_dir
set timing_report [file join $output_dir timing_summary.rpt]
set drc_report    [file join $output_dir drc.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 -file $timing_report
report_drc -file $drc_report

# Re-check the two board-blocking rules after report_drc has populated the
# violation database.  Other errors remain protected by write_bitstream's own
# mandatory DRC pass.
set blocking_drc [get_drc_violations -quiet -filter {CHECK == NSTD-1 || CHECK == UCIO-1}]
if {[llength $blocking_drc] != 0} {
    error "NSTD-1/UCIO-1 is still present; see $drc_report. Bitstream was not generated."
}

set bit_file [file join $output_dir soc_4core_trial_wrapper.bit]
write_bitstream $bit_file

set summary_file [file join $output_dir summary.txt]
set fd [open $summary_file w]
puts $fd "Four-core board bitstream release"
puts $fd "Generated: [clock format [clock seconds]]"
puts $fd "Part: [get_property PART [current_project]]"
puts $fd "sys_clk period: $clock_period ns"
puts $fd "Post-route WNS: $wns ns"
puts $fd "Post-route WHS: $whs ns"
puts $fd "Bitstream: $bit_file"
close $fd

puts "=== BOARD BITSTREAM: PASS ==="
puts "Bitstream: $bit_file"
puts "Evidence:  $summary_file"
