# Post-route Fmax evidence: 102.041 MHz

## Result

The active four-core physical-address cache-controller design meets a
9.800 ns clock period on `xc7z030fbv676-1` after full synthesis, placement,
physical optimization, and routing.

| Measurement | 100 MHz baseline | Optimized proof |
|---|---:|---:|
| Applied clock period | 10.000 ns | 9.800 ns |
| Proven target frequency | 100.000 MHz | 102.041 MHz |
| Post-route WNS | +0.051 ns | +0.029 ns |
| Post-route WHS | +0.039 ns | +0.036 ns |
| Failed/unrouted/partial nets | 0 | 0 |
| Timing signoff | MET | MET |

The proven target-frequency increase is 2.041%. This is a constraint-backed
post-route result, not a frequency inferred only from synthesis or an
intermediate placement estimate.

The old critical path ran from the cache controller request address through
the shared-L2 response metadata. After pipelining the L2 directory lookup and
maintenance data selection, the limiting path moved into a private I-cache to
core writeback-control path. This confirms that the former L2 path was
actually removed from the timing bottleneck.

## Resource comparison

| Post-route resource | Baseline | Optimized | Change |
|---|---:|---:|---:|
| Slice LUTs | 56,263 | 53,415 | -2,848 (-5.1%) |
| LUT as memory | 11,822 | 8,494 | -3,328 (-28.2%) |
| RAMD64E after synthesis | 11,712 | 8,384 | -3,328 (-28.4%) |
| Slice registers | 37,353 | 38,507 | +1,154 (+3.1%) |
| Block-RAM tiles | 234/265 | 234/265 | unchanged |
| DSPs | 16/400 | 16/400 | unchanged |

The L2 data capacity is unchanged. One explicit directory read index avoids
duplicating the distributed directory RAM, while extra pipeline registers
break the long combinational/routing paths.

## Behavioral evidence

- Active cache-controller regression: **21/21 PASS**.
- Hierarchical physical-system regression: **5/5 PASS**, from core through
  L1, L2/AHB, four-core SoC, and board-level AXI behavior.
- Legacy Sv32 translation sources remain excluded from the active manifest.

The behavioral reports were generated after the final RTL pipeline changes.
The later XDC change affects implementation timing only, not RTL behavior.

## Reproduce in Vivado

From the Vivado Tcl Console:

```tcl
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_active_cache_xsim.tcl}
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_behavior_hierarchy_xsim.tcl}
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_fmax_102mhz.tcl}
```

The implementation script verifies that the clock object really uses
9.800 ns, rejects cache-resource overuse, and fails if post-route setup or
hold slack is negative. It does not create false paths, multicycle paths,
timing waivers, or DRC suppressions.

## Evidence files

- Baseline: `reports/vivado-mdu-pipeline-20261027-162913/summary.txt`
- Optimized timing: `reports/vivado-mdu-pipeline-20261028-114757/summary.txt`
- Full timing signoff: `reports/vivado-mdu-pipeline-20261028-114757/timing_route.rpt`
- DRC: `reports/vivado-mdu-pipeline-20261028-114757/drc_route.rpt`
- Utilization: `reports/vivado-mdu-pipeline-20261028-114757/utilization_route.rpt`
- Active regression: `reports/xsim-active-cache-20261028-110125/summary.md`
- Hierarchical regression: `reports/xsim-behavior-hierarchy-20261028-110415/summary.md`

## Remaining board limitation

Post-route timing is valid for the selected FPGA part, but bitstream
generation is not yet board-ready. DRC still reports `NSTD-1` and `UCIO-1`
for `sys_clk` and `ext_reset_in` because the exact board pin locations and
I/O standards have intentionally not been guessed. Add the official board
XDC before generating and loading a bitstream. The power report also warns
that vectorless reset activity may make its power estimate inaccurate; this
does not alter timing signoff.
