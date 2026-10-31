# Active cache-controller architecture regression for Vivado XSIM.
# Run from the Vivado Tcl Console:
#   source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_active_cache_xsim.tcl}
#
# Only rtl/files.f is compiled. Translation/TLB/PTW sources and the eight
# legacy Sv32 testbenches are deliberately excluded from this result.

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set sim_dir     [file join $project_dir sim]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir  [file join $project_dir reports "xsim-active-cache-$stamp"]
file mkdir $report_dir

set tests {
    {tb_ahb_error_sideband.v       tb_ahb_error_sideband       {AHB_ERROR_SIDEBAND_TB: PASS}}
    {tb_ahb_uncached.v             tb_ahb_uncached             {AHB_UNCACHED_TB: PASS}}
    {tb_axi_request_hold.v         tb_axi_request_hold         {AXI_REQUEST_HOLD_TB: PASS}}
    {tb_boot_ctrl.v                tb_boot_ctrl                {BOOT_CTRL_TB: PASS}}
    {tb_cache_amo.v                tb_cache_amo                {CACHE_AMO_TB: PASS}}
    {tb_cache_error_path.v         tb_cache_error_path         {CACHE_ERROR_PATH_TB: PASS}}
    {tb_cache_fence_i.v            tb_cache_fence_i            {CACHE_FENCE_I_TB: PASS}}
    {tb_cache_lrsc.v               tb_cache_lrsc               {CACHE_LRSC_TB: PASS}}
    {tb_cache_lrsc_snoop.v         tb_cache_lrsc_snoop         {CACHE_LRSC_SNOOP_TB: PASS}}
    {tb_cache_maintenance.v        tb_cache_maintenance        {CACHE_MAINTENANCE_TB: PASS}}
    {tb_cache_uncached.v           tb_cache_uncached           {CACHE_UNCACHED_TB: PASS}}
    {tb_coherence.v                tb_coherence                {MSI_COHERENCE_TB: PASS}}
    {tb_coherence_ahb.v            tb_coherence_ahb            {MSI_COHERENCE_AHB_TB: PASS}}
    {tb_coherence_error.v          tb_coherence_error          {COHERENCE_ERROR_TB: PASS}}
    {tb_coherence_watchdog.v       tb_coherence_watchdog       {CACHE_WATCHDOG_TB: PASS}}
    {tb_core_instruction_legality.v tb_core_instruction_legality {CORE_INSTRUCTION_LEGALITY_TB: PASS}}
    {tb_core_rv32ima_isa.v         tb_core_rv32ima_isa         {CORE_RV32IMA_ISA_TB: PASS}}
    {tb_csr_access_fault.v         tb_csr_access_fault         {CSR_ACCESS_FAULT_TB: PASS}}
    {tb_csr_priv.v                 tb_csr_priv                 {CSR_PRIV_TB: PASS}}
    {tb_csr_trap.v                 tb_csr_trap                 {CSR_TRAP_TB: PASS}}
    {tb_dma_end_to_end.v           tb_dma_end_to_end           {DMA_END_TO_END_TB: PASS}}
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
puts "=== XSIM active cache-controller regression ==="
puts "Report directory: $report_dir"

if {[catch {exec xvlog -work xil_defaultlib {*}$rtl_files} compile_output]} {
    set fd [open [file join $report_dir compile-rtl.log] w]
    puts $fd $compile_output
    close $fd
    puts stderr $compile_output
    cd $old_dir
    error "Active RTL compile failed. See $report_dir/compile-rtl.log"
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
            # Every test is self-terminating; run to its own finish condition.
            catch {exec xsim $snapshot -R} run_output
            if {[string first $marker $run_output] >= 0 &&
                [string first "_TB: FAIL" $run_output] < 0} {
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
    puts [format "%-34s %s" $top $result]
}

set summary [file join $report_dir summary.md]
set fd [open $summary w]
puts $fd "# Vivado XSIM active cache-controller regression"
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
puts $fd "> Scope: direct physical addressing + core/cache/coherence/bus/boot/DMA. Legacy Sv32 is excluded."
close $fd

cd $old_dir
puts "=== XSIM ACTIVE RESULT: $pass_count/[llength $tests] PASS ==="
puts "Evidence: $summary"
if {$pass_count != [llength $tests]} {
    error "One or more active tests failed. Inspect the run logs above."
}
