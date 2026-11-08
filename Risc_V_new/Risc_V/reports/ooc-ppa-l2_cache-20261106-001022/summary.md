# OOC PPA: `l2_cache`

- Generated: Fri Nov 06 00:11:47 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `synth`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `not-run`
- Setup WNS: `-0.154 ns`
- Hold slack: `0.191 ns`
- Timing-derived Fmax estimate: `286.779 MHz`
- Critical startpoint: `lookup_select_pending_reg/C`
- Critical endpoint: `u_meta_lru/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg/ADDRARDADDR[10]`

| Resource | Count |
|---|---:|
| LUT cells | 1530 |
| FF cells | 1511 |
| RAMB36E1 | 136 |
| RAMB18E1 | 5 |
| BRAM tiles (conservative) | 139 |
| RAMD64E | 0 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
