# Generate a reproducible vectorless or workload-annotated power report from
# a routed checkpoint.  MSI/MESI comparisons must use SAIFs captured from the
# same binary, duration and memory backpressure pattern.
#
# Usage:
#   vivado -mode batch -source scripts/report_power_dcp.tcl -tclargs \
#       <routed.dcp> <output.rpt> ?<activity.saif> <strip_path>?

if {$argc != 2 && $argc != 4} {
    error "Usage: report_power_dcp.tcl <routed.dcp> <output.rpt> ?<activity.saif> <strip_path>?"
}

set dcp_path [file normalize [lindex $argv 0]]
set out_path [file normalize [lindex $argv 1]]
if {![file exists $dcp_path]} {
    error "Routed checkpoint not found: $dcp_path"
}

file mkdir [file dirname $out_path]
open_checkpoint $dcp_path
if {$argc == 4} {
    set saif_path [file normalize [lindex $argv 2]]
    set strip_path [lindex $argv 3]
    if {![file exists $saif_path]} {
        error "SAIF not found: $saif_path"
    }
    read_saif -strip_path $strip_path \
        -out_file "${out_path}.saif_unmatched.rpt" $saif_path
    report_switching_activity [get_nets -quiet -hierarchical] \
        -file "${out_path}.activity.rpt"
    puts "POWER_ACTIVITY: $saif_path (strip_path=$strip_path)"
}
report_power -file $out_path
puts "POWER_REPORT: $out_path"
close_project
