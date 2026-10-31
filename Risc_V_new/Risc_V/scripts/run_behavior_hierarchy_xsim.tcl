# Behavioral verification ladder for the active physical-address system.
# No synthesis or implementation is launched by this script.
#
# Vivado Tcl Console:
#   source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_behavior_hierarchy_xsim.tcl}

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dir     [file join $project_dir rtl]
set sim_dir     [file join $project_dir sim]
set stamp       [clock format [clock seconds] -format "%Y%m%d-%H%M%S"]
set report_dir  [file join $project_dir reports "xsim-behavior-hierarchy-$stamp"]
file mkdir $report_dir

# Ordered from the smallest architectural boundary to the board-facing RTL
# boundary.  The last two tests are intentionally full four-core hierarchies.
set tests {
    {L0_CORE       tb_core_rv32ima_isa.v              tb_core_rv32ima_isa              {CORE_RV32IMA_ISA_TB: PASS}}
    {L1_CORE_L1    tb_core_l1_physical_subsystem.v    tb_core_l1_physical_subsystem    {CORE_L1_PHYSICAL_SUBSYSTEM_TB: PASS}}
    {L2_CACHE_AHB  tb_coherence_ahb.v                 tb_coherence_ahb                 {MSI_COHERENCE_AHB_TB: PASS}}
    {L3_4CORE_SOC  tb_quad_core_soc_ahb_behavior.v    tb_quad_core_soc_ahb_behavior    {QUAD_CORE_SOC_AHB_BEHAVIOR_TB: PASS}}
    {L4_BOARD_AXI  tb_quad_core_axi_ahb_behavior.v    tb_quad_core_axi_ahb_behavior    {QUAD_CORE_AXI_AHB_BEHAVIOR_TB: PASS}}
}

set rtl_files {}
set manifest [open [file join $rtl_dir files.f] r]
while {[gets $manifest line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend rtl_files [file normalize [file join $rtl_dir $line]]
}
close $manifest

# Scope guard: the historical Sv32 sources may remain in the repository for
# reference, but they must never re-enter the active physical-system manifest.
set forbidden_translation_sources {
    mmu/mmu_top.v
    mmu/mmu_core_wrapper.v
    mmu/mmu_tlb.v
    mmu/mmu_super_tlb.v
    mmu/mmu_ptw.v
    mmu/mmu_region_decode.v
    mmu/mmu_ip_wrapper.v
}
set manifest_text [join $rtl_files "\n"]
foreach forbidden $forbidden_translation_sources {
    set forbidden_abs [file normalize [file join $rtl_dir $forbidden]]
    if {[string first $forbidden_abs $manifest_text] >= 0} {
        error "Physical-system scope violation: rtl/files.f includes $forbidden"
    }
}

set old_dir [pwd]
cd $report_dir
puts "=== Physical-system behavioral verification ladder ==="
puts "No synthesis will be run."
puts "Reports: $report_dir"

if {[catch {exec xvlog -work xil_defaultlib {*}$rtl_files} rtl_output]} {
    set fd [open [file join $report_dir compile-rtl.log] w]
    puts $fd $rtl_output
    close $fd
    cd $old_dir
    error "RTL compile failed. See $report_dir/compile-rtl.log"
}
set fd [open [file join $report_dir compile-rtl.log] w]
puts $fd $rtl_output
close $fd

set results {}
set pass_count 0
set dut_fail_count 0
set tool_error_count 0

foreach test $tests {
    lassign $test level tb_file top marker
    set compile_log [file join $report_dir "compile-$top.log"]
    set elab_log    [file join $report_dir "elab-$top.log"]
    set run_log     [file join $report_dir "run-$top.log"]
    set snapshot    "${top}_behav"

    set status "TOOL_ERROR"
    set compile_ok 1
    if {[catch {exec xvlog -work xil_defaultlib [file join $sim_dir $tb_file]} tb_compile_output]} {
        set compile_ok 0
    }
    set fd [open $compile_log w]
    puts $fd $tb_compile_output
    close $fd

    if {$compile_ok} {
        # Full 4-core elaboration is memory intensive in XSIM 2022.2.  Debug
        # instrumentation is disabled because these are self-checking gates;
        # rerun one failing test interactively with -debug typical for waves.
        catch {exec xelab -debug off -mt off "xil_defaultlib.$top" -snapshot $snapshot} elab_output
        set fd [open $elab_log w]
        puts $fd $elab_output
        close $fd

        set snapshot_exe [file join $report_dir xsim.dir $snapshot xsimk.exe]
        if {[file exists $snapshot_exe]} {
            catch {exec xsim $snapshot -R} run_output
            set fd [open $run_log w]
            puts $fd $run_output
            close $fd
            if {[string first $marker $run_output] >= 0 &&
                [string first "_TB: FAIL" $run_output] < 0} {
                set status "PASS"
                incr pass_count
            } else {
                set status "DUT_FAIL"
                incr dut_fail_count
            }
        } else {
            set fd [open $run_log w]
            puts $fd "Simulation not started because XSIM elaboration did not create $snapshot_exe"
            close $fd
            incr tool_error_count
        }
    } else {
        set fd [open $elab_log w]
        puts $fd "Testbench compile failed; elaboration skipped."
        close $fd
        set fd [open $run_log w]
        puts $fd "Simulation not started because testbench compilation failed."
        close $fd
        incr tool_error_count
    }

    lappend results [list $level $top $status]
    puts [format "%-14s %-38s %s" $level $top $status]
}

set summary [file join $report_dir summary.md]
set fd [open $summary w]
puts $fd "# Physical-system behavioral verification"
puts $fd ""
puts $fd "Generated: [clock format [clock seconds]]"
puts $fd ""
puts $fd "- PASS: $pass_count/[llength $tests]"
puts $fd "- DUT failures: $dut_fail_count"
puts $fd "- Tool/elaboration errors: $tool_error_count"
puts $fd "- Translation-source manifest guard: PASS"
puts $fd ""
puts $fd "| Level | Test | Status |"
puts $fd "|---|---|---:|"
foreach result $results {
    lassign $result level top status
    puts $fd "| $level | $top | $status |"
}
puts $fd ""
puts $fd "> Scope: direct physical addressing; no TLB/PTW/VA-to-PA translation."
puts $fd "> TOOL_ERROR is kept separate from DUT_FAIL so an EDA installation problem cannot be reported as a design failure."
close $fd

cd $old_dir
puts "=== RESULT: $pass_count/[llength $tests] PASS, $dut_fail_count DUT_FAIL, $tool_error_count TOOL_ERROR ==="
puts "Evidence: $summary"
if {$dut_fail_count != 0 || $tool_error_count != 0} {
    error "Behavioral gate is not clear. Inspect summary and per-test logs."
}

