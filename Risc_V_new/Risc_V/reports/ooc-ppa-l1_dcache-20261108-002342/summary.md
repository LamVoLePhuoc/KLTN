# OOC PPA: `l1_dcache`

- Generated: Sun Nov 08 00:44:10 +0700 2026
- Part: `xcvu29p-fsga2577-2L-e`
- Flow: `impl`
- Target: `4.000 ns` (`250.000 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `0.433 ns`
- Hold slack: `0.007 ns`
- Timing-derived Fmax estimate: `280.348 MHz`
- Critical startpoint: `hit_stage_word_off_reg[2]_rep/C`
- Critical endpoint: `cache_write_line_reg[197]/D`

| Resource | Count |
|---|---:|
| LUT cells | 4161 |
| FF cells | 2382 |
| RAMB36 | 16 |
| RAMB18 | 2 |
| BRAM tiles (conservative) | 17 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
