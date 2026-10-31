# Physical-system behavioral verification

Generated: Mon Oct 26 14:30:29 +0700 2026

- PASS: 2/5
- DUT failures: 3
- Tool/elaboration errors: 0
- Translation-source manifest guard: PASS

| Level | Test | Status |
|---|---|---:|
| L0_CORE | tb_core_rv32ima_isa | PASS |
| L1_CORE_L1 | tb_core_l1_physical_subsystem | DUT_FAIL |
| L2_CACHE_AHB | tb_coherence_ahb | PASS |
| L3_4CORE_SOC | tb_quad_core_soc_ahb_behavior | DUT_FAIL |
| L4_BOARD_AXI | tb_quad_core_axi_ahb_behavior | DUT_FAIL |

> Scope: direct physical addressing; no TLB/PTW/VA-to-PA translation.
> TOOL_ERROR is kept separate from DUT_FAIL so an EDA installation problem cannot be reported as a design failure.
