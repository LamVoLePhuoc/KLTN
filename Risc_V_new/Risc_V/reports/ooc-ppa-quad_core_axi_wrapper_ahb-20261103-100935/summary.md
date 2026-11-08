# OOC PPA: `quad_core_axi_wrapper_ahb`

- Generated: Tue Nov 03 10:23:54 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `ACLK`
- Route status: `complete`
- Setup WNS: `0.214 ns`
- Hold slack: `0.011 ns`
- Timing-derived Fmax estimate: `104.319 MHz`
- Critical startpoint: `soc/core2/u_icache/lookup_addr_reg[6]_rep/C`
- Critical endpoint: `soc/core2/physical_core/core/fetch_unit/Program_Counter/PC_reg[30]/D`

| Resource | Count |
|---|---:|
| LUT cells | 45937 |
| FF cells | 33139 |
| RAMB36E1 | 216 |
| RAMB18E1 | 25 |
| BRAM tiles (conservative) | 229 |
| RAMD64E | 192 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
