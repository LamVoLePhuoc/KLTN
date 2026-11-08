# Out-of-context synthesis check for the packaged DMA RTL.
set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set dma_dir     [file join $project_dir rtl dma]
set report_dir  [file join $project_dir reports soc-dma-ip-synth]
file mkdir $report_dir

read_verilog [list \
    [file join $dma_dir apb_dma_regs.v] \
    [file join $dma_dir dma_cache_coordinator.v] \
    [file join $dma_dir axi_memcpy_dma.v] \
    [file join $dma_dir soc_dma_controller.v]]

synth_design -top soc_dma_controller -part xc7z030fbg676-2 -mode out_of_context
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
write_checkpoint -force [file join $report_dir soc_dma_controller_ooc.dcp]
puts "SOC_DMA_IP_SYNTH: PASS"
