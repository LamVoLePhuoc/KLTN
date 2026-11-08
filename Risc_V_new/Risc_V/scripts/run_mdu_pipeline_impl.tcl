# Rebuild the active four-core design, enforce the cache-resource gate, then
# emit post-synthesis and post-route reports in a timestamped directory.
# Run from the Vivado Tcl Console with:
#   source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_mdu_pipeline_impl.tcl}

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_xpr [file join $project_dir Risc_V.xpr]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir  [file join $project_dir reports "vivado-mdu-pipeline-$stamp"]
file mkdir $report_dir

set target_period_ns 9.800
set target_frequency_mhz [expr {1000.0 / $target_period_ns}]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_xpr
}

# Implementation-only floorplan: keep the 139-tile shared L2 and its MSI
# controller in the smallest contiguous xc7z030 clock-region rectangle that
# can hold the complete banked store.  Register it here so command-line runs
# cannot silently omit the physical constraint from constrs_1.
set l2_floorplan_xdc [file normalize \
    [file join $project_dir constraints l2_cluster_floorplan.xdc]]
if {![file exists $l2_floorplan_xdc]} {
    error "Missing L2 floorplan constraint: $l2_floorplan_xdc"
}
set floorplan_files [get_files -quiet $l2_floorplan_xdc]
if {[llength $floorplan_files] == 0} {
    add_files -fileset constrs_1 -norecurse $l2_floorplan_xdc
    set floorplan_files [get_files -quiet $l2_floorplan_xdc]
}
set_property USED_IN_SYNTHESIS false $floorplan_files
set_property USED_IN_IMPLEMENTATION true $floorplan_files
puts "L2 floorplan: $l2_floorplan_xdc"

set mdu_source [file normalize [file join $project_dir rtl core execute_stage.v]]
if {[llength [get_files -quiet $mdu_source]] == 0} {
    error "Active project does not contain $mdu_source"
}

puts "=== Active four-core cache-controller implementation ==="
puts "Project: [get_property NAME [current_project]]"
puts "Reports: $report_dir"
puts [format "Timing target: %.3f ns (%.3f MHz)" $target_period_ns $target_frequency_mhz]

# Discard only generated run products. Project sources and the previous
# reports/vivado-active baseline are left untouched for comparison.
if {[llength [get_designs -quiet]] > 0} {
    close_design
}
update_compile_order -fileset sources_1

# cpu0 is synthesized out of context and stitched into the top-level as a
# checkpoint. Rebuilding only synth_1 could silently reuse an old CPU DCP, so
# this dependency must run first. A regenerated Block Design can retain the
# OOC_HIERARCHICAL XCI while dropping its run object; recreate that generated
# run automatically instead of requiring a particular project-history state.
set expected_cpu_synth_run soc_4core_trial_cpu0_0_synth_1
set cpu_synth_candidates [get_runs -quiet $expected_cpu_synth_run]
if {[llength $cpu_synth_candidates] == 0} {
    set cpu_synth_candidates [get_runs -quiet *soc_4core_trial_cpu0_0*synth*]
}
if {[llength $cpu_synth_candidates] == 0} {
    puts "CPU OOC run is missing; recreating it from the managed XCI..."
    set cpu_xci [get_files -quiet *soc_4core_trial_cpu0_0.xci]
    set bd_file [get_files -quiet */soc_4core_trial.bd]
    if {[llength $cpu_xci] == 0 && [llength $bd_file] > 0} {
        set cpu_xci [get_files -quiet -of_objects $bd_file *soc_4core_trial_cpu0_0.xci]
    }
    if {[llength $cpu_xci] == 0} {
        if {[llength $bd_file] == 0} {
            error "Neither the cpu0 XCI nor soc_4core_trial.bd is present in sources_1"
        }
        generate_target -force all $bd_file
        update_compile_order -fileset sources_1
        set cpu_xci [get_files -quiet -of_objects $bd_file *soc_4core_trial_cpu0_0.xci]
    }
    if {[llength $cpu_xci] == 0} {
        error "Could not locate the managed cpu0 XCI after regenerating BD targets"
    }
    create_ip_run $cpu_xci
    set cpu_synth_candidates [get_runs -quiet $expected_cpu_synth_run]
    if {[llength $cpu_synth_candidates] == 0} {
        set cpu_synth_candidates [get_runs -quiet *soc_4core_trial_cpu0_0*synth*]
    }
}
if {[llength $cpu_synth_candidates] != 1} {
    error "Expected exactly one cpu0 OOC synthesis run, found: $cpu_synth_candidates"
}
set cpu_synth_run [lindex $cpu_synth_candidates 0]
puts "CPU OOC run: $cpu_synth_run"

# Module-reference source edits are not part of the XCI cache key in this
# Vivado flow. Remove only the matching CPU entry before launching its OOC run;
# otherwise reset_run can silently copy the old DCP back from the project cache.
# This is generated data and the fresh synthesis recreates it under the same ID.
set cpu_ip [get_ips -quiet soc_4core_trial_cpu0_0]
if {[llength $cpu_ip] > 0} {
    set stale_cpu_cache_id [config_ip_cache -cache_has_match $cpu_ip]
    if {$stale_cpu_cache_id ne ""} {
        puts "Removing stale CPU IP cache entry: $stale_cpu_cache_id"
        config_ip_cache -remove $cpu_ip
    }
} else {
    puts "No standalone get_ips object for cpu0; the recreated OOC run will be rebuilt directly."
}
reset_run $cpu_synth_run
launch_runs $cpu_synth_run -jobs 4
wait_on_run $cpu_synth_run

