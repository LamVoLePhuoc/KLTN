# OOC PPA: `core_l1_wrapper`

- Generated: Tue Nov 10 22:27:32 +0700 2026
- Part: `xcvu29p-fsga2577-2L-e`
- Flow: `impl`
- MESI_ENABLE: `1`
- Target: `4.000 ns` (`250.000 MHz`) on `clk`
- Route status: `complete`
- MARK_DEBUG nets after synthesis: `0`
- Setup WNS: `0.143 ns`
- Hold slack: `0.004 ns`
- Timing-derived Fmax estimate: `259.269 MHz`
- Critical startpoint: `physical_core/core/fetch_unit/Program_Counter/PC_reg[5]/C`
- Critical endpoint: `u_icache/valid_way1_groups_q1_reg[16]/D`

| Resource | Count |
|---|---:|
| LUT cells | 10619 |
| FF cells | 6769 |
| RAMB36 | 24 |
| RAMB18 | 4 |
| BRAM tiles (conservative) | 26 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result.
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
