#===============================================================
# build_soc_4core_trial.tcl
#
# Second architecture trial fit: the FULL 4-core system (4x
# core_l1_wrapper -> coherence_manager [L2 + MESI directory + the
# AHB-stand-in arbiter] -> quad_core_axi_wrapper) wired into Vivado
# stock AXI4 IP. This is a separate, new script -- it does NOT
# modify build_soc_mmu_trial.tcl (the earlier 1-core, no-cache trial)
# or any other existing file, per instruction.
#
# WHAT THIS BUILDS:
#
#   cpu0 (quad_core_axi_wrapper: 4 cores + L1 I$/D$ + L2 + MESI)
#              M_AXI (single combined R/W master)
#                     |            dma0 (axi_cdma)
#                     |               M_AXI
#                      \_______________/
#                             |
#                    axi_interconnect_0
#                     (stand-in for the diagram's AXI4 system bus)
#                    /                  \
#             mem_ctrl/S_AXI          dma0/S_AXI_LITE
#             (axi_bram_ctrl)         (ctrl regs)
#             0x0000_0000, sized
#             by MEM_SIZE_BYTES
#             below -- stands in
#             for "Memory
#             Controller + DDRAM"
#
# CHANGES FROM build_soc_mmu_trial.tcl (the 1-core version), all per
# instruction:
#   - 4 cores (quad_core_axi_wrapper), not 1 (mmu_ip_wrapper) --
#     wired through coherence_manager.v's L2/MESI/arbiter, so this
#     script only ever touches ONE AXI master from the CPU side
#     (unlike the 1-core script's separate IMEM/DMEM masters --
#     coherence_manager.v already serializes everything onto one
#     mem_* port before this wrapper's AXI logic ever sees it).
#   - Interrupt controller (axi_intc) and the second BRAM target
#     (the "SRAM Controller + SRAM" stand-in) are DROPPED entirely,
#     per instruction -- only DMA (axi_cdma) and one memory target
#     ("Memory Controller + DDRAM") remain. If SRAM ends up back in
#     scope later, re-add a second axi_bram_ctrl/blk_mem_gen pair the
#     same way build_soc_mmu_trial.tcl does it.
#   - No proc_sys_reset-fed IC_ARESETN split needed here -- only one
#     AXI master feeds the interconnect from the CPU side (plus DMA),
#     so the wiring is simpler than the earlier script's 3-master case.
#
# WHY THESE CHOICES: see build_soc_mmu_trial.tcl's header for the
# reasoning that still applies unchanged here (no AHB IP in Vivado's
# catalog; BRAM stand-in instead of PS7 DDR/MIG until the board's
# real DDR path is confirmed; axi_cdma over axi_dma since this is a
# memory-mapped-to-memory-mapped copy engine, not a stream device).
#
# MMU enable is no longer an external pin (see step [3] below): each
# core boots with its satp CSR reset to 0 (Bare/bypass, same effective
# result as the old CONST_MMU_ENABLE=0 tie-off) and only starts
# translating once boot/supervisor code running ON that core executes
# CSRRW satp, ... itself -- same as real RISC-V hardware. This script
# does not preload a page table into mem_ctrl, so as long as the
# preloaded program never writes satp, behaviour is unchanged from the
# old tie-off (see tb_mmu_core.v for the table layout a future
# preloaded test could use).
#
# CORRECTNESS CAVEAT (read before trusting results from this BD):
# coherence_manager.v / l1_dcache.v / l2_cache.v implement a from-
# scratch MESI directory protocol that has NOT been simulated --
# only reasoned through by hand (see each file's header and
# Risc_V_new/README.md's risk register). This script proves the
# *wiring* fits together and elaborates; it proves nothing about
# whether the coherence protocol itself is correct. Do not treat a
# clean `validate_bd_design` here as evidence the MESI logic works --
# only a passing testbench (Risc_V/sim/tb_coherence.v, if present, or
# one you write) is evidence of that.
#
# HOW TO RUN
#   1. Open Risc_V_new/Risc_V/Risc_V.xpr in Vivado (must already be
#      open -- this script assumes an active project, it does not
#      open one itself).
#   2. In the Tcl Console:  source {<path to this file>}
#   3. Same WARNING-not-abort convention as build_soc_mmu_trial.tcl --
#      read the Tcl Console output, fix anything flagged by hand in
#      the GUI rather than re-running blind.
#   4. Window -> soc_4core_trial in the BD editor; Generate Block
#      Design; simulate the generated wrapper or fold it into a
#      larger testbench.
#===============================================================

