# Re-check a routed Vivado checkpoint at a tighter clock period without
# changing placement or routing.  This separates an achieved timing target
# from the looser timing-derived Fmax estimate printed by run_ooc_ppa.tcl.
#
# Usage:
#   vivado -mode batch -source scripts/check_routed_timing.tcl -tclargs \
#       <routed.dcp> <clock_name> <clock_port> <period_ns> <report_dir>

if {$argc != 5} {
    error "Usage: check_routed_timing.tcl <routed.dcp> <clock_name> <clock_port> <period_ns> <report_dir>"
}

set dcp_path   [file normalize [lindex $argv 0]]
set clock_name [lindex $argv 1]
set clock_port [lindex $argv 2]
set period_ns  [expr {double([lindex $argv 3])}]
set report_dir [file normalize [lindex $argv 4]]

if {![file exists $dcp_path]} {
    error "Routed checkpoint not found: $dcp_path"
}
file mkdir $report_dir

open_checkpoint $dcp_path
if {[llength [get_ports -quiet $clock_port]] != 1} {
    error "Expected one top-level clock port '$clock_port'"
}

# Reissuing create_clock without -add replaces the existing primary clock on
# this source.  Placement and routing remain untouched; only STA is updated.
create_clock -name $clock_name -period $period_ns [get_ports $clock_port]

report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path  [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Unable to resolve setup/hold timing paths"
}

set setup_slack [get_property SLACK $setup_path]
set hold_slack  [get_property SLACK $hold_path]
set target_mhz  [expr {1000.0 / $period_ns}]

set summary_path [file join $report_dir summary.md]
set summary [open $summary_path w]
puts $summary "# Routed timing validation"
puts $summary ""
puts $summary "- Checkpoint: `[file tail $dcp_path]`"
puts $summary [format "- Target: `%.6f ns` (`%.3f MHz`) on `%s`" \
    $period_ns $target_mhz $clock_port]
puts $summary [format "- Setup WNS: `%.3f ns`" $setup_slack]
puts $summary [format "- Hold slack: `%.3f ns`" $hold_slack]
puts $summary "- Critical startpoint: `[get_property STARTPOINT_PIN $setup_path]`"
puts $summary "- Critical endpoint: `[get_property ENDPOINT_PIN $setup_path]`"
close $summary

puts [format "ROUTED_TIMING_RESULT target=%.3fMHz WNS=%.3fns WHS=%.3fns" \
    $target_mhz $setup_slack $hold_slack]
puts "Evidence: $summary_path"
close_project
