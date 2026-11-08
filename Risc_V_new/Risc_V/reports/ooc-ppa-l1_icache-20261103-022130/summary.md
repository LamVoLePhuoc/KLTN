# OOC PPA: `l1_icache`

- Generated: Tue Nov 03 02:23:35 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `2.442 ns`
- Hold slack: `0.053 ns`
- Timing-derived Fmax estimate: `135.906 MHz`
- Critical startpoint: `u_meta_way0/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg/CLKARDCLK`
- Critical endpoint: `miss_word_reg[0]/CE`

| Resource | Count |
|---|---:|
| LUT cells | 2284 |
| FF cells | 1201 |
| RAMB36E1 | 8 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 9 |
| RAMD64E | 16 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
