# OOC PPA: `core_l1_wrapper`

- Generated: Thu Nov 05 00:25:05 +0700 2026
- Part: `xc7z030fbv676-1`
- Flow: `impl`
- Target: `8.300 ns` (`120.482 MHz`) on `clk`
- Route status: `complete`
- Setup WNS: `0.113 ns`
- Hold slack: `0.060 ns`
- Timing-derived Fmax estimate: `122.145 MHz`
- Critical startpoint: `physical_core/core/ex_mem/ALU_ResultM_reg[2]/C`
- Critical endpoint: `u_dcache/bus_req_line_reg[30]/D`

| Resource | Count |
|---|---:|
| LUT cells | 9748 |
| FF cells | 6085 |
| RAMB36E1 | 24 |
| RAMB18E1 | 4 |
| BRAM tiles (conservative) | 26 |
| RAMD64E | 32 |

> The Fmax value is derived from this routed/ synthesized timing result. 
> A positive-slack estimate must be validated with a tighter constraint before it is claimed as achieved Fmax.
