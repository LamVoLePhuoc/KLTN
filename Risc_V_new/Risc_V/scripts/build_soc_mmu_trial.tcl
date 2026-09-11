#===============================================================
# build_soc_mmu_trial.tcl
#
# First architecture "trial fit": wires the MMU-integrated core
# (mmu_ip_wrapper.v -> mmu_core_wrapper.v -> RV32IMA core) into a
# real AXI4 SoC skeleton built entirely from Vivado's own IP
# catalog, per the 4-CORE CPU WRAPPER diagram / address_mapping.
#
# WHAT THIS BUILDS (1 core only -- see README for why):
#
#   cpu0 (mmu_ip_wrapper)              dma0 (axi_cdma)
#     M_AXI_IMEM (R-only)                M_AXI
#     M_AXI_DMEM (R/W)                     |
#        \___________________+_____________/
#                             |
#                    axi_interconnect_0
#                     (stand-in for the diagram's
#                      AXI4 system bus)
#          /            |             |            \
#     bram_boot     bram_main      dma0/           intc0/
#     (S_AXI)       (S_AXI)        S_AXI_LITE      s_axi
#     0x0000_0000   0x8000_0000    (ctrl)          (ctrl)
#     64KB, stands  64KB, stands
#     in for "SRAM  in for "Memory
#     Controller +  Controller +
#     SRAM"         DDRAM"
#
# WHY THESE CHOICES (see Risc_V_new/README.md for the full writeup):
#   - No AHB anywhere: Vivado's IP catalog is AXI-centric and ships
#     no generic AHB interconnect IP, so the diagram's AHB segment
#     (4 cores + L2 + coherence unit) isn't buildable from stock IP
#     at all -- only the AXI4 system-bus segment is. This script
#     only trial-fits that AXI4 segment, with ONE core standing in
#     for "the AHB side, eventually", not four.
#   - BRAM stand-ins, not PS7/MIG, for memory: this part xc7z030 is
#     a Zynq device (pin comments in riscv.xdc say "Zedboard", most
#     likely a Z-turn/ZedBoard-clone board) whose real DDR3 is wired
#     to the Zynq PS7's hard memory controller, not a PL-side MIG --
#     using it for real needs the PS7 IP configured with this
#     board's actual DDR part, which needs confirming against the
#     board/board-file before it can be scripted correctly. BRAM
#     avoids that unknown for this first pass; swap to PS7 DDR later
#     once the board is confirmed.
#   - axi_cdma, not axi_dma: the diagram's "DMA CONTROLLER" moves
#     data between two memory-mapped regions (SRAM ctrl <-> memory
#     ctrl), not between memory and an AXI4-Stream device -- axi_cdma
#     is the simpler, more apt fit (one AXI4 master, one AXI4-Lite
#     control slave, no stream endpoints to invent).
#   - Mmu_Enable tied to 0 (bypass, VA=PA) for this first run, not 1:
#     this script does not (yet) load a page table into bram_boot,
#     so enabling translation now would walk a table full of zeros
#     and every access would fault. Flip CONST_MMU_ENABLE's value to
#     1 only after preloading bram_boot with a real table (same
#     layout as Risc_V/sim/tb_mmu_core.v's page table, which you can
#     reuse) via an .mem/.coe init file on the blk_mem_gen instance.
#     With Mmu_Enable=0, this run is really "does the AXI plumbing
#     itself work" (real ARREADY/RVALID/BVALID handshakes, real
#     multi-cycle latency), independent of MMU correctness -- a
#     smaller, separately-checkable claim than "MMU + AXI both work"
#     at once.
#
# HOW TO RUN
#   1. Open Risc_V_new/Risc_V/Risc_V.xpr in Vivado (must already be
#      open -- this script assumes an active project, it does not
#      open one itself).
#   2. In the Tcl Console:  source {<path to this file>}
#   3. Watch the Tcl Console output -- every step below prints a
#      one-line progress message, and every step that could fail on
#      a Vivado-version-specific detail (exact IP version, exact
#      auto-generated address-segment name) is wrapped in `catch`
#      with a clear warning instead of aborting the whole script; if
#      you see a WARNING, open the block design in the GUI and fix
#      that one spot by hand (IP re-customize dialog, or the Address
#      Editor tab) rather than re-running blind.
#   4. When it finishes: Window -> soc_mmu_trial in the BD editor to
#      inspect the diagram; "Generate Block Design"; then either
#      simulate the generated wrapper directly, or add it into a
#      larger testbench.
#
# This script only ADDS a new block design + one new source file
# (mmu_ip_wrapper.v, already written) -- it does not touch
# RV32IMA_DualCore_Wrapper.v/BoardTop.v or any file already
# synthesized/implemented on real hardware (see Risc_V.runs/).
#===============================================================

