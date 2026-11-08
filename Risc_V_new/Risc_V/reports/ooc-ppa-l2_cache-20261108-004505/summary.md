# OOC PPA: `l2_cache`

- Generated: Sun Nov 08 01:06:14 +0700 2026
- Part: `xcvu29p-fsga2577-2L-e`
- Flow: `impl`
- Target: `4.000 ns` (`250.000 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `0.227 ns`
- Hold slack: `0.013 ns`
- Timing-derived Fmax estimate: `265.041 MHz`
- Critical startpoint: `lookup_selected_way_q_reg[0]_rep/C`
- Critical endpoint: `g_line_slice[1].u_slice/lookup_word_q_reg[2]/D`

| Resource | Count |
|---|---:|
| LUT cells | 1621 |
| FF cells | 1511 |
| RAMB36 | 136 |
| RAMB18 | 5 |
| BRAM tiles (conservative) | 139 |
| RAMD64E | 0 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
