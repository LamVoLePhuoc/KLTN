# Synthesize one HART_ID-specific core+private-L1 partition for insertion into
# the hierarchical full-SoC implementation.  Keeping the four partitions out
# of the parent synthesis avoids the monolithic elaboration/flatten OOM.
#
# Usage: vivado -mode batch -source scripts/synth_hier_core_l1.tcl -tclargs \
#          <output-dir> <hart-id> <MESI_ENABLE> ?<period-ns>?

if {$argc < 3 || $argc > 4} {
    error "Usage: synth_hier_core_l1.tcl <output-dir> <hart-id> <MESI_ENABLE> ?<period-ns>?"
}

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set out_dir     [file normalize [lindex $argv 0]]
set hart_id     [lindex $argv 1]
set mesi_enable [lindex $argv 2]
set period_ns   [expr {$argc == 4 ? double([lindex $argv 3]) : 4.000}]

if {$hart_id ni {0 1 2 3}} { error "hart-id must be 0..3" }
if {$mesi_enable ni {0 1}} { error "MESI_ENABLE must be 0 or 1" }
file mkdir $out_dir

set project_file [open [file join $project_dir Risc_V.xpr] r]
set project_xml [read $project_file]
close $project_file
if {![regexp {<Option Name="Part" Val="([^"]+)"} $project_xml -> part_name]} {
    error "Cannot resolve target part from Risc_V.xpr"
}

set_param general.maxThreads 1
create_project -in_memory -part $part_name
set_property TARGET_LANGUAGE Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property verilog_define {PPA_NO_MARK_DEBUG} [current_fileset]

set manifest [open [file join $rtl_dir files.f] r]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    read_verilog [file normalize [file join $rtl_dir $line]]
}
close $manifest

set child_xdc [file join $out_dir "core${hart_id}_clock.xdc"]
set xdc_fd [open $child_xdc w]
puts $xdc_fd [format {create_clock -name child_ooc_clk -period %.3f [get_ports {clk}]} $period_ns]
close $xdc_fd
read_xdc $child_xdc
synth_design -top core_l1_wrapper -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt \
    -generic "HART_ID=$hart_id" -generic "MESI_ENABLE=$mesi_enable"

set debug_nets [get_nets -quiet -hier -filter {MARK_DEBUG == 1}]
if {[llength $debug_nets] != 0} {
    error "Child hart $hart_id retained [llength $debug_nets] MARK_DEBUG nets"
}

report_utilization -file [file join $out_dir "core${hart_id}_utilization_synth.rpt"]

# The top-level ACLK constraint must be the sole clock authority after all
# partitions are linked.  The child clock has already guided synthesis.
reset_timing
set dcp_path [file join $out_dir "core${hart_id}_synth.dcp"]
write_checkpoint -force $dcp_path
puts "HIER_CHILD_RESULT hart=$hart_id mesi=$mesi_enable dcp=$dcp_path"
close_project