puts "=== build_soc_mmu_trial.tcl: starting ==="

if {[llength [get_projects -quiet]] == 0} {
    error "No open Vivado project. Open Risc_V_new/Risc_V/Risc_V.xpr first, then re-source this script."
}

set BD_NAME "soc_mmu_trial"

#---------------------------------------------------------------
# 0. Make sure mmu_ip_wrapper.v is a design source
#---------------------------------------------------------------
puts "--> [0] Registering mmu_ip_wrapper.v as a design source"

set wrapper_file [glob -nocomplain -directory [file dirname [get_property DIRECTORY [current_project]]]/../rtl mmu_ip_wrapper.v]
if {$wrapper_file eq ""} {
    # Fall back: search relative to this script's own location
    set script_dir [file dirname [file normalize [info script]]]
    set wrapper_file [file normalize [file join $script_dir .. rtl mmu_ip_wrapper.v]]
}

if {![file exists $wrapper_file]} {
    error "Could not find mmu_ip_wrapper.v (looked at: $wrapper_file). Adjust the path at the top of this script if your checkout layout differs."
}

if {[llength [get_files -quiet [file tail $wrapper_file]]] == 0} {
    add_files -norecurse $wrapper_file
    puts "    added $wrapper_file to the project"
} else {
    puts "    already in project: $wrapper_file"
}
update_compile_order -fileset sources_1

#---------------------------------------------------------------
# 1. Create the block design
#---------------------------------------------------------------
puts "--> [1] Creating block design '$BD_NAME'"

if {[llength [get_files -quiet "${BD_NAME}.bd"]] > 0} {
    # Always rebuild from scratch rather than reusing a stale BD --
    # this script is meant to be re-run while iterating, and a BD
    # left half-wired from a previous failed run (e.g. cpu0 created
    # before mmu_ip_wrapper.v had proper X_INTERFACE_INFO attributes,
    # so its AXI ports never got bundled into interface pins) would
    # silently keep failing the same way even after the source file
    # is fixed, since Vivado only re-infers a module reference's
    # interface pins at the moment the cell is *created*.
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
# 2. Clock / reset
#---------------------------------------------------------------
puts "--> [2] Clock/reset network (external clk+rst -> proc_sys_reset)"

create_bd_port -dir I sys_clk
create_bd_port -dir I ext_reset_in

set rst0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]
connect_bd_net [get_bd_ports sys_clk]        [get_bd_pins  $rst0/slowest_sync_clk]
connect_bd_net [get_bd_ports ext_reset_in]   [get_bd_pins  $rst0/ext_reset_in]

set ACLK       [get_bd_ports sys_clk]
set ARESETN    [get_bd_pins  $rst0/peripheral_aresetn]
set IC_ARESETN [get_bd_pins  $rst0/interconnect_aresetn]

#---------------------------------------------------------------
# 3. CPU (MMU-integrated core, AXI4 master)
#---------------------------------------------------------------
puts "--> [3] Instantiating cpu0 = mmu_ip_wrapper"

