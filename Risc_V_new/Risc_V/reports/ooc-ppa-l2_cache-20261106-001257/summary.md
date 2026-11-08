# OOC PPA: `l2_cache`

- Generated: Fri Nov 06 00:14:25 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `synth`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `not-run`
- Setup WNS: `0.229 ns`
- Hold slack: `0.214 ns`
- Timing-derived Fmax estimate: `322.165 MHz`
- Critical startpoint: `u_data_way1/g_word_bank[0].u_word_ram/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_0/CLKARDCLK`
- Critical endpoint: `g_line_slice[0].u_slice/lookup_word_q_reg[0]/D`

| Resource | Count |
|---|---:|
| LUT cells | 1807 |
| FF cells | 1511 |
| RAMB36E1 | 136 |
| RAMB18E1 | 5 |
| BRAM tiles (conservative) | 139 |
| RAMD64E | 0 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
