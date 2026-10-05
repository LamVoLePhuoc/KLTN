# MMU weekly regression for Vivado XSIM.
# Run from Vivado Tcl Console:
#   source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_mmu_progress_xsim.tcl}
#
# This flow is intentionally independent of the project's sim_1 fileset. It
# compiles into reports/xsim-mmu-<timestamp>/xsim.dir and leaves the currently
# configured simulation top untouched.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set sim_dir     [file join $project_dir sim]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir  [file join $project_dir reports "xsim-mmu-$stamp"]
file mkdir $report_dir

set tests {
    {tb_mmu_core.v         tb_mmu_core         {MMU_TB: PASS}}
    {tb_mmu_upgrade.v      tb_mmu_upgrade      {MMU_UPGRADE_TB: PASS}}
    {tb_mmu_policy.v       tb_mmu_policy       {MMU_POLICY_TB: PASS}}
    {tb_mmu_advanced.v     tb_mmu_advanced     {MMU_ADVANCED_TB: PASS}}
    {tb_mmu_sfence.v       tb_mmu_sfence       {MMU_SFENCE_TB: PASS}}
    {tb_mmu_context.v      tb_mmu_context      {MMU_CONTEXT_TB: PASS}}
    {tb_mmu_bus_error.v    tb_mmu_bus_error    {MMU_BUS_ERROR_TB: PASS}}
    {tb_csr_mmu_bits.v     tb_csr_mmu_bits     {CSR_MMU_BITS_TB: PASS}}
    {tb_csr_access_fault.v tb_csr_access_fault {CSR_ACCESS_FAULT_TB: PASS}}
}

set rtl_files {}
set manifest [open [file join $rtl_dir files.f] r]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend rtl_files [file normalize [file join $rtl_dir $line]]
}
close $manifest

set old_dir [pwd]
cd $report_dir
puts "=== XSIM MMU regression ==="
puts "Report directory: $report_dir"

if {[catch {exec xvlog -work xil_defaultlib {*}$rtl_files} compile_output]} {
    set fd [open [file join $report_dir compile-rtl.log] w]
    puts $fd $compile_output
    close $fd
    cd $old_dir
    error "RTL compile failed. See $report_dir/compile-rtl.log"
}
set fd [open [file join $report_dir compile-rtl.log] w]
puts $fd $compile_output
close $fd

set results {}
set pass_count 0
foreach test $tests {
    lassign $test tb_file top marker
    set compile_log [file join $report_dir "compile-$top.log"]
    set run_log     [file join $report_dir "run-$top.log"]
    set snapshot    "${top}_behav"

    set compile_ok 1
    if {[catch {exec xvlog -work xil_defaultlib [file join $sim_dir $tb_file]} tb_compile_output]} {
        set compile_ok 0
    }
    set fd [open $compile_log w]
    puts $fd $tb_compile_output
    close $fd

    set run_output ""
    set passed 0
    if {$compile_ok} {
        if {[catch {exec xelab -debug typical "xil_defaultlib.$top" -snapshot $snapshot} elab_output]} {
            append run_output "ELABORATION FAILED\n$elab_output\n"
        } else {
            # -R runs until the testbench calls $finish; no fixed 1000 ns limit.
            catch {exec xsim $snapshot -R} run_output
            if {[string first $marker $run_output] >= 0 &&
                [string first ": FAIL" $run_output] < 0} {
                set passed 1
            }
        }
    } else {
        set run_output "TESTBENCH COMPILE FAILED"
    }

    set fd [open $run_log w]
    puts $fd $run_output
    close $fd
    set result [expr {$passed ? "PASS" : "FAIL"}]
    if {$passed} { incr pass_count }
    lappend results [list $top $result [file tail $run_log]]
    puts [format "%-24s %s" $top $result]
}

set summary [file join $report_dir summary.md]
set fd [open $summary w]
puts $fd "# Vivado XSIM MMU regression"
puts $fd ""
puts $fd "Result: **$pass_count/[llength $tests] PASS**"
puts $fd ""
puts $fd "| Test | Result | Log |"
puts $fd "|---|---:|---|"
foreach result $results {
    lassign $result top status log_name
    puts $fd "| $top | $status | $log_name |"
}
puts $fd ""
puts $fd "> Scope: MMU and directly related CSR tests. tb_csr_priv is not included in these 9 tests."
close $fd

cd $old_dir
puts "=== XSIM MMU RESULT: $pass_count/[llength $tests] PASS ==="
puts "Evidence: $summary"
if {$pass_count != [llength $tests]} {
    error "One or more MMU tests failed. Inspect the run logs above."
}

