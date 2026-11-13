# Memory-efficient bottom-up route of the complete four-core AXI wrapper.
# Four HART_ID-specific core+L1 DCPs are inserted into black boxes in a parent
# netlist containing reset, AHB, coherence/L2 and AXI logic.
#
# Usage: vivado -mode batch -source scripts/run_hierarchical_soc_ppa.tcl \
#          -tclargs <child-dcp-dir> ?<period-ns>? ?<MESI_ENABLE>?

if {$argc < 1 || $argc > 3} {
    error "Usage: run_hierarchical_soc_ppa.tcl <child-dcp-dir> ?<period-ns>? ?<MESI_ENABLE>?"
}

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set child_dir   [file normalize [lindex $argv 0]]
set period_ns   [expr {$argc >= 2 ? double([lindex $argv 1]) : 4.000}]
set mesi_enable [expr {$argc >= 3 ? [lindex $argv 2] : 1}]
if {$mesi_enable ni {0 1}} { error "MESI_ENABLE must be 0 or 1" }

for {set hart 0} {$hart < 4} {incr hart} {
    set child_dcp [file join $child_dir "core${hart}_synth.dcp"]
    if {![file exists $child_dcp]} { error "Missing child checkpoint: $child_dcp" }
}

set project_file [open [file join $project_dir Risc_V.xpr] r]
set project_xml [read $project_file]
close $project_file
if {![regexp {<Option Name="Part" Val="([^"]+)"} $project_xml -> part_name]} {
    error "Cannot resolve target part from Risc_V.xpr"
}

set stamp [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir [file join $project_dir reports "hier-ppa-quad-core-soc-$stamp"]
file mkdir $report_dir

set_param general.maxThreads 1
create_project -in_memory -part $part_name
set_property TARGET_LANGUAGE Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property verilog_define {PPA_NO_MARK_DEBUG} [current_fileset]

# Read every active source except the real core_l1_wrapper implementation;
# the synthesis-only black-box shell supplies that module boundary.
set wrapper_source [file normalize [file join $rtl_dir cache core_l1_wrapper.v]]
set manifest [open [file join $rtl_dir files.f] r]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    set source_path [file normalize [file join $rtl_dir $line]]
    if {$source_path eq $wrapper_source} { continue }
    read_verilog $source_path
}
close $manifest
read_verilog [file join $script_dir ppa core_l1_wrapper_blackbox.v]

set top_xdc [file join $report_dir soc_clock.xdc]
set xdc_fd [open $top_xdc w]
puts $xdc_fd [format {create_clock -name soc_clk -period %.3f [get_ports {ACLK}]} $period_ns]
close $xdc_fd
read_xdc $top_xdc
synth_design -top quad_core_axi_wrapper_ahb -part $part_name \
    -flatten_hierarchy none -no_iobuf \
    -generic "MESI_ENABLE=$mesi_enable"

set expected_cells {soc/core0 soc/core1 soc/core2 soc/core3}
# Vivado's hierarchical-design flow requires these black boxes to be explicit
# partitions before importing OOC checkpoints.  Besides enabling the special
# checkpoint cleanup path, HD.PARTITION protects the interfaces from parent
# optimization (UG905).
set_property HD.PARTITION 1 [get_cells $expected_cells]
for {set hart 0} {$hart < 4} {incr hart} {
    set cell_name [lindex $expected_cells $hart]
    set target_cell [get_cells -quiet $cell_name]
    if {[llength $target_cell] != 1} {
        set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
        error "Cannot find unique partition cell '$cell_name'; black boxes: $blackboxes"
    }
    # Pass the stable cell name, not the object handle: read_checkpoint
    # rebuilds the in-memory design and invalidates previously queried objects.
    read_checkpoint -strict -cell $cell_name \
        [file join $child_dir "core${hart}_synth.dcp"]
}

set remaining_blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $remaining_blackboxes] != 0} {
    error "Unresolved black boxes after child insertion: $remaining_blackboxes"
}
set debug_nets [get_nets -quiet -hier -filter {MARK_DEBUG == 1}]
if {[llength $debug_nets] != 0} {
    error "Hierarchical PPA build retained [llength $debug_nets] MARK_DEBUG nets"
}

report_utilization -file [file join $report_dir utilization_linked_synth.rpt]
write_checkpoint -force [file join $report_dir linked_synth.dcp]

opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $report_dir utilization_route.rpt]
report_utilization -hierarchical -hierarchical_depth 5 \
    -file [file join $report_dir utilization_hierarchical_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 30 \
    -file [file join $report_dir timing_route.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_methodology -file [file join $report_dir methodology_route.rpt]
write_checkpoint -force [file join $report_dir quad_core_axi_wrapper_ahb_route.dcp]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path  [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Cannot resolve unique setup/hold timing paths after route"
}
set setup_slack [get_property SLACK $setup_path]
set hold_slack  [get_property SLACK $hold_path]
set effective_period [expr {$period_ns - $setup_slack}]
set estimated_fmax [expr {$effective_period > 0.0 ? 1000.0 / $effective_period : 0.0}]
set failed_nets -1
catch {
    set failed_nets [llength [get_nets -quiet -hier -filter \
        {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL}]]
}

set summary_path [file join $report_dir summary.md]
set summary [open $summary_path w]
puts $summary "# Hierarchical full four-core SoC PPA"
puts $summary ""
puts $summary "- Part: `$part_name`"
puts $summary "- MESI_ENABLE: `$mesi_enable`"
puts $summary [format "- Target: `%.3f ns` (`%.3f MHz`)" $period_ns [expr {1000.0/$period_ns}]]
puts $summary [format "- Setup WNS: `%.3f ns`" $setup_slack]
puts $summary [format "- Hold slack: `%.3f ns`" $hold_slack]
puts $summary [format "- Timing-derived Fmax estimate: `%.3f MHz`" $estimated_fmax]
puts $summary "- Failed/unrouted nets: `$failed_nets`"
puts $summary "- MARK_DEBUG nets: `[llength $debug_nets]`"
puts $summary "- Critical startpoint: `[get_property STARTPOINT_PIN $setup_path]`"
puts $summary "- Critical endpoint: `[get_property ENDPOINT_PIN $setup_path]`"
puts $summary ""
puts $summary "> All four HART_ID-specific core/L1 checkpoints were linked before implementation."
puts $summary "> Scope: internal RTL route with `-no_iobuf`. Final VCU129 board sign-off must drive ACLK through the board clocking/BUFG path and constrain external AXI input/output delays."
close $summary

puts [format "HIER_SOC_RESULT WNS=%.3fns hold=%.3fns estimated_Fmax=%.3fMHz failed_nets=%d" \
    $setup_slack $hold_slack $estimated_fmax $failed_nets]
puts "Evidence: $summary_path"
close_project

# A generated report is not a passing PPA result unless setup, hold and routing
# all pass. Keep the reports/checkpoint for diagnosis, but return a failing
# Vivado exit status so automation cannot accidentally promote a bad route.
if {$setup_slack < 0.0 || $hold_slack < 0.0 || $failed_nets != 0} {
    error [format "Hierarchical route failed sign-off: WNS=%.3f ns, hold=%.3f ns, failed/unrouted nets=%d" \
        $setup_slack $hold_slack $failed_nets]
}
