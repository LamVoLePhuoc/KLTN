# Usage from Vivado Tcl or batch mode:
#   source scripts/run_one_xsim.tcl -notrace
# This script reads variables ONE_TB_FILE, ONE_TB_TOP and ONE_TB_MARKER when
# sourced interactively.  In batch mode pass them as three -tclargs values.
set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set sim_dir     [file join $project_dir sim]

if {$argc >= 3} {
    set ONE_TB_FILE   [lindex $argv 0]
    set ONE_TB_TOP    [lindex $argv 1]
    set ONE_TB_MARKER [lindex $argv 2]
}
foreach required {ONE_TB_FILE ONE_TB_TOP ONE_TB_MARKER} {
    if {![info exists $required]} {
        error "Set ONE_TB_FILE, ONE_TB_TOP and ONE_TB_MARKER, or pass three -tclargs values."
    }
}

set work_dir [file join $project_dir reports "xsim-one-$ONE_TB_TOP"]
file mkdir $work_dir
set rtl_files {}
set manifest [open [file join $rtl_dir files.f] r]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend rtl_files [file normalize [file join $rtl_dir $line]]
}
close $manifest

set old_dir [pwd]
cd $work_dir
exec xvlog -work xil_defaultlib {*}$rtl_files
exec xvlog -work xil_defaultlib [file join $sim_dir $ONE_TB_FILE]
exec xelab -debug typical -mt off "xil_defaultlib.$ONE_TB_TOP" \
    -snapshot "${ONE_TB_TOP}_behav"
set output [exec xsim "${ONE_TB_TOP}_behav" -R]
set fd [open [file join $work_dir run.log] w]
puts $fd $output
close $fd
puts $output
cd $old_dir
if {[string first $ONE_TB_MARKER $output] < 0 ||
    [string first "_TB: FAIL" $output] >= 0} {
    error "$ONE_TB_TOP failed. See [file join $work_dir run.log]"
}
puts "=== ONE TEST PASS: $ONE_TB_TOP ==="
