# OOC PPA: `l1_icache`

- Generated: Wed Nov 04 18:44:20 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `-0.321 ns`
- Hold slack: `0.094 ns`
- Timing-derived Fmax estimate: `273.673 MHz`
- Critical startpoint: `lookup_result_addr_reg[6]_rep_replica/C`
- Critical endpoint: `miss_way_reg_rep__5/D`

| Resource | Count |
|---|---:|
| LUT cells | 2434 |
| FF cells | 1444 |
| RAMB36E1 | 8 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 9 |
| RAMD64E | 16 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
