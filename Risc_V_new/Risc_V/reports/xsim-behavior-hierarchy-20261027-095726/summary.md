# Physical-system behavioral verification

Generated: Tue Oct 27 09:58:21 +0700 2026

- PASS: 5/5
- DUT failures: 0
- Tool/elaboration errors: 0
- Translation-source manifest guard: PASS

| Level | Test | Status |
|---|---|---:|
| L0_CORE | tb_core_rv32ima_isa | PASS |
| L1_CORE_L1 | tb_core_l1_physical_subsystem | PASS |
| L2_CACHE_AHB | tb_coherence_ahb | PASS |
| L3_4CORE_SOC | tb_quad_core_soc_ahb_behavior | PASS |
| L4_BOARD_AXI | tb_quad_core_axi_ahb_behavior | PASS |

> Scope: direct physical addressing; no TLB/PTW/VA-to-PA translation.
> TOOL_ERROR is kept separate from DUT_FAIL so an EDA installation problem cannot be reported as a design failure.
