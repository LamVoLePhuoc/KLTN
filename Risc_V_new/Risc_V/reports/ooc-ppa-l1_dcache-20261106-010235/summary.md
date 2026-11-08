# OOC PPA: `l1_dcache`

- Generated: Fri Nov 06 01:04:32 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `synth`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `not-run`
- Setup WNS: `-1.630 ns`
- Hold slack: `0.174 ns`
- Timing-derived Fmax estimate: `201.491 MHz`
- Critical startpoint: `u_meta_way0/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg/CLKBWRCLK`
- Critical endpoint: `u_meta_way0/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg/ADDRBWRADDR[10]`

| Resource | Count |
|---|---:|
| LUT cells | 4165 |
| FF cells | 2387 |
| RAMB36E1 | 16 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 17 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
