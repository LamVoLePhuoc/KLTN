# OOC PPA: `physical_core_wrapper`

- Generated: Tue Nov 03 22:39:03 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.000 ns` (`111.111 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `0.803 ns`
- Hold slack: `0.057 ns`
- Timing-derived Fmax estimate: `121.996 MHz`
- Critical startpoint: `core/ex_mem/ALU_ResultM_reg[5]/C`
- Critical endpoint: `core/csr_trap/mcause_reg[23]/R`

| Resource | Count |
|---|---:|
| LUT cells | 3835 |
| FF cells | 2414 |
| RAMB36E1 | 0 |
| RAMB18E1 | 0 |
| BRAM tiles (conservative) | 0 |
| RAMD64E | 0 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
