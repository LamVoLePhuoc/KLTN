# Standalone L2 synthesis/resource gate.
# Usage:
#   vivado -mode batch -source scripts/check_l2_bram_synth.tcl
#
# This intentionally uses an in-memory project so it can run while the main
# Block Design project is closed or open without modifying its run state.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir  [file join $project_dir reports "l2-bram-synth-$stamp"]
file mkdir $report_dir

create_project -in_memory -part xc7z030fbv676-1
read_verilog [file join $project_dir rtl cache l2_cache.v]
synth_design -top l2_cache -part xc7z030fbv676-1 -flatten_hierarchy rebuilt

report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]

set ramb36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set ramd64_count [llength [get_cells -hier -filter {REF_NAME == RAMD64E}]]
set lut_count    [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
set bram_bits    [expr {$ramb36_count * 36864 + $ramb18_count * 18432}]
set l2_data_bits [expr {512 * 1024 * 8}]

set summary [file join $report_dir summary.txt]
set fd [open $summary w]
puts $fd "L2 standalone synthesis resource gate"
puts $fd "PART=xc7z030fbv676-1"
puts $fd "RAMB36E1=$ramb36_count"
puts $fd "RAMB18E1=$ramb18_count"
puts $fd "BRAM_BITS=$bram_bits (required $l2_data_bits)"
puts $fd "RAMD64E=$ramd64_count"
puts $fd "LUT=$lut_count"
close $fd

puts "=== L2 BRAM SYNTHESIS CHECK ==="
puts "RAMB36E1=$ramb36_count RAMB18E1=$ramb18_count BRAM_BITS=$bram_bits RAMD64E=$ramd64_count LUT=$lut_count"
puts "Evidence: $summary"

# Check capacity rather than a fixed primitive count: Vivado can pack a
# 4096x256 way more efficiently as 28 RAMB36 + 1 RAMB18, whereas the former
# 16384x32 organization used 32 RAMB36 per quarter of the same 512-KB store.
if {$bram_bits < $l2_data_bits} {
    error "L2 data did not map enough block-RAM capacity for 512 KB."
}
if {$ramd64_count >= 26600} {
    error "L2 still exceeds the xc7z030 distributed-RAM capacity."
}

puts "L2_BRAM_SYNTH_TB: PASS"