set cpu_synth_status [get_property STATUS [get_runs $cpu_synth_run]]
puts "$cpu_synth_run: $cpu_synth_status"
if {[string first "Complete" $cpu_synth_status] < 0} {
    error "$cpu_synth_run did not complete successfully"
}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "synth_1 did not complete successfully"
}

open_run synth_1
set target_clock [get_clocks -quiet sys_clk_in]
if {[llength $target_clock] != 1} {
    error "Expected exactly one sys_clk_in timing clock, found: $target_clock"
}
set applied_period_ns [get_property PERIOD $target_clock]
if {abs($applied_period_ns - $target_period_ns) > 0.001} {
    error [format "Constraint mismatch: requested %.3f ns, design uses %.3f ns" \
        $target_period_ns $applied_period_ns]
}
puts [format "Verified applied sys_clk_in period: %.3f ns" $applied_period_ns]
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $report_dir utilization_hierarchical_synth.rpt]

# Fail before the expensive implementation step if a cache array regresses to
# distributed RAM.  The xc7z030 has 26,600 compatible LUT-memory sites and 265
# RAMB36-equivalent tiles.  RAMB18 pairs conservatively count as one tile.
set synth_ramd64 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMD64E}]]
set synth_ramb36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set synth_ramb18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
set synth_bram_tiles [expr {$synth_ramb36 + (($synth_ramb18 + 1) / 2)}]
set resource_gate [open [file join $report_dir resource_gate.txt] w]
puts $resource_gate "RAMD64E=$synth_ramd64 (limit 26600)"
puts $resource_gate "RAMB36E1=$synth_ramb36"
puts $resource_gate "RAMB18E1=$synth_ramb18"
puts $resource_gate "Conservative BRAM tiles=$synth_bram_tiles (limit 265)"
close $resource_gate
puts "Resource gate: RAMD64E=$synth_ramd64, RAMB36E1=$synth_ramb36, RAMB18E1=$synth_ramb18"
if {$synth_ramd64 > 26600} {
    close_design
    error "Distributed RAM exceeds xc7z030 capacity; inspect resource_gate.txt and L2 inference."
}
if {$synth_bram_tiles > 265} {
    close_design
    error "Block RAM exceeds xc7z030 capacity; inspect resource_gate.txt."
}
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir timing_synth.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "impl_1 did not complete successfully"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization_route.rpt]
report_utilization -hierarchical -hierarchical_depth 6 \
    -file [file join $report_dir utilization_hierarchical_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 \
    -file [file join $report_dir timing_route.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_drc -file [file join $report_dir drc_route.rpt]
report_methodology -file [file join $report_dir methodology_route.rpt]
report_power -file [file join $report_dir power_route.rpt]

set pblock_report [open [file join $report_dir l2_pblock_route.txt] w]
set l2_pblock [get_pblocks -quiet pblock_l2_cluster]
if {[llength $l2_pblock] == 1} {
    puts $pblock_report "GRID_RANGES=[get_property GRID_RANGES $l2_pblock]"
    puts $pblock_report "CELL_COUNT=[llength [get_cells -quiet -of_objects $l2_pblock]]"
} else {
    puts $pblock_report "ERROR: pblock_l2_cluster was not present after route"
}
close $pblock_report

set summary [open [file join $report_dir summary.txt] w]
puts $summary "Active four-core cache-controller implementation"
puts $summary "Generated: [clock format [clock seconds]]"
puts $summary [format "Timing target: %.3f ns (%.3f MHz)" $target_period_ns $target_frequency_mhz]
puts $summary [format "Applied sys_clk_in period: %.3f ns" $applied_period_ns]
puts $summary "$cpu_synth_run: $cpu_synth_status"
puts $summary "synth_1: $synth_status"
puts $summary "impl_1:  $impl_status"

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] > 0} {
    puts $summary "Post-route WNS: [get_property SLACK $setup_path] ns"
    puts $summary "Critical startpoint: [get_property STARTPOINT_PIN $setup_path]"
    puts $summary "Critical endpoint:   [get_property ENDPOINT_PIN $setup_path]"
}

set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $hold_path] > 0} {
    puts $summary "Post-route WHS: [get_property SLACK $hold_path] ns"
}

puts $summary "Detailed reports:"
puts $summary "  resource_gate.txt"
puts $summary "  utilization_synth.rpt"
puts $summary "  utilization_hierarchical_synth.rpt"
puts $summary "  timing_synth.rpt"
puts $summary "  utilization_route.rpt"
puts $summary "  utilization_hierarchical_route.rpt"
puts $summary "  timing_route.rpt"
puts $summary "  route_status.rpt"
puts $summary "  drc_route.rpt"
puts $summary "  methodology_route.rpt"
puts $summary "  power_route.rpt"
puts $summary "  l2_pblock_route.txt"
close $summary

# A completed route is not a timing pass.  Fail explicitly when either
# setup or hold slack is negative so a tighter-clock experiment cannot be
# reported as an Fmax improvement unless the routed design really meets it.
set setup_slack [expr {[llength $setup_path] > 0 ? [get_property SLACK $setup_path] : -1.0}]
set hold_slack  [expr {[llength $hold_path]  > 0 ? [get_property SLACK $hold_path]  : -1.0}]
if {$setup_slack < 0.0 || $hold_slack < 0.0} {
    error [format "Post-route timing FAILED at %.3f ns: WNS=%.3f ns, WHS=%.3f ns" \
        $target_period_ns $setup_slack $hold_slack]
}

puts "=== COMPLETE ==="
puts "Read [file join $report_dir summary.txt]"
puts "Compare against [file join $project_dir reports vivado-active]"

