# OOC PPA: `core_l1_wrapper`

- Generated: Tue Nov 03 18:12:36 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `1.017 ns`
- Hold slack: `0.054 ns`
- Timing-derived Fmax estimate: `113.856 MHz`
- Critical startpoint: `u_icache/lookup_addr_reg[6]/C`
- Critical endpoint: `physical_core/core/if_id/InstrD_reg[14]/R`

| Resource | Count |
|---|---:|
| LUT cells | 9711 |
| FF cells | 5345 |
| RAMB36E1 | 24 |
| RAMB18E1 | 4 |
| BRAM tiles (conservative) | 26 |
| RAMD64E | 48 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