set cpu0 [create_bd_cell -type module -reference mmu_ip_wrapper cpu0]
catch {set_property CONFIG.RESET_ADDR {32'h00001000} [get_bd_cells cpu0]}

connect_bd_net $ACLK    [get_bd_pins cpu0/ACLK]
connect_bd_net $ARESETN [get_bd_pins cpu0/ARESETN]

# Static MMU control -- see header note: bypass (0) until a real
# page table is preloaded into bram_boot.
set c_en    [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_MMU_ENABLE]
set_property CONFIG.CONST_WIDTH {1}  [get_bd_cells $c_en]
set_property CONFIG.CONST_VAL   {0}  [get_bd_cells $c_en]
connect_bd_net [get_bd_pins $c_en/dout] [get_bd_pins cpu0/Mmu_Enable]

set c_satp  [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_SATP_PPN]
set_property CONFIG.CONST_WIDTH {20} [get_bd_cells $c_satp]
set_property CONFIG.CONST_VAL   {0}  [get_bd_cells $c_satp]
connect_bd_net [get_bd_pins $c_satp/dout] [get_bd_pins cpu0/Satp_PPN]

set c_flush [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_MMU_FLUSH]
set_property CONFIG.CONST_WIDTH {1}  [get_bd_cells $c_flush]
set_property CONFIG.CONST_VAL   {0}  [get_bd_cells $c_flush]
connect_bd_net [get_bd_pins $c_flush/dout] [get_bd_pins cpu0/Mmu_Flush]

#---------------------------------------------------------------
# 4. DMA (memory-mapped to memory-mapped copy engine)
#---------------------------------------------------------------
puts "--> [4] Instantiating dma0 = axi_cdma"

set dma0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma:4.1 dma0]
catch {set_property CONFIG.C_INCLUDE_SG {0} [get_bd_cells $dma0]}
connect_bd_net $ACLK    [get_bd_pins $dma0/s_axi_lite_aclk]
connect_bd_net $ACLK    [get_bd_pins $dma0/m_axi_aclk]
connect_bd_net $ARESETN [get_bd_pins $dma0/s_axi_lite_aresetn]

#---------------------------------------------------------------
# 5. Interrupt controller
#---------------------------------------------------------------
puts "--> [5] Instantiating intc0 = axi_intc"

set intc0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 intc0]
connect_bd_net $ACLK    [get_bd_pins $intc0/s_axi_aclk]
connect_bd_net $ARESETN [get_bd_pins $intc0/s_axi_aresetn]

# No real interrupt source wired up yet (core has no trap/exception
# unit -- see Risc_V_new/README.md #13). Tie intc0's input low so the
# design elaborates; wire a real source in once one exists.
set c_intr [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_INTR]
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells $c_intr]
set_property CONFIG.CONST_VAL   {0} [get_bd_cells $c_intr]
connect_bd_net [get_bd_pins $c_intr/dout] [get_bd_pins $intc0/intr]

create_bd_port -dir O irq
connect_bd_net [get_bd_pins $intc0/irq] [get_bd_ports irq]

#---------------------------------------------------------------
# 6. Two BRAM-backed memory targets (SRAM / DRAM stand-ins)
#---------------------------------------------------------------
puts "--> [6] Instantiating bram_boot / bram_main (SRAM + DRAM stand-ins)"

proc make_bram_target {name aclk aresetn} {
    set bc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 ${name}_ctrl]
    set_property -dict [list \
        CONFIG.SINGLE_PORT_BRAM {1} \
        CONFIG.PROTOCOL         {AXI4} \
    ] [get_bd_cells $bc]

    set mem [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 ${name}_mem]
    catch {set_property -dict [list \
        CONFIG.Memory_Type            {Single_Port_RAM} \
        CONFIG.Use_Byte_Write_Enable  {true} \
        CONFIG.Byte_Size              {8} \
        CONFIG.Write_Width_A          {32} \
        CONFIG.Write_Depth_A          {16384} \
        CONFIG.Enable_A               {Always_Enabled} \
    ] [get_bd_cells $mem]}

    connect_bd_intf_net [get_bd_intf_pins $bc/BRAM_PORTA] [get_bd_intf_pins $mem/BRAM_PORTA]
    connect_bd_net $aclk    [get_bd_pins $bc/s_axi_aclk]
    connect_bd_net $aresetn [get_bd_pins $bc/s_axi_aresetn]

    return $bc
}

set bram_boot [make_bram_target bram_boot $ACLK $ARESETN]
set bram_main [make_bram_target bram_main $ACLK $ARESETN]

#---------------------------------------------------------------
# 7. AXI4 system bus (the diagram's AXI4 segment)
#---------------------------------------------------------------
puts "--> [7] Instantiating axi_interconnect_0 (3 masters in -> 4 slaves out)"

set ic0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {4}] [get_bd_cells $ic0]

