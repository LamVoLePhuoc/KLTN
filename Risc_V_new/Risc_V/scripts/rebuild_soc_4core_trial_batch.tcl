# Batch entry point for rebuilding the active four-core Block Design.
set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_xpr [file join $project_dir Risc_V.xpr]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_xpr
}

source [file join $script_dir build_soc_4core_trial.tcl]
close_project
