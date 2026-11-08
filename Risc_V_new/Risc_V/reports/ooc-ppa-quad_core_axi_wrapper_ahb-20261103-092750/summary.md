# OOC PPA: `quad_core_axi_wrapper_ahb`

- Generated: Tue Nov 03 09:51:12 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `9.800 ns` (`102.041 MHz`) on `ACLK`
- Route status: `complete`
- Setup WNS: `0.174 ns`
- Hold slack: `0.052 ns`
- Timing-derived Fmax estimate: `103.885 MHz`
- Critical startpoint: `soc/core1/u_icache/lookup_addr_reg[7]/C`
- Critical endpoint: `soc/core1/physical_core/core/csr_trap/mcause_reg[9]/CE`

| Resource | Count |
|---|---:|
| LUT cells | 48548 |
| FF cells | 33134 |
| RAMB36E1 | 208 |
| RAMB18E1 | 20 |
| BRAM tiles (conservative) | 218 |
| RAMD64E | 8384 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
