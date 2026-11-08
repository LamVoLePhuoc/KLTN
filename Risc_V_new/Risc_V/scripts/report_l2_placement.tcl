# Report BRAM and local line-slice placement by clock region from a routed DCP.
# Usage:
#   vivado -mode batch -source scripts/report_l2_placement.tcl -tclargs <dcp> ?floorplan_xdc?

if {$argc < 1 || $argc > 2} {
    error "Usage: report_l2_placement.tcl <routed_dcp> ?floorplan_xdc?"
}

set dcp_path [file normalize [lindex $argv 0]]
if {![file exists $dcp_path]} {
    error "Checkpoint does not exist: $dcp_path"
}

open_checkpoint $dcp_path
if {$argc == 2} {
    read_xdc [file normalize [lindex $argv 1]]
    puts "PBLOCK_RANGES=[get_property GRID_RANGES [get_pblocks pblock_l2_cluster]]"
    puts "PBLOCK_CELL_COUNT=[llength [get_cells -quiet -of_objects [get_pblocks pblock_l2_cluster]]]"
}

proc clock_region_of_cell {cell} {
    set loc [get_property LOC $cell]
    if {$loc eq ""} {
        return UNPLACED
    }
    set site [get_sites -quiet $loc]
    set regions [get_clock_regions -quiet -of_objects $site]
    if {[llength $regions] != 1} {
        return UNKNOWN
    }
    return [get_property NAME [lindex $regions 0]]
}

array set available_bram {}
foreach region [get_clock_regions -quiet] {
    set name [get_property NAME $region]
    set available_bram($name) [llength [get_sites -quiet -of_objects $region \
        -filter {NAME =~ RAMB36*}]]
}

array set used_bram {}
set bram_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]
foreach cell $bram_cells {
    set region [clock_region_of_cell $cell]
    if {![info exists used_bram($region)]} { set used_bram($region) 0 }
    incr used_bram($region)
}

array set slice_regs {}
set local_regs [get_cells -quiet -hier -regexp \
    {.*g_line_slice\[[0-7]\].*u_slice.*(lookup_word_q|maint_.*_q).*_reg.*}]
foreach cell $local_regs {
    set region [clock_region_of_cell $cell]
    if {![info exists slice_regs($region)]} { set slice_regs($region) 0 }
    incr slice_regs($region)
}

puts "clock_region,available_ramb36,used_ramb36,local_slice_registers"
foreach name [lsort -dictionary [array names available_bram]] {
    set used [expr {[info exists used_bram($name)] ? $used_bram($name) : 0}]
    set regs [expr {[info exists slice_regs($name)] ? $slice_regs($name) : 0}]
    puts "$name,$available_bram($name),$used,$regs"
}

puts "TOTAL_BRAM_CELLS=[llength $bram_cells]"
puts "TOTAL_LOCAL_SLICE_REGS=[llength $local_regs]"
close_design