puts "=== build_soc_4core_trial.tcl: starting ==="

if {[llength [get_projects -quiet]] == 0} {
    error "No open Vivado project. Open Risc_V_new/Risc_V/Risc_V.xpr first, then re-source this script."
}

set BD_NAME       "soc_4core_trial"
set MEM_SIZE_BYTES 262144 ;# 256KB -- trial-fit size, not the real target DRAM size

#---------------------------------------------------------------
# 0. Register the new RTL sources this trial needs (all files added
#    in this session; none of them touch/replace anything used by
#    build_soc_mmu_trial.tcl or the already-synthesized dual-core
#    BoardTop path).
#---------------------------------------------------------------
puts "--> [0] Registering new RTL sources"

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir     [file normalize [file join $script_dir .. rtl]]

set new_sources {
    l1_icache.v
    l1_dcache.v
    core_l1_wrapper.v
    l2_cache.v
    coherence_manager.v
    quad_core_soc.v
    quad_core_axi_wrapper.v
}

foreach f $new_sources {
    set full_path [file join $rtl_dir $f]
    if {![file exists $full_path]} {
        error "Could not find $full_path -- adjust $rtl_dir at the top of this script if your checkout layout differs."
    }
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -norecurse $full_path
        puts "    added $f"
    } else {
        puts "    already in project: $f"
    }
}
update_compile_order -fileset sources_1

#---------------------------------------------------------------
# 1. Create the block design (always rebuild clean -- see
#    build_soc_mmu_trial.tcl's step [1] comment for why: a module
#    reference's interface pins are only inferred at cell-creation
#    time, so a stale half-built BD from an earlier failed run would
#    keep failing the same way even after a source fix).
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
# 2. Clock / reset
#---------------------------------------------------------------
puts "--> [2] Clock/reset network"

create_bd_port -dir I sys_clk
create_bd_port -dir I ext_reset_in

set rst0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0]
connect_bd_net [get_bd_ports sys_clk]      [get_bd_pins $rst0/slowest_sync_clk]
connect_bd_net [get_bd_ports ext_reset_in] [get_bd_pins $rst0/ext_reset_in]

set ACLK       [get_bd_ports sys_clk]
set ARESETN    [get_bd_pins  $rst0/peripheral_aresetn]
set IC_ARESETN [get_bd_pins  $rst0/interconnect_aresetn]

#---------------------------------------------------------------
# 3. CPU (4-core, cache+coherence integrated, AXI4 master)
#---------------------------------------------------------------
puts "--> [3] Instantiating cpu0 = quad_core_axi_wrapper"

set cpu0 [create_bd_cell -type module -reference quad_core_axi_wrapper cpu0]
# Stagger each core's boot address by 0x1000 so 4 independent program
# regions are possible in mem_ctrl (all cores otherwise default to
# the same RESET_ADDR, which -- like RV32IMA_DualCore_Wrapper.v's two
# cores -- would have them execute the exact same instruction stream).
catch {set_property -dict [list \
    CONFIG.RESET_ADDR0 {32'h00001000} \
    CONFIG.RESET_ADDR1 {32'h00002000} \
    CONFIG.RESET_ADDR2 {32'h00003000} \
    CONFIG.RESET_ADDR3 {32'h00004000} \
] [get_bd_cells cpu0]}

connect_bd_net $ACLK    [get_bd_pins cpu0/ACLK]
connect_bd_net $ARESETN [get_bd_pins cpu0/ARESETN]

