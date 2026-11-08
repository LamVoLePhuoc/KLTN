# OOC PPA: `l1_icache`

- Generated: Wed Nov 04 18:50:54 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `-0.255 ns`
- Hold slack: `0.093 ns`
- Timing-derived Fmax estimate: `278.707 MHz`
- Critical startpoint: `valid_way0_r_reg[212]/C`
- Critical endpoint: `lookup_victim_q2_reg/D`

| Resource | Count |
|---|---:|
| LUT cells | 2441 |
| FF cells | 1422 |
| RAMB36E1 | 8 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 9 |
| RAMD64E | 16 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
