# OOC PPA: `l1_icache`

- Generated: Wed Nov 04 18:36:45 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `-1.714 ns`
- Hold slack: `0.091 ns`
- Timing-derived Fmax estimate: `198.138 MHz`
- Critical startpoint: `lookup_addr_q2_reg[5]_rep/C`
- Critical endpoint: `lookup_result_word_reg[16]/D`

| Resource | Count |
|---|---:|
| LUT cells | 2597 |
| FF cells | 1393 |
| RAMB36E1 | 8 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 9 |
| RAMD64E | 16 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