set c_flush [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_MMU_FLUSH]
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells $c_flush]
set_property CONFIG.CONST_VAL   {0} [get_bd_cells $c_flush]
connect_bd_net [get_bd_pins $c_flush/dout] [get_bd_pins cpu0/Mmu_Flush]

set c_cflush [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 CONST_CACHE_FLUSH]
set_property CONFIG.CONST_WIDTH {1} [get_bd_cells $c_cflush]
set_property CONFIG.CONST_VAL   {0} [get_bd_cells $c_cflush]
connect_bd_net [get_bd_pins $c_cflush/dout] [get_bd_pins cpu0/Cache_Flush]

# NOTE: no CONST_MMU_ENABLE / CONST_SATP_PPN0..3 any more -- each
# core's own satp CSR (software CSRRW, see csr_trap_unit.v) is now the
# real source of truth for MMU enable + page-table root
# (core_l1_wrapper.v's mmu_core_wrapper instance uses
# MMU_CTRL_FROM_CSR=1). Boot code must CSRRW satp itself once a page
# table is ready in mem_ctrl; there is no external pin left to flip
# for this any more.

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
# 5. One BRAM-backed memory target ("Memory Controller + DDRAM"
#    stand-in). No second target this time -- SRAM Controller is
#    dropped per instruction.
#---------------------------------------------------------------
puts "--> [5] Instantiating mem_ctrl (${MEM_SIZE_BYTES} bytes)"

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
connect_bd_net $ACLK    [get_bd_pins $mem_ctrl/s_axi_aclk]
connect_bd_net $ARESETN [get_bd_pins $mem_ctrl/s_axi_aresetn]

#---------------------------------------------------------------
# 6. AXI4 system bus
#---------------------------------------------------------------
puts "--> [6] Instantiating axi_interconnect_0 (2 masters in -> 2 slaves out)"

set ic0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {2}] [get_bd_cells $ic0]

connect_bd_net $ACLK       [get_bd_pins $ic0/ACLK]
connect_bd_net $IC_ARESETN [get_bd_pins $ic0/ARESETN]
foreach idx {00 01} {
    connect_bd_net $ACLK    [get_bd_pins $ic0/S${idx}_ACLK]
    connect_bd_net $ARESETN [get_bd_pins $ic0/S${idx}_ARESETN]
    connect_bd_net $ACLK    [get_bd_pins $ic0/M${idx}_ACLK]
    connect_bd_net $ARESETN [get_bd_pins $ic0/M${idx}_ARESETN]
}

# Masters in: cpu0 (the whole 4-core+cache+coherence system, as ONE
# AXI master), dma0's data-mover port.
connect_bd_intf_net [get_bd_intf_pins cpu0/M_AXI]  [get_bd_intf_pins $ic0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma0/M_AXI] [get_bd_intf_pins $ic0/S01_AXI]

# Slaves out: the one memory target, dma0's own control port.
connect_bd_intf_net [get_bd_intf_pins $ic0/M00_AXI] [get_bd_intf_pins $mem_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic0/M01_AXI] [get_bd_intf_pins $dma0/S_AXI_LITE]

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

#---------------------------------------------------------------
# 8. Wrap up
#---------------------------------------------------------------
puts "--> [8] Validating and saving"

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

puts "=== build_soc_4core_trial.tcl: done ==="
puts ""
puts "Next steps:"
puts "  1. Window -> $BD_NAME -- inspect the diagram, check for red/unconnected pins."
puts "  2. If any WARNING printed above, fix that one connection/address by hand."
puts "  3. MMU enable/satp are CSR-driven now (no external pin) -- each core boots"
puts "     with paging off and only translates once ITS OWN boot code executes"
puts "     CSRRW satp, ... after preloading a page table into mem_ctrl."
puts "  4. Re-read the CORRECTNESS CAVEAT at the top of this file before trusting any"
puts "     result beyond 'the wiring elaborates' -- the MESI protocol itself is"
puts "     unsimulated. Run/write a coherence testbench before relying on it."
puts "  5. To simulate: set the generated <BD_NAME>_wrapper as the simulation top,"
puts "     or instantiate it from your own testbench."
