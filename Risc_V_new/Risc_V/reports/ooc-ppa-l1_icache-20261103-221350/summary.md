# OOC PPA: `l1_icache`

- Generated: Tue Nov 03 22:16:43 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `2.396 ns`
- Hold slack: `0.086 ns`
- Timing-derived Fmax estimate: `135.062 MHz`
- Critical startpoint: `lookup_addr_reg[7]/C`
- Critical endpoint: `miss_way_reg_rep__11/D`

| Resource | Count |
|---|---:|
| LUT cells | 2283 |
| FF cells | 1201 |
| RAMB36E1 | 8 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 9 |
| RAMD64E | 16 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
