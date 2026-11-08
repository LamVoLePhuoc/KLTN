# OOC PPA: `l2_cache`

- Generated: Fri Nov 06 00:25:45 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `3.333 ns` (`300.030 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `-1.182 ns`
- Hold slack: `0.098 ns`
- Timing-derived Fmax estimate: `221.484 MHz`
- Critical startpoint: `init_active_reg_replica_3/C`
- Critical endpoint: `u_data_way3/g_word_bank[6].u_word_ram/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_3/ADDRARDADDR[9]`

| Resource | Count |
|---|---:|
| LUT cells | 1808 |
| FF cells | 1524 |
| RAMB36E1 | 136 |
| RAMB18E1 | 5 |
| BRAM tiles (conservative) | 139 |
| RAMD64E | 0 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
