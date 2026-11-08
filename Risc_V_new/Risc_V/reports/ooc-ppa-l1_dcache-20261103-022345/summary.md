# OOC PPA: `l1_dcache`

- Generated: Tue Nov 03 02:26:36 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `2.074 ns`
- Hold slack: `0.061 ns`
- Timing-derived Fmax estimate: `129.433 MHz`
- Critical startpoint: `u_meta_way1/u_xpm/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg/CLKBWRCLK`
- Critical endpoint: `bus_req_line_reg[126]/CE`

| Resource | Count |
|---|---:|
| LUT cells | 3286 |
| FF cells | 1708 |
| RAMB36E1 | 16 |
| RAMB18E1 | 2 |
| BRAM tiles (conservative) | 17 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
