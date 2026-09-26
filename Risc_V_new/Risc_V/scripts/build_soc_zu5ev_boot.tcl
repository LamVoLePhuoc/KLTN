#===============================================================
# build_soc_zu5ev_boot.tcl
#
# THIRD architecture trial fit -- adds the Genesys ZU-5EV SD-card boot
# flow (Hướng 3 / Direction 3, see Risc_V_new/README.md) on top of the
# 4-core system from build_soc_4core_trial.tcl. This is a separate,
# new script -- it does NOT modify build_soc_mmu_trial.tcl or
# build_soc_4core_trial.tcl, per instruction.
#
# WHY A ZYNQ PS SHOWS UP HERE AT ALL (read this before wiring
# anything else): Genesys ZU-5EV's on-board microSD card is wired to
# the Zynq UltraScale+ PS's own hardened SD controller (MIO pins) --
# confirmed via Digilent's own documented boot flow for this board
# (FSBL + BOOT.BIN read from SD by the PS's boot ROM; see README's
# boot-flow section for sources). There is NO electrical path from
# the PL fabric to the SD card's pins on this board -- a PL-only
# RISC-V core cannot bit-bang the card directly, no matter how the
# RTL is written. The only correct architecture is therefore:
#   PS boots from SD (already works out of the box on this board) ->
#   a small PS-side loader reads the RISC-V program from the SD
#   card's FAT32 filesystem into DRAM -> PS writes boot_ctrl.v's GO
#   bit -> RISC-V cores (held in reset until then) start fetching.
# See rtl/boot/boot_ctrl.v and rtl/soc/quad_core_axi_wrapper_ahb_bootable.v's
# headers for the PL-side half of this; see README for the PS-side
# loader software (a completely different toolchain -- ARM bare-metal
# / FSBL, not something this repo hand-assembles).
#
# WHAT THIS BUILDS:
#
#   ps0 (zynq_ultra_ps_e)                     axi_interconnect_data
#     M_AXI_HPM0_FPD (GP master) ------S02--\   (3 masters -> 4 slaves)
#                                             |--> M00 -> mem_ctrl (BRAM
#   cpu0 (quad_core_axi_wrapper_ahb_bootable) |          stand-in for DDR)
#     M_AXI -----------------------------S00--|--> M01 -> uart0 (axi_uartlite,
#     S_AXI_BOOT (boot_ctrl's regs) <----------|          bonus/debug only)
#                                              |--> M02 -> dma0/S_AXI_LITE
#   dma0 (axi_cdma)                           |
#     M_AXI ------------------------------S01-/--> M03 -> cpu0/S_AXI_BOOT
#                                                          (boot_ctrl -- see
#                                                          below: reachable
#                                                          from BOTH cpu0
#                                                          AND ps0)
#
# boot_ctrl (inside cpu0, see rtl/soc/quad_core_axi_wrapper_ahb_bootable.v)
# is reachable from BOTH cpu0's own M_AXI (RISC-V writes its PASS/FAIL
# result there) and ps0's GP master (PS writes GO, reads the result
# back) -- see boot_ctrl.v's header for why the result is routed
# through here instead of through uart0's physical pins (their
# existence on this board is unconfirmed -- see that header).
#
# DIFFERENCES FROM build_soc_4core_trial.tcl:
#   - cpu0 is quad_core_axi_wrapper_ahb_bootable (NEW -- wraps
#     quad_core_axi_wrapper_ahb + boot_ctrl, gates ARESETN with the GO
#     bit) instead of quad_core_axi_wrapper directly. quad_core_axi_wrapper_ahb
#     is the AHB-Lite SoC variant (quad_core_soc_ahb.v), the FINAL bus
#     choice (README mục 4) -- NOT the direct-wire quad_core_soc.v this
#     script's sibling build_soc_4core_trial.tcl still uses.
#   - A Zynq UltraScale+ PS (zynq_ultra_ps_e) replaces the plain
#     sys_clk/ext_reset_in top-level ports + proc_sys_reset -- the PS
#     is now the clock/reset source for the whole design, same as any
#     real Zynq design (this is also what makes SD boot possible at
#     all -- see above).
#   - New slave: uart0 (axi_uartlite), reachable from cpu0's own M_AXI
#     -- bonus/debug serial output ONLY, use once you've confirmed
#     this board exposes a PL-reachable UART-capable connector (see
#     boot_ctrl.v's header). NOT the automated PASS/FAIL path.
#   - New slave reachable from BOTH cpu0 and ps0: boot_ctrl's
#     S_AXI_BOOT port -- see rtl/boot/boot_ctrl.v.
#   - Still BRAM for mem_ctrl, NOT the PS's real DDR via an HP port --
#     same reasoning as the 1-core/4-core scripts (prove the wiring
#     elaborates first, swap in real DDR once that's confirmed). This
#     means this trial does NOT yet actually prove the SD->DRAM->
#     release-from-reset flow end to end with REAL shared DRAM --
#     that needs an HP port -> mem_ctrl swap as a documented follow-up
#     (see README) once a real Vivado run confirms this much elaborates.
#
# WHY THESE CHOICES: see build_soc_mmu_trial.tcl's header for the
# reasoning that still applies unchanged (BRAM stand-in instead of
# real DDR until confirmed; axi_cdma for the same memory-mapped-copy
# role).
#
# HONESTY NOTE ON THE PS AUTOMATION CALLS BELOW (read before assuming
# a clean run means this is fully correct): apply_bd_automation's
# exact rule names and the Zynq UltraScale+ PS's exact port/pin names
# have shifted slightly across Vivado releases, and this session has
# no Vivado installation to test against (same limitation noted in
# every other script/testbench this whole project -- see README's
# risk register). Every PS-related automation call below is wrapped
# in catch with a clear WARNING telling you exactly what to do by hand
# in the GUI if it doesn't match your Vivado version -- same
# "WARNING-not-abort" convention as the other 2 scripts, just applied
# to a part of the flow (Zynq PS bring-up) that has more version-to-
# version variation than plain AXI peripheral IP does. Do not treat a
# clean run of this script as proof the PS is correctly configured for
# real SD boot -- only actually booting the board is that proof.
#
# CORRECTNESS CAVEAT: same as build_soc_4core_trial.tcl -- this proves
# wiring, not board-level MSI behavior or the boot
# handshake's real timing on hardware.
#
# HOW TO RUN
#   1. Open Risc_V_new/Risc_V/Risc_V.xpr in Vivado, with the Genesys
#      ZU-5EV board part selected for the project (Project Settings ->
#      Board -- needed for the PS automation below to pick correct
#      MIO/DDR defaults; see README for where to get this board file
#      if not already installed).
#   2. In the Tcl Console: source {<path to this file>}
#   3. Read every WARNING printed -- fix that one step by hand in the
#      GUI (Window -> Diagram, right-click the flagged cell -> Run
#      Block Automation / Run Connection Automation) rather than
#      re-running blind.
#   4. Window -> soc_zu5ev_boot in the BD editor; Generate Block
#      Design; Generate Bitstream once satisfied.
#===============================================================

