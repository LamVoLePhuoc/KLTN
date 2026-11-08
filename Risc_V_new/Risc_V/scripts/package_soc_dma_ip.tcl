# Package the source-level APB-controlled AXI DMA as reusable Vivado IP.
#
# Run from a shell:
#   vivado -mode batch -source scripts/package_soc_dma_ip.tcl
#
# Output:
#   ip_repo/soc_dma_controller_1_0/component.xml

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set rtl_dma_dir [file join $project_dir rtl dma]
set ip_repo_dir [file join $project_dir ip_repo]
set ip_root     [file join $ip_repo_dir soc_dma_controller_1_0]
set work_root   [file join $project_dir .ip_package_work]

set expected_ip_root [file normalize [file join $project_dir ip_repo soc_dma_controller_1_0]]
if {[file normalize $ip_root] ne $expected_ip_root} {
    error "Refusing to replace unexpected IP output path: $ip_root"
}

file mkdir $ip_repo_dir
if {[file exists $ip_root]} {
    file delete -force $ip_root
}
file mkdir $work_root

create_project -force soc_dma_ip_package $work_root -part xc7z030fbg676-2
set_property target_language Verilog [current_project]

set dma_sources [list \
    [file join $rtl_dma_dir apb_dma_regs.v] \
    [file join $rtl_dma_dir dma_cache_coordinator.v] \
    [file join $rtl_dma_dir axi_memcpy_dma.v] \
    [file join $rtl_dma_dir soc_dma_controller.v]]

foreach src $dma_sources {
    if {![file exists $src]} {
        error "Missing DMA source: $src"
    }
}

add_files -norecurse $dma_sources
set_property top soc_dma_controller [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor kltn.local \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name soc_dma_controller $core
set_property display_name {KLTN APB-Controlled AXI DMA} $core
set_property description {Non-coherent memory-to-memory AXI4 DMA with APB4 control and cache-maintenance handshake} $core
set_property vendor_display_name {KLTN} $core
set_property version 1.0 $core
set_property core_revision 1 $core

# The RTL interface attributes must infer these standard interfaces.  Fail the
# package step instead of silently producing a pin-only IP if inference breaks.
foreach busif_name {S_APB M_AXI} {
    if {[llength [ipx::get_bus_interfaces $busif_name -of_objects $core]] != 1} {
        error "Expected packaged bus interface $busif_name was not inferred"
    }
}

ipx::associate_bus_interfaces -busif S_APB -clock clk $core
ipx::associate_bus_interfaces -busif M_AXI -clock clk $core

# Give the APB slave a small, explicit address block.  The Xilinx AXI-to-APB
# bridge still exposes a 64 KiB AXI aperture; only offsets 0x00..0x10 are used.
set apb_if [ipx::get_bus_interfaces S_APB -of_objects $core]
set memory_maps [ipx::get_memory_maps -of_objects $core]
if {[llength $memory_maps] == 0} {
    set memory_map [ipx::add_memory_map S_APB $core]
    set_property slave_memory_map_ref S_APB $apb_if
} else {
    set memory_map [lindex $memory_maps 0]
    set_property slave_memory_map_ref [get_property name $memory_map] $apb_if
}
if {[llength [ipx::get_address_blocks -of_objects $memory_map]] == 0} {
    set address_block [ipx::add_address_block dma_registers $memory_map]
    set_property base_address 0 $address_block
    set_property range 4096 $address_block
    set_property width 32 $address_block
    set_property usage register $address_block
}

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

set integrity_result [ipx::check_integrity -quiet $core]
puts "IP integrity result: $integrity_result"
puts "Packaged DMA IP: $ip_root"

close_project