connect_bd_net $ACLK    [get_bd_pins $ic0/ACLK]
connect_bd_net $IC_ARESETN [get_bd_pins $ic0/ARESETN]
foreach idx {00 01 02} {
    connect_bd_net $ACLK    [get_bd_pins $ic0/S${idx}_ACLK]
    connect_bd_net $ARESETN [get_bd_pins $ic0/S${idx}_ARESETN]
}
foreach idx {00 01 02 03} {
    connect_bd_net $ACLK    [get_bd_pins $ic0/M${idx}_ACLK]
    connect_bd_net $ARESETN [get_bd_pins $ic0/M${idx}_ARESETN]
}

# Masters in: cpu0 IMEM, cpu0 DMEM, dma0 data port
connect_bd_intf_net [get_bd_intf_pins cpu0/M_AXI_IMEM] [get_bd_intf_pins $ic0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins cpu0/M_AXI_DMEM] [get_bd_intf_pins $ic0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXI]     [get_bd_intf_pins $ic0/S02_AXI]

# Slaves out: boot BRAM, main BRAM, dma0 control, intc0 control
connect_bd_intf_net [get_bd_intf_pins $ic0/M00_AXI] [get_bd_intf_pins $bram_boot/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic0/M01_AXI] [get_bd_intf_pins $bram_main/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic0/M02_AXI] [get_bd_intf_pins $dma0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $ic0/M03_AXI] [get_bd_intf_pins $intc0/s_axi]

#---------------------------------------------------------------
# 8. Address map
#
# bram_boot / bram_main offsets follow address_mapping's physical
# map (Boot ROM @ 0x0000_0000, Main RAM @ 0x8000_0000) -- ranges are
# 64KB here (a trial-fit size, not the real Main RAM size from the
# diagram). dma0/intc0 control ranges are left to Vivado's default
# auto-assignment since address_mapping doesn't specify them.
#---------------------------------------------------------------
puts "--> [8] Assigning addresses"

catch {assign_bd_address} ; # auto-assign everything first, so nothing is left unmapped

foreach {space_pin} {cpu0/M_AXI_IMEM cpu0/M_AXI_DMEM dma0/M_AXI} {
    if {[catch {
        set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $space_pin] -filter {NAME =~ "*bram_boot*"}]
        assign_bd_address -offset 0x00000000 -range 64K -target_address_space [get_bd_addr_spaces $space_pin] $seg -force
    } err]} {
        puts "    WARNING: could not pin bram_boot address for $space_pin ($err) -- fix by hand in the Address Editor."
    }
    if {[catch {
        set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $space_pin] -filter {NAME =~ "*bram_main*"}]
        assign_bd_address -offset 0x80000000 -range 64K -target_address_space [get_bd_addr_spaces $space_pin] $seg -force
    } err]} {
        puts "    WARNING: could not pin bram_main address for $space_pin ($err) -- fix by hand in the Address Editor."
    }
}

#---------------------------------------------------------------
# 9. Wrap up
#---------------------------------------------------------------
puts "--> [9] Validating and saving"

regenerate_bd_layout
if {[catch {validate_bd_design} verr]} {
    puts "    WARNING: validate_bd_design reported problems:"
    puts "    $verr"
    puts "    Open the BD in the GUI (Window -> $BD_NAME) to see them highlighted."
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

puts "=== build_soc_mmu_trial.tcl: done ==="
puts ""
puts "Next steps:"
puts "  1. Window -> $BD_NAME  -- inspect the diagram, check for red/unconnected pins."
puts "  2. If any WARNING printed above, fix that one connection/address by hand."
puts "  3. Mmu_Enable is tied to 0 (bypass) -- this run only proves the AXI plumbing"
puts "     (real ARREADY/RVALID/BVALID handshakes) works, not MMU-over-AXI yet."
puts "     To test the MMU for real: load a page table into bram_boot's blk_mem_gen"
puts "     (same layout as Risc_V/sim/tb_mmu_core.v), then flip CONST_MMU_ENABLE's"
puts "     CONFIG.CONST_VAL to 1 and re-run from step 8 (address assignment) onward."
puts "  4. To simulate: set the generated <BD_NAME>_wrapper as the simulation top,"
puts "     or instantiate it from your own testbench."