puts "=== build_soc_zu5ev_boot.tcl: starting ==="

if {[llength [get_projects -quiet]] == 0} {
    error "No open Vivado project. Open Risc_V_new/Risc_V/Risc_V.xpr first, then re-source this script."
}

set BD_NAME       "soc_zu5ev_boot"
set MEM_SIZE_BYTES 262144 ;# 256KB -- trial-fit size, same as build_soc_4core_trial.tcl

#---------------------------------------------------------------
# 0. Register RTL sources. cpu0 below instantiates the AHB-Lite SoC
#    variant (quad_core_axi_wrapper_ahb_bootable), per the FINAL
#    architecture decision (README mục 4: AHB-Lite is the chosen bus
#    between the 4 cores and the rest of the system) -- the direct-
#    wire variant's sources (quad_core_soc.v, quad_core_axi_wrapper.v,
#    quad_core_axi_wrapper_bootable.v) are still registered too (kept
#    available in the project as a simpler reference/fallback -- see
#    README mục 4 point 1 for the documented tradeoff between the two),
#    just not what cpu0 below actually instantiates.
#---------------------------------------------------------------
puts "--> [0] Registering RTL sources"

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir     [file normalize [file join $script_dir .. rtl]]

proc find_rtl_source {rtl_root filename} {
    set matches [concat \
        [glob -nocomplain -types f [file join $rtl_root $filename]] \
        [glob -nocomplain -types f [file join $rtl_root * $filename]] \
        [glob -nocomplain -types f [file join $rtl_root * * $filename]]]
    if {[llength $matches] != 1} {
        error "Expected exactly one RTL source named $filename under $rtl_root, found [llength $matches]."
    }
    return [lindex $matches 0]
}

