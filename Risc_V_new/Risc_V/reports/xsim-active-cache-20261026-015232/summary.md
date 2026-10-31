# Vivado XSIM active cache-controller regression

Result: **18/21 PASS**

| Test | Result | Log |
|---|---:|---|
| tb_ahb_error_sideband | PASS | run-tb_ahb_error_sideband.log |
| tb_ahb_uncached | PASS | run-tb_ahb_uncached.log |
| tb_axi_request_hold | PASS | run-tb_axi_request_hold.log |
| tb_boot_ctrl | PASS | run-tb_boot_ctrl.log |
| tb_cache_amo | FAIL | run-tb_cache_amo.log |
| tb_cache_error_path | PASS | run-tb_cache_error_path.log |
| tb_cache_fence_i | PASS | run-tb_cache_fence_i.log |
| tb_cache_lrsc | FAIL | run-tb_cache_lrsc.log |
| tb_cache_lrsc_snoop | FAIL | run-tb_cache_lrsc_snoop.log |
| tb_cache_maintenance | PASS | run-tb_cache_maintenance.log |
| tb_cache_uncached | PASS | run-tb_cache_uncached.log |
| tb_coherence | PASS | run-tb_coherence.log |
| tb_coherence_ahb | PASS | run-tb_coherence_ahb.log |
| tb_coherence_error | PASS | run-tb_coherence_error.log |
| tb_coherence_watchdog | PASS | run-tb_coherence_watchdog.log |
| tb_core_instruction_legality | PASS | run-tb_core_instruction_legality.log |
| tb_core_rv32ima_isa | PASS | run-tb_core_rv32ima_isa.log |
| tb_csr_access_fault | PASS | run-tb_csr_access_fault.log |
| tb_csr_priv | PASS | run-tb_csr_priv.log |
| tb_csr_trap | PASS | run-tb_csr_trap.log |
| tb_dma_end_to_end | PASS | run-tb_dma_end_to_end.log |

> Scope: direct physical addressing + core/cache/coherence/bus/boot/DMA. Legacy Sv32 is excluded.
