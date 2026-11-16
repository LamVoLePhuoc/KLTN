# Reproducible out-of-context PPA measurement for one active RTL block.
#
# Usage:
#   vivado -mode batch -source scripts/run_ooc_ppa.tcl -tclargs \
#       <top> <clock_port> <period_ns> <synth|impl> ?<MESI_ENABLE>?
#
# Example:
#   vivado -mode batch -source scripts/run_ooc_ppa.tcl -tclargs \
#       ahb_lite_arbiter_8m1s HCLK 9.800 impl
#
# The script reads the canonical rtl/files.f manifest but Vivado retains only
# the hierarchy reachable from <top>. It never opens or modifies Risc_V.xpr.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set project_file [open [file join $project_dir Risc_V.xpr] r]
set project_xml [read $project_file]
close $project_file
if {![regexp {<Option Name="Part" Val="([^"]+)"} $project_xml -> part_name]} {
    error "Cannot resolve target part from Risc_V.xpr"
}

if {$argc < 1 || $argc > 5} {
    error "Usage: run_ooc_ppa.tcl <top> <clock_port> <period_ns> <synth|impl> ?<MESI_ENABLE>?"
}

set top_name     [lindex $argv 0]
set clock_port   [expr {$argc >= 2 ? [lindex $argv 1] : "clk"}]
set period_ns    [expr {$argc >= 3 ? double([lindex $argv 2]) : 9.800}]
set flow_mode    [expr {$argc >= 4 ? [string tolower [lindex $argv 3]] : "impl"}]
set mesi_override [expr {$argc >= 5 ? [lindex $argv 4] : ""}]
if {$flow_mode ni {synth impl}} {
    error "Flow mode must be 'synth' or 'impl', got '$flow_mode'"
}
if {$period_ns <= 0.0} {
    error "Clock period must be positive, got '$period_ns'"
}
if {$mesi_override ne "" && $mesi_override ni {0 1}} {
    error "MESI_ENABLE override must be 0 or 1, got '$mesi_override'"
}