set new_sources {
    mmu_region_decode.v
    mmu_debug_buffer.v
    mmu_super_tlb.v
    l1_icache.v
    l1_dcache.v
    core_l1_wrapper.v
    l2_cache.v
    cache_debug_buffer.v
    coherence_manager.v
    ahb_lite_l1_adapter.v
    ahb_lite_l1_slave_adapter.v
    quad_core_soc_ahb.v
    quad_core_axi_wrapper_ahb.v
    quad_core_soc.v
    quad_core_axi_wrapper.v
    boot_ctrl.v
    quad_core_axi_wrapper_bootable.v
    quad_core_axi_wrapper_ahb_bootable.v
}

foreach f $new_sources {
    set full_path [find_rtl_source $rtl_dir $f]
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -norecurse $full_path
        puts "    added $f"
    } else {
        puts "    already in project: $f"
    }
}
update_compile_order -fileset sources_1

#---------------------------------------------------------------
# 1. Create the block design (always rebuild clean -- see the other
#    2 scripts' step [1] comment for why).
#---------------------------------------------------------------
puts "--> [1] Creating block design '$BD_NAME'"

if {[llength [get_files -quiet "${BD_NAME}.bd"]] > 0} {
    puts "    ${BD_NAME}.bd already exists -- closing and deleting it so this run starts clean"
    catch {close_bd_design [get_bd_designs $BD_NAME]}
    set stale_bd [get_files -quiet "${BD_NAME}.bd"]
    if {$stale_bd ne ""} {
        remove_files -quiet $stale_bd
        catch {file delete -force [get_property NAME $stale_bd]}
    }
}
create_bd_design $BD_NAME

#---------------------------------------------------------------
# 2. Zynq UltraScale+ PS -- the clock/reset source for this whole
#    design (see header: this is what makes SD boot possible at all).
#---------------------------------------------------------------
puts "--> [2] Instantiating ps0 = zynq_ultra_ps_e"

set ps0 [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e ps0]

if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
        -config {apply_board_preset "1"} [get_bd_cells $ps0]
} autoerr]} {
    puts "    WARNING: PS board-preset automation failed or your Vivado's rule name/args differ: $autoerr"
    puts "    Fix by hand: double-click ps0 in the BD Diagram -> Re-customize IP -> on the Board tab,"
    puts "    apply the Genesys ZU-5EV preset (needs the board part set in Project Settings first)."
    puts "    At minimum by hand, also ensure: 1 PL clock enabled (pl_clk0, ~100MHz), 1 AXI GP master"
    puts "    enabled (M_AXI_GP0, for boot_ctrl/uart0), DDR enabled (for a later real-DRAM swap-in)."
}

#---------------------------------------------------------------
# 3. CPU (bootable 4-core wrapper) + DMA
#---------------------------------------------------------------
puts "--> [3] Instantiating cpu0 = quad_core_axi_wrapper_ahb_bootable (AHB-Lite SoC variant -- final choice, see step [0])"

set cpu0 [create_bd_cell -type module -reference quad_core_axi_wrapper_ahb_bootable cpu0]
catch {set_property -dict [list \
    CONFIG.RESET_ADDR0 {32'h00001000} \
    CONFIG.RESET_ADDR1 {32'h00002000} \
    CONFIG.RESET_ADDR2 {32'h00003000} \
    CONFIG.RESET_ADDR3 {32'h00004000} \
] [get_bd_cells cpu0]}

set c_flush [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_MMU_FLUSH]
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells $c_flush]
set_property CONFIG.CONST_VAL   {0} [get_bd_cells $c_flush]
connect_bd_net [get_bd_pins $c_flush/dout] [get_bd_pins cpu0/Mmu_Flush]

set c_cflush [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_CACHE_FLUSH]
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells $c_cflush]
set_property CONFIG.CONST_VAL   {0} [get_bd_cells $c_cflush]
connect_bd_net [get_bd_pins $c_cflush/dout] [get_bd_pins cpu0/Cache_Flush]

puts "--> [3b] Instantiating dma0 = axi_cdma"

set dma0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma:4.1 dma0]
catch {set_property CONFIG.C_INCLUDE_SG {0} [get_bd_cells $dma0]}

