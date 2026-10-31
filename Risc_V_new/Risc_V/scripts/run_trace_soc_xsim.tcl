# Focused diagnostic run for the four-core same-line coherence scenario.
set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set sim_dir     [file join $project_dir sim]
set work_dir    [file join $project_dir reports xsim-soc-coherence-trace]
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
exec xvlog -work xil_defaultlib -d COHERENCE_TRACE \
    [file join $sim_dir tb_quad_core_soc_ahb_behavior.v]
exec xelab -debug typical -mt off xil_defaultlib.tb_quad_core_soc_ahb_behavior \
    -snapshot tb_quad_core_soc_ahb_behavior_trace
set output [exec xsim tb_quad_core_soc_ahb_behavior_trace -R]
set fd [open [file join $work_dir trace.log] w]
puts $fd $output
close $fd
puts $output
puts "Trace: [file join $work_dir trace.log]"
cd $old_dir
