# OOC PPA: `core_l1_wrapper`

- Generated: Tue Nov 10 23:01:35 +0700 2026
- Part: `xcvu29p-fsga2577-2L-e`
- Flow: `impl`
- MESI_ENABLE: `0`
- Target: `4.000 ns` (`250.000 MHz`) on `clk`
- Route status: `complete`
- MARK_DEBUG nets after synthesis: `0`
- Setup WNS: `0.295 ns`
- Hold slack: `0.011 ns`
- Timing-derived Fmax estimate: `269.906 MHz`
- Critical startpoint: `physical_core/core/ex_mem/ALU_ResultM_reg[16]/C`
- Critical endpoint: `u_dcache/u_data_way0/u_xpm/xpm_memory_base_inst/gen_wr_b.gen_word_narrow.mem_reg_bram_3/WEA[2]`

| Resource | Count |
|---|---:|
| LUT cells | 10618 |
| FF cells | 6769 |
| RAMB36 | 24 |
| RAMB18 | 4 |
| BRAM tiles (conservative) | 26 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result.
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