#---------------------------------------------------------------
# 4. Memory target (BRAM stand-in for DDR -- see header) and uart0
#    (axi_uartlite -- BONUS/debug peripheral only; the automated
#    PASS/FAIL path goes through boot_ctrl's REG_RESULT instead, see
#    boot_ctrl.v's header for why). Both reachable from cpu0's own
#    M_AXI.
#---------------------------------------------------------------
puts "--> [4] Instantiating mem_ctrl (${MEM_SIZE_BYTES} bytes) and uart0"

set mem_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 mem_ctrl]
set_property -dict [list \
    CONFIG.SINGLE_PORT_BRAM {1} \
    CONFIG.PROTOCOL         {AXI4} \
] [get_bd_cells $mem_ctrl]

set mem_bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 mem_bram]
catch {set_property -dict [list \
    CONFIG.Memory_Type            {Single_Port_RAM} \
    CONFIG.Use_Byte_Write_Enable  {true} \
    CONFIG.Byte_Size              {8} \
    CONFIG.Write_Width_A          {32} \
    CONFIG.Write_Depth_A          [expr {$MEM_SIZE_BYTES / 4}] \
    CONFIG.Enable_A               {Always_Enabled} \
] [get_bd_cells $mem_bram]}
connect_bd_intf_net [get_bd_intf_pins $mem_ctrl/BRAM_PORTA] [get_bd_intf_pins $mem_bram/BRAM_PORTA]

set uart0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart0]
if {[catch {set_property CONFIG.C_BAUDRATE {115200} [get_bd_cells $uart0]} uarterr]} {
    puts "    WARNING: could not set uart0's baud rate property (VLNV/CONFIG name may differ in your"
    puts "    Vivado version): $uarterr -- set it by hand in the IP's Re-customize dialog if needed."
}

#---------------------------------------------------------------
# 5. ONE shared interconnect for everything -- 3 masters (cpu0, dma0,
#    AND ps0's own GP master) -> 4 slaves (mem_ctrl, uart0, dma0's own
#    control port, boot_ctrl). boot_ctrl is reachable from BOTH cpu0
#    and ps0 deliberately: the RISC-V program writes its PASS/FAIL
#    result into boot_ctrl's REG_RESULT (via cpu0/M_AXI), and the PS
#    both writes GO and reads RESULT back (via its own GP master) --
#    see boot_ctrl.v's header for why the result is routed through
#    here rather than through uart0's physical pins.
#---------------------------------------------------------------
puts "--> [5] Instantiating axi_interconnect_data (3 masters -> 4 slaves)"

set ic_data [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_data]
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {4}] [get_bd_cells $ic_data]

# Clock/reset for ic_data, mem_ctrl, mem_bram, uart0, dma0, cpu0, and
# ps0's own GP master port: left to connection automation / by-hand
# fixup below (step 6) rather than hand-wired to a guessed PS pin name
# here -- see the HONESTY NOTE in this file's header on why.

connect_bd_intf_net [get_bd_intf_pins cpu0/M_AXI]  [get_bd_intf_pins $ic_data/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXI] [get_bd_intf_pins $ic_data/S01_AXI]
if {[catch {
    connect_bd_intf_net [get_bd_intf_pins ps0/M_AXI_HPM0_FPD] [get_bd_intf_pins $ic_data/S02_AXI]
} psmasterr]} {
    puts "    WARNING: could not connect ps0's GP master (port name may be M_AXI_HPM0_LPD instead, or"
    puts "    not yet enabled on your PS config): $psmasterr"
    puts "    Fix by hand: check which GP master ps0's Re-customize IP dialog actually enabled, then"
    puts "    connect_bd_intf_net it to axi_interconnect_data/S02_AXI yourself in the Diagram."
}

connect_bd_intf_net [get_bd_intf_pins $ic_data/M00_AXI] [get_bd_intf_pins $mem_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic_data/M01_AXI] [get_bd_intf_pins $uart0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic_data/M02_AXI] [get_bd_intf_pins $dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $ic_data/M03_AXI] [get_bd_intf_pins cpu0/S_AXI_BOOT]

