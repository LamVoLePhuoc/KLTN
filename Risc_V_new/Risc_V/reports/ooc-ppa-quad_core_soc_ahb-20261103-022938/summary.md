# OOC PPA: `quad_core_soc_ahb`

- Generated: Tue Nov 03 03:02:47 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `0.127 ns`
- Hold slack: `0.031 ns`
- Timing-derived Fmax estimate: `103.381 MHz`
- Critical startpoint: `u_shared_ahb_s/HRDATA_reg[31]/C`
- Critical endpoint: `u3_i_ahb_m/rd_line_buf_reg[127]/D`

| Resource | Count |
|---|---:|
| LUT cells | 48532 |
| FF cells | 32791 |
| RAMB36E1 | 208 |
| RAMB18E1 | 20 |
| BRAM tiles (conservative) | 218 |
| RAMD64E | 8384 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