set stamp      [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir [file join $project_dir reports "ooc-ppa-${top_name}-${stamp}"]
file mkdir $report_dir

proc read_active_manifest {rtl_dir} {
    set manifest_path [file join $rtl_dir files.f]
    set manifest [open $manifest_path r]
    set sources {}
    while {[gets $manifest line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {
            continue
        }
        set source_path [file normalize [file join $rtl_dir $line]]
        if {![file exists $source_path]} {
            close $manifest
            error "Manifest source does not exist: $source_path"
        }
        lappend sources $source_path
    }
    close $manifest
    return $sources
}

proc cell_count {filter_expression} {
    return [llength [get_cells -quiet -hier -filter $filter_expression]]
}

proc timing_value {path property_name default_value} {
    if {[llength $path] == 0} {
        return $default_value
    }
    return [get_property $property_name $path]
}

puts "=== OOC PPA: $top_name ==="
puts "Part: $part_name"
puts [format "Clock: %s, %.3f ns (%.3f MHz target)" \
    $clock_port $period_ns [expr {1000.0 / $period_ns}]]
puts "Flow: $flow_mode"
if {$mesi_override ne ""} { puts "MESI_ENABLE: $mesi_override" }
puts "Reports: $report_dir"

# Vivado 2022.2 intermittently crashes its parallel synthesis worker on this
# large XPM-heavy hierarchy ("TclStackFree"/worker died).  A single worker is
# slower but deterministic and preserves the exact same synthesis strategy.
set_param general.maxThreads 1

create_project -in_memory -part $part_name
set_property TARGET_LANGUAGE Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property verilog_define {PPA_NO_MARK_DEBUG} [current_fileset]

foreach source_path [read_active_manifest $rtl_dir] {
    read_verilog $source_path
}

# Read the timing constraint before synthesis so synthesis is timing driven.
set xdc_path [file join $report_dir ooc_clock.xdc]
set xdc_fd [open $xdc_path w]
puts $xdc_fd [format {create_clock -name ooc_clk -period %.3f [get_ports {%s}]} \
    $period_ns $clock_port]
# Give the OOC clock a legal clock-buffer origin so routed clock delay/skew is
# modeled instead of silently omitted. The final integrated run remains the
# authority because its real top-level clock tree can use another BUFG site.
puts $xdc_fd [format {set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports {%s}]} \
    $clock_port]
close $xdc_fd
read_xdc $xdc_path

set synth_args [list -top $top_name -part $part_name -mode out_of_context \
                     -flatten_hierarchy rebuilt]
if {$mesi_override ne ""} {
    lappend synth_args -generic "MESI_ENABLE=$mesi_override"
}
synth_design {*}$synth_args

set mark_debug_nets [get_nets -quiet -hier -filter {MARK_DEBUG == 1}]
set mark_debug_count [llength $mark_debug_nets]
if {$mark_debug_count != 0} {
    set debug_report [open [file join $report_dir unexpected_mark_debug_nets.rpt] w]
    foreach debug_net $mark_debug_nets { puts $debug_report $debug_net }
    close $debug_report
    error "PPA build retained $mark_debug_count MARK_DEBUG nets"
}

if {[llength [get_ports -quiet $clock_port]] != 1} {
    error "Expected one top-level clock port '$clock_port' on $top_name"
}
if {[llength [get_clocks -quiet ooc_clk]] != 1} {
    error "OOC clock constraint was not applied to $top_name/$clock_port"
}

# Detailed synthesis reports temporarily add almost 1 GiB to Vivado's resident
# set on this hierarchy.  In implementation mode they are redundant with the
# routed reports and can make the placer fail for lack of memory.  Keep them for
# synth-only characterization; defer all reporting until after route otherwise.
if {$flow_mode eq "synth"} {
    report_utilization -file [file join $report_dir utilization_synth.rpt]
    report_utilization -hierarchical -hierarchical_depth 5 \
        -file [file join $report_dir utilization_hierarchical_synth.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -check_timing_verbose -max_paths 20 \
        -file [file join $report_dir timing_synth.rpt]
}

set route_status "not-run"
if {$flow_mode eq "impl"} {
    opt_design
    place_design
    phys_opt_design
    route_design
    set route_status "complete"

    report_utilization -file [file join $report_dir utilization_route.rpt]
    report_utilization -hierarchical -hierarchical_depth 5 \
        -file [file join $report_dir utilization_hierarchical_route.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -check_timing_verbose -max_paths 20 \
        -file [file join $report_dir timing_route.rpt]
    report_route_status -file [file join $report_dir route_status.rpt]
    report_methodology -file [file join $report_dir methodology_route.rpt]
    write_checkpoint -force [file join $report_dir ${top_name}_route.dcp]
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path  [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_slack [timing_value $setup_path SLACK -999.0]
set hold_slack  [timing_value $hold_path  SLACK -999.0]
set effective_period [expr {$period_ns - $setup_slack}]
set estimated_fmax_mhz [expr {$effective_period > 0.0 ? 1000.0 / $effective_period : 0.0}]

set lut_count    [cell_count {REF_NAME =~ LUT*}]
set ff_count     [cell_count {REF_NAME =~ FD*}]
set ramb36_count [cell_count {REF_NAME =~ RAMB36E*}]
set ramb18_count [cell_count {REF_NAME =~ RAMB18E*}]
set ramd64_count [cell_count {REF_NAME == RAMD64E}]
set bram_tiles   [expr {$ramb36_count + (($ramb18_count + 1) / 2)}]

set summary_path [file join $report_dir summary.md]
set summary [open $summary_path w]
puts $summary "# OOC PPA: `$top_name`"
puts $summary ""
puts $summary "- Generated: [clock format [clock seconds]]"
puts $summary "- Part: `$part_name`"
puts $summary "- Flow: `$flow_mode`"
if {$mesi_override ne ""} { puts $summary "- MESI_ENABLE: `$mesi_override`" }
puts $summary [format "- Target: `%.3f ns` (`%.3f MHz`) on `%s`" \
    $period_ns [expr {1000.0 / $period_ns}] $clock_port]
puts $summary "- Route status: `$route_status`"
puts $summary "- MARK_DEBUG nets after synthesis: `$mark_debug_count`"
puts $summary [format "- Setup WNS: `%.3f ns`" $setup_slack]
puts $summary [format "- Hold slack: `%.3f ns`" $hold_slack]
puts $summary [format "- Timing-derived Fmax estimate: `%.3f MHz`" $estimated_fmax_mhz]
puts $summary "- Critical startpoint: `[timing_value $setup_path STARTPOINT_PIN unavailable]`"
puts $summary "- Critical endpoint: `[timing_value $setup_path ENDPOINT_PIN unavailable]`"
puts $summary ""
puts $summary "| Resource | Count |"
puts $summary "|---|---:|"
puts $summary "| LUT cells | $lut_count |"
puts $summary "| FF cells | $ff_count |"
puts $summary "| RAMB36 | $ramb36_count |"
puts $summary "| RAMB18 | $ramb18_count |"
puts $summary "| BRAM tiles (conservative) | $bram_tiles |"
puts $summary "| RAMD64E | $ramd64_count |"
puts $summary ""
puts $summary "> The Fmax value is derived from this routed/ synthesized timing result. "
puts $summary "> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax."
close $summary

set csv_path [file join $report_dir summary.csv]
set csv [open $csv_path w]
puts $csv "top,part,flow,clock_port,target_period_ns,target_mhz,wns_ns,hold_slack_ns,estimated_fmax_mhz,lut,ff,ramb36,ramb18,bram_tiles,ramd64,mark_debug_nets,report_dir"
puts $csv [join [list $top_name $part_name $flow_mode $clock_port \
    [format %.3f $period_ns] [format %.3f [expr {1000.0 / $period_ns}]] \
    [format %.3f $setup_slack] [format %.3f $hold_slack] \
    [format %.3f $estimated_fmax_mhz] $lut_count $ff_count $ramb36_count \
    $ramb18_count $bram_tiles $ramd64_count $mark_debug_count $report_dir] ,]
close $csv

puts [format "OOC_PPA_RESULT top=%s WNS=%.3fns estimated_Fmax=%.3fMHz LUT=%d FF=%d BRAM_tiles=%d" \
    $top_name $setup_slack $estimated_fmax_mhz $lut_count $ff_count $bram_tiles]
puts "Evidence: $summary_path"
close_project