#---------------------------------------------------------------
# 6. Clock/reset fixup. Deliberately NOT attempted via a guessed
#    apply_bd_automation call here (see HONESTY NOTE in the header --
#    the generic "auto-connect this clock/reset pin" Tcl incantation
#    has varied enough across Vivado releases that a wrong guess risks
#    silently wiring something incorrectly, which is worse than just
#    failing loudly). Do this part by hand:
#---------------------------------------------------------------
puts "--> [6] Clock/reset: MUST be finished by hand (see below), not attempted automatically"
puts "    Open the BD Diagram. Every cell added by this script (axi_interconnect_data, mem_ctrl,"
puts "    mem_bram, uart0, dma0, cpu0) still has unconnected ACLK/ARESETN (or S_AXI_ACLK/S_AXI_ARESETN)"
puts "    pins at this point -- right-click each red pin -> Run Connection Automation -> let Vivado"
puts "    pick ps0's PL clock output and matching reset. This is the same manual step any hand-built"
puts "    Zynq design needs in the GUI, not specific to this repo. Doing this on axi_interconnect_data's"
puts "    own ACLK/ARESETN first will usually let Vivado's automation cascade the same choice to most"
puts "    of the other cells in one pass -- but re-check each cell afterward regardless."

#---------------------------------------------------------------
# 7. Address map
#---------------------------------------------------------------
puts "--> [7] Assigning addresses"

catch {assign_bd_address} ; # auto-assign everything first

foreach {space_pin} {cpu0/M_AXI dma0/M_AXI} {
    if {[catch {
        set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $space_pin] -filter {NAME =~ "*mem_ctrl*"}]
        assign_bd_address -offset 0x00000000 -range ${MEM_SIZE_BYTES} -target_address_space [get_bd_addr_spaces $space_pin] $seg -force
    } err]} {
        puts "    WARNING: could not pin mem_ctrl address for $space_pin ($err) -- fix by hand in the Address Editor."
    }
}

puts "    NOTE: boot_ctrl's address as seen from cpu0/M_AXI (RISC-V side, writes REG_RESULT) and its"
puts "    address as seen from ps0's GP master (PS side, writes REG_CTRL's GO bit + reads REG_RESULT)"
puts "    can legitimately be DIFFERENT numbers -- each AXI master has its own address map, assigned"
puts "    independently -- open the Address Editor tab and note BOTH down, you need both for the"
puts "    RISC-V program's linker script / MMIO addresses and the PS-side loader's code (see README)."
puts "    uart0's address (bonus/debug only, see step [4]) is whatever was auto-picked for cpu0/M_AXI."

#---------------------------------------------------------------
# 8. Wrap up
#---------------------------------------------------------------
puts "--> [8] Validating and saving"

regenerate_bd_layout
if {[catch {validate_bd_design} verr]} {
    puts "    WARNING: validate_bd_design reported problems:"
    puts "    $verr"
    puts "    Open the BD in the GUI (Window -> $BD_NAME) to see them highlighted -- most likely an"
    puts "    unconnected ACLK/ARESETN pin left over from step [6]'s automation, see the NOTE there."
} else {
    puts "    validate_bd_design: OK"
}
save_bd_design

set bd_file [get_files "${BD_NAME}.bd"]
if {[catch {make_wrapper -files $bd_file -top} wrap_err]} {
    puts "    NOTE: make_wrapper reported: $wrap_err (a wrapper may already exist -- check sources)"
} else {
    add_files -norecurse [make_wrapper -files $bd_file -top]
    update_compile_order -fileset sources_1
}

puts "=== build_soc_zu5ev_boot.tcl: done ==="
puts ""
puts "Next steps:"
puts "  1. Window -> $BD_NAME -- inspect the diagram, check for red/unconnected pins (expect some if"
puts "     any WARNING printed above -- fix those by hand first)."
puts "  2. Re-read every WARNING above before trusting a clean validate_bd_design."
puts "  3. mem_ctrl is still BRAM, not real DDR -- this trial proves the wiring elaborates, not that"
puts "     SD->DRAM->release-from-reset works end to end on real hardware. See README for the"
puts "     documented follow-up (swap mem_ctrl for a PS HP-port-backed DDR path)."
puts "  4. The PS-side SD loader (FSBL hook or bare-metal app) is described in README, not generated"
puts "     by this script -- it is ARM software (Vitis/PetaLinux toolchain), out of scope for this"
puts "     RTL/Tcl repo."
puts "  5. MSI unit/AHB tests pass in Questa; board-level validation is still required."
