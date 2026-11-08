# PPA optimization log

This file is the compact hand-off record for the staged optimization flow.
Detailed Vivado logs remain under `reports/`; later work should read this file
and only the report/module relevant to the active checkpoint.

## Frozen baseline configuration

| Item | Value |
|---|---|
| Vivado | 2022.2 |
| FPGA part | `xc7z030fbv676-1` |
| Active timing constraint | `9.700 ns` on the integrated `ACLK` (`103.093 MHz`) |
| Addressing | Direct physical addressing; legacy Sv32 excluded |
| Coherence | MSI |
| Private cache | Four L1I + four L1D |
| Shared cache | 512 KiB L2, 4-way set-associative, 4096 sets, 32-byte line |
| Internal bus | AHB-Lite, eight L1 request sources |
| External bus | AXI4 |
| Platform DMA/memory | Vivado IP Catalog; excluded from active RTL regression |
| Clock domains | One synchronous CPU clock for the current optimization phase |

The project targets a generic part rather than a named board. Board-specific
pin constraints and any multi-clock architecture remain out of scope until the
exact board is fixed.

## Checkpoint status

| Checkpoint | Status | Evidence |
|---|---|---|
| 0. Architecture freeze | Complete | Configuration table above |
| 1. Functional baseline | Complete (existing evidence) | `reports/xsim-active-cache-20261101-172442/summary.md`: 21/21 PASS |
| 1. Current PPA baseline | Complete | Accepted RTL/resource baseline at 9.800 ns; tighter integrated sign-off is recorded in checkpoint 11 |
| 2. Reusable OOC flow | Complete | Arbiter synthesis completed at 9.800 ns; first validation also removed four stale `legacy_2core` manifest entries; no active RTL changed |
| 3. Per-block Fmax matrix | Complete | Ten routed OOC baselines, including the full AXI wrapper |
| 4. First localized optimization | Complete, rejected | Fanout hint failed timing gate and was reverted |
| 5. Per-master buffering | Complete, accepted | 8 registered AHB response buffers; 21/21 PASS; integrated WNS improved to +0.174 ns |
| 6. Control-block boundary audit | Complete | Active arbiter is separate; cache/coherence functions remain intentionally combined |
| 7. L2 miss/refill verification | Complete | Active hierarchy proves 8 memory words are read before every checked L2 line install |
| 8. L2 metadata BRAM mapping | Complete, accepted | Integrated LUT -2,611 and WNS +0.040 ns; BRAM +11 tiles |
| 9. CSR redirect/stall decoupling | Complete, rejected | Functional tests passed, but integrated WNS regressed from +0.214 ns to +0.036 ns; reverted |
| 10. Split I-cache hit/miss cones | Complete, rejected | Targeted tests passed, but isolated I-cache WNS regressed from +2.442 ns to +2.396 ns; reverted |
| 11. Routed Fmax lower-bound validation | Complete | Every active block class and the full wrapper routed with positive setup/hold slack; integrated system achieved 103.093 MHz |

## Historical reference — not the current baseline

Report: `reports/vivado-mdu-pipeline-20261028-003331/`

| Metric | Historical value |
|---|---:|
| Applied clock | 10.000 ns / 100.000 MHz |
| Post-route WNS | +0.072 ns |
| Post-route WHS | +0.033 ns |
| LUT | 60,930 |
| Registers | 38,586 |
| BRAM tiles | 234 / 265 |
| Critical start | `u_shared_l2/maint_way_q_reg[0]/C` |
| Critical end | `u_shared_l2/maint_line_data_reg[93]/D` |

The historical critical path is inside the shared L2 maintenance data-way mux,
but it must be remeasured on the current source and 9.800 ns constraint before
any RTL optimization is justified.

## OOC flow validation

Report: `reports/ooc-ppa-ahb_lite_arbiter_8m1s-20261103-015053/`

| Metric | Synthesis-only validation |
|---|---:|
| Target | 9.800 ns / 102.041 MHz |
| Setup WNS | +7.522 ns |
| Timing-derived estimate | 438.982 MHz; not yet route-validated |
| LUT cells | 309 |
| FF cells | 7 |
| Errors / critical warnings | 0 / 0 |

The large positive slack only validates the measurement flow. It is not an
achieved arbiter Fmax until an implementation run at a tighter constraint
passes routing and timing.

### `ahb_lite_arbiter_8m1s` — post-route baseline

Report: `reports/ooc-ppa-ahb_lite_arbiter_8m1s-20261103-015344/`

1. Critical path or bottleneck: `grant_source_r_reg[0]/C` to `rr_next_reg[0]/D`.
2. Root cause: no failing path at the 9.800 ns baseline; this is the slowest
   internal register-to-register path reported by the isolated arbiter.
3. Proposed/localized optimization: none until a tighter-constraint validation
   proves the arbiter is a system limiter.
4. Expected area/timing/power impact: no RTL change, so none.
5. Verification and measured result: route complete, WNS `+7.002 ns`, hold
   slack `+0.228 ns`, 309 LUT cells, 7 FF cells, 0 BRAM. The timing-derived
   estimate is 357.398 MHz but is not yet claimed as achieved Fmax.

## Checkpoint 3 routed OOC matrix — 9.800 ns baseline

All entries below use Vivado 2022.2 and `xc7z030fbv676-1`. There are zero
unconstrained internal endpoints in the routed timing reports. Primary I/O
delay and OOC part-pin warnings are expected and are not used as Fmax evidence.

| Block | WNS (ns) | Hold (ns) | Timing-derived estimate (MHz) | LUT | FF | BRAM tiles |
|---|---:|---:|---:|---:|---:|---:|
| `ahb_lite_arbiter_8m1s` | +7.002 | +0.228 | 357.398 | 309 | 7 | 0 |
| `ahb_lite_l1_adapter` | +5.055 | +0.083 | 210.748 | 499 | 850 | 0 |
| `physical_core_wrapper` | +0.944 | +0.107 | 112.918 | 3,835 | 2,414 | 0 |
| `l1_icache` | +2.442 | +0.053 | 135.906 | 2,284 | 1,201 | 9 |
| `l1_dcache` | +2.074 | +0.061 | 129.433 | 3,286 | 1,708 | 17 |
| `cache_controller_mmu` | +2.740 | +0.093 | 141.643 | 2,378 | 3,793 | 0 |
| `coherence_manager` legacy combined wrapper | +1.600 | +0.074 | 121.951 | 5,359 | 4,267 | 114 |
| `l2_cache` | +0.782 | +0.099 | 110.889 | 4,481 | 1,510 | 114 |
| `quad_core_soc_ahb` | +0.127 | +0.031 | 103.381 | 48,532 | 32,791 | 218 |
| `quad_core_axi_wrapper_ahb` | +0.082 | +0.049 | 102.902 | 48,540 | 32,861 | 218 |

These estimates come from a route at 9.800 ns. They rank bottlenecks but are
not yet individually validated maximum frequencies. The integrated quad-core
AXI-wrapper result is the current system authority: 102.041 MHz passes with
only 0.082 ns setup margin.

### Current integrated bottleneck

Report: `reports/ooc-ppa-quad_core_soc_ahb-20261103-022938/`

1. Critical path or bottleneck: shared AHB slave response register
   `u_shared_ahb_s/HRDATA_reg[31]` to core-3 instruction-master line buffer
   `u3_i_ahb_m/rd_line_buf_reg[127]`.
2. Root cause: the path has zero logic levels but 9.552 ns routing delay
   (97.261% of the 9.821 ns data-path delay). The 32-bit registered shared
   response is broadcast by the arbiter to all eight masters; the reported net
   has fanout 56 and crosses from `SLICE_X63Y143` to `SLICE_X7Y3` in the dense
   218-BRAM design.
3. Proposed/localized optimization: first try timing-driven response-register
   replication (`MAX_FANOUT`) without changing the AHB interface or latency.
   If replication is insufficient, Checkpoint 5 will add per-master buffering
   with an explicitly verified extra response stage.
4. Expected area/timing/power impact: replication may add up to a few hundred
   FFs and modest clock power while reducing long data-net fanout/routing delay.
5. Verification and measured result: the first fanout-hint trial below was
   rejected. The subsequent registered per-master response buffers passed all
   acceptance gates and removed this path from the critical-path set; see
   Checkpoint 5 below.

### Optimization trial 1 — response-register replication

Change: add `(* max_fanout = 8 *)` to the registered `HRDATA[31:0]` output of
`ahb_lite_l1_slave_adapter`. This is a synthesis/physical-optimization hint;
the AHB interface, FSM, response data and latency are unchanged.

Acceptance gates:

1. Relevant AHB/coherence simulations pass.
2. Full active regression remains 21/21 PASS.
3. Full AXI-wrapper route completes with no internal unconstrained endpoints.
4. The 9.800 ns WNS improves beyond the +0.082 ns baseline without a material
   resource regression. If it does not, revert this hint before attempting a
   protocol-visible per-master response buffer.

Measured result: **rejected and reverted**. Regression remained 21/21 PASS, but
the routed AXI wrapper changed from WNS `+0.082 ns` to `-0.011 ns`; LUT cells
increased from 48,540 to 48,935 and FF cells from 32,861 to 32,883. The former
AHB broadcast path was no longer worst, but the new core-to-D-cache path failed
timing. A synthesis hint that merely changes placement is not a robust system
improvement.

## Checkpoint 5 — eight AHB response buffers

Change: retain each adapter's existing one-entry request latch, and add one
registered response slot for each of the eight L1 masters in
`ahb_lite_arbiter_8m1s`. The arbiter records the owner of an accepted AHB
address phase, captures `S_HRDATA/S_HRESP` only when that data phase completes,
and pulses `M_HREADY` only for the owning master. This replaces the direct
32-bit response broadcast to all eight masters. It adds one response cycle;
the existing adapters already serialize transactions and do not issue a new
request until the current response completes.

Verification:

- `tb_ahb_arbiter` PASS, including slave wait-state, response-data/error
  ownership, and one-cycle response-valid checks:
  `reports/xsim-one-tb_ahb_arbiter/run.log`.
- `tb_coherence_ahb` PASS through cold read, RFO, modified-owner snoop,
  invalidation, dirty eviction, and concurrent-request cases:
  `reports/xsim-one-tb_coherence_ahb/run.log`.
- Full active regression 21/21 PASS:
  `reports/xsim-active-cache-20261103-092319/summary.md`.
- Isolated arbiter route at 9.800 ns:
  `reports/ooc-ppa-ahb_lite_arbiter_8m1s-20261103-092558/summary.md`.
  WNS `+5.929 ns`, hold `+0.228 ns`, 327 LUT, 291 FF, 0 BRAM.
- Integrated AXI-wrapper route at 9.800 ns:
  `reports/ooc-ppa-quad_core_axi_wrapper_ahb-20261103-092750/summary.md`.
  WNS `+0.174 ns`, hold `+0.052 ns`, 48,548 LUT, 33,134 FF, 218 BRAM,
  and zero unconstrained internal endpoints.

Measured delta versus the Checkpoint-3 integrated baseline: WNS improves by
`0.092 ns`; LUT increases by 8 (`0.016%`); FF increases by 273 (`0.831%`);
BRAM is unchanged. The old shared-AHB-response broadcast path is no longer
critical. The new worst path is local to core 1, from the I-cache lookup-address
register to the CSR trap `mcause` clock enable. **Accepted and retained.**

## Checkpoint 6 — control-block boundary audit

Source tracing from `quad_core_soc_ahb` confirms the active ownership split:

- `ahb_lite_arbiter_8m1s` alone selects one of the eight AHB masters, holds the
  grant through completion, and routes the registered response to its owner.
- `cache_controller_mmu` is instantiated with
  `EXTERNAL_REQUEST_ARBITER=1`; its direct per-core request inputs are tied off,
  so the legacy internal round-robin path cannot decide an active request.
- `cache_controller_mmu` intentionally combines the MSI coherence FSM, snoop
  scoreboard, L2 command sequencing, refill/writeback and external-memory line
  engine. This matches the adviser-requested combined cache/coherence control
  block rather than two competing controllers.
- `l2_cache` remains a peer storage/directory block. `coherence_manager` is only
  a legacy compatibility facade with an internal L2 for older tests.

No RTL interface or FSM refactor was made: it would add verification risk
without correcting an active ownership defect. Stale architecture labels were
updated and the SVGs regenerated from
`docs/architecture/generate_architecture_svgs.mjs` so the diagrams now show
`8 AHB masters -> 8M1S arbiter -> cache/coherence controller <-> L2`.

## Checkpoint 7 — explicit L2 miss/refill proof

`tb_quad_core_soc_ahb_behavior` now contains a transaction scoreboard around
the active four-core hierarchy. It associates `l2_resp_valid` with a pending
read lookup (write acknowledgements are deliberately excluded), starts a refill
on a lookup miss, counts physical-memory reads, and verifies that a 256-bit L2
line is installed only after exactly eight 32-bit read requests.

Evidence:

- Active hierarchy test including `TC-SOC-007`: PASS:
  `reports/xsim-one-tb_quad_core_soc_ahb_behavior/run.log`.
- Full active RTL regression after the accepted arbiter change: 21/21 PASS:
  `reports/xsim-active-cache-20261103-095756/summary.md`.

This proves the implemented cold-miss data path is
`memory (8 x 32-bit) -> controller line buffer (256-bit) -> L2 install -> L1
response`; it is not merely inferred from successful software execution.

## Checkpoint 8 — pack the L2 directory into block RAM

Root cause: L2 data already used explicit XPM block RAM, but tag, valid, dirty,
sharer and replacement metadata were 21 separate 4096-entry distributed arrays
per way. The isolated baseline therefore used 8,192 `RAMD64E` primitives and
4,481 LUT cells despite already having a registered lookup pipeline.

Change: pack each way's metadata into one `4096 x 21` synchronous XPM block RAM
with `{tag, sharers, dirty, valid}` entries, plus one `4096 x 2` block RAM for
LRU. The existing lookup and maintenance stages absorb the one-cycle synchronous
read; no external interface or controller state was added. Initialization,
fill/update and maintenance invalidation use explicit single-port writes.

Verification:

- Dirty-victim error recovery test PASS:
  `reports/xsim-one-tb_coherence_error/run.log`.
- Active four-core AHB hierarchy, including exact 8-word refill proof, PASS:
  `reports/xsim-one-tb_quad_core_soc_ahb_behavior/run.log`.
- Full active regression 21/21 PASS:
  `reports/xsim-active-cache-20261103-100656/summary.md`.

Measured results:

| Scope | Version | WNS (ns) | LUT | FF | BRAM tiles | RAMD64E |
|---|---|---:|---:|---:|---:|---:|
| L2 OOC | distributed metadata | +0.782 | 4,481 | 1,510 | 114 | 8,192 |
| L2 OOC | packed block RAM | +0.737 | 1,809 | 1,508 | 125 | 0 |
| Integrated AXI wrapper | after AHB response buffers | +0.174 | 48,548 | 33,134 | 218 | 8,384 |
| Integrated AXI wrapper | packed L2 metadata | +0.214 | 45,937 | 33,139 | 229 | 192 |

Evidence:

- `reports/ooc-ppa-l2_cache-20261103-100358/summary.md`.
- `reports/ooc-ppa-quad_core_axi_wrapper_ahb-20261103-100935/summary.md`.

Integrated delta: LUT `-2,611` (`-5.38%`), FF `+5`, BRAM `+11` tiles,
RAMD64E `-8,192`, and WNS `+0.040 ns`. The design uses 229/265 conservative
BRAM tiles and has zero unconstrained internal endpoints. **Accepted and
retained.** The current system critical path is now local to core 2, from the
I-cache lookup-address register through 22 logic levels to the program-counter
register, rather than the L2 directory or shared AHB response.

## Checkpoint 9 — decouple CSR redirect target from external stall

Trial: keep `TrapTakenM` and every architectural CSR/trap commit gated by
`Stall_Core_External`, but compute the combinational `TrapPCM` target from the
ungated trap/return request. The intent was to prevent the I-cache-ready to
external-stall signal from traversing the CSR target mux and fetch PC adder
while the PC register itself is stalled.

Screening and verification:

- Isolated `core_l1_wrapper` route moved the former 22-level PC path out of the
  critical position and produced WNS `+1.017 ns` at 9.800 ns:
  `reports/ooc-ppa-core_l1_wrapper-20261103-180444/summary.md`.
- CSR trap test PASS: `reports/xsim-one-tb_csr_trap/run.log`.
- Full active regression 21/21 PASS:
  `reports/xsim-active-cache-20261103-181304/summary.md`.
- Active four-core hierarchy, including exact 8-word L2 refill, PASS:
  `reports/xsim-one-tb_quad_core_soc_ahb_behavior/run.log`.

Integrated route result:

| Version | WNS (ns) | Hold (ns) | LUT | FF | BRAM tiles | RAMD64E |
|---|---:|---:|---:|---:|---:|---:|
| Checkpoint 8 authority | +0.214 | +0.011 | 45,937 | 33,139 | 229 | 192 |
| CSR redirect trial | +0.036 | +0.055 | 46,041 | 33,142 | 229 | 192 |

Evidence:
`reports/ooc-ppa-quad_core_axi_wrapper_ahb-20261103-181701/summary.md`.
The trial passed timing at the 102.041 MHz target and routed with zero failed
nets, but integrated WNS regressed by `0.178 ns`, LUT increased by 104 and FF
increased by 3. The critical path merely moved to a 16-level core-to-D-cache
request path dominated by routing delay. **Rejected and reverted.** Checkpoint
8 remains the accepted integrated authority.

## Checkpoint 10 — split I-cache response and miss-control cones

Trial: duplicate the registered-address equality and tag-hit comparators so the
timing-critical `cpu_valid` response did not share a logic cone with the wide
miss-request capture controls. `keep` attributes preserved the two cones. No
interface, FSM state or cache latency changed.

Verification and screening:

- I-cache failed-fill/retry path PASS:
  `reports/xsim-one-tb_cache_error_path/run.log`.
- Architectural `FENCE.I`, D-cache clean and I-cache invalidation PASS:
  `reports/xsim-one-tb_cache_fence_i/run.log`.
- Isolated I-cache route:
  `reports/ooc-ppa-l1_icache-20261103-221350/summary.md`.

The isolated result changed from WNS `+2.442 ns`, 2,284 LUT and 1,201 FF to
WNS `+2.396 ns`, 2,283 LUT and 1,201 FF. Since the target block lost
`0.046 ns` of setup margin before integration, the trial failed the screening
gate; no full-system route was warranted. **Rejected and reverted.**

## Checkpoint 11 — routed Fmax lower-bound validation

No RTL changed in this checkpoint. Each number below is an achieved routed
frequency on `xc7z030fbv676-1`: route completed with zero failed nets and both
setup and hold slack are positive at the stated constraint. The looser
"timing-derived Fmax estimate" in each generated summary is not claimed as an
achieved frequency.

| Active block | Period | Achieved lower bound | Setup WNS | Hold | Evidence |
|---|---:|---:|---:|---:|---|
| One CPU core (`physical_core_wrapper`) | 8.300 ns | 120.482 MHz | +0.442 ns | +0.083 ns | `reports/ooc-ppa-physical_core_wrapper-20261103-223920/summary.md` |
| AHB arbiter (`ahb_lite_arbiter_8m1s`) | 3.000 ns | 333.333 MHz | +0.620 ns | +0.196 ns | `reports/ooc-ppa-ahb_lite_arbiter_8m1s-20261103-224235/summary.md` |
| AHB L1 adapter (`ahb_lite_l1_adapter`) | 5.000 ns | 200.000 MHz | +0.832 ns | +0.083 ns | `reports/ooc-ppa-ahb_lite_l1_adapter-20261103-224440/summary.md` |
| Combined cache/coherence controller (`cache_controller_mmu`) | 7.200 ns | 138.889 MHz | +0.813 ns | +0.095 ns | `reports/ooc-ppa-cache_controller_mmu-20261103-224712/summary.md` |
| Shared L2 (`l2_cache`) | 9.200 ns | 108.696 MHz | +0.550 ns | +0.080 ns | `reports/ooc-ppa-l2_cache-20261103-225156/summary.md` |
| Full 4-core AXI wrapper | 9.700 ns | 103.093 MHz | +0.460 ns | +0.028 ns | `reports/ooc-ppa-quad_core_axi_wrapper_ahb-20261103-225604/summary.md` |

The active architecture does not instantiate a second standalone coherence
controller: MSI snoop, refill, writeback and coherence ownership are combined
inside `cache_controller_mmu`. Therefore that active block is measured once;
the legacy `coherence_manager` compatibility wrapper is not presented as a
separate system limit.

The slowest standalone lower bound is L2 at 108.696 MHz, but integration and
physical routing reduce the whole-system result. The current SoC sign-off clock
is therefore **103.093 MHz (9.700 ns)**, not the minimum of timing-derived
estimates. The routed integrated critical path runs from core 2 I-cache metadata
BRAM to the core 2 fetch PC input; this agrees with Vivado's warnings that the
cache BRAM read path cannot absorb an optional output register automatically.
Any next timing optimization should first pipeline or restructure that exact
I-cache-to-fetch path, then repeat targeted functional tests and full routing.

Because this is an out-of-context wrapper route, AXI top-level ports report
missing `HD.PARTPIN_LOCS`. Final board sign-off still requires a concrete board,
pin constraints and the selected external AXI IP topology. Internal routed
timing, hold and connectivity are valid for this checkpoint; external I/O delay
sign-off is intentionally out of scope.

## Checkpoint 12 — pipeline L1 I-cache metadata-to-fetch feedback

Objective: remove the integrated critical path from the I-cache metadata BRAM,
through hit/stall/trap control, back to the fetch PC, and validate a 300 MHz
lower bound for the isolated I-cache on `xc7z030fbv676-1`.

Localized RTL changes in `rtl/cache/l1_icache.v`:

- enable the XPM BRAM output register (`READ_LATENCY_A=2`) and delay the lookup
  address/valid state by the same two cycles;
- split tag/valid comparison from the 256-bit line and 8:1 instruction-word
  selection with explicit result registers;
- replace the direct 512:1 valid/LRU read with two registered balanced stages:
  32 parallel groups of 16 sets, followed by one 32:1 group selection;
- register fill completion address/data/error so a failed fill is returned for
  the exact request and is never installed as a cache hit;
- preserve the module ports, blocking miss protocol, replacement policy and
  whole-cache invalidation semantics.

Routed results:

| Scope | Target | Setup WNS | Hold | LUT | FF | BRAM tiles | Critical path |
|---|---:|---:|---:|---:|---:|---:|---|
| Isolated `l1_icache` | 3.333 ns / 300.030 MHz | +0.020 ns | +0.064 ns | 2,626 | 1,967 | 9 | miss/flush state to valid-bit reset |
| `core_l1_wrapper` | 8.300 ns / 120.482 MHz | +0.113 ns | +0.060 ns | 9,748 | 6,085 | 26 | core ALU result to D-cache request line |

Evidence:

- `reports/ooc-ppa-l1_icache-20261104-235218/summary.md`.
- `reports/ooc-ppa-core_l1_wrapper-20261105-001339/summary.md`.
- `reports/xsim-active-cache-20261105-002557/summary.md`: 21/21 PASS.
- `reports/xsim-one-tb_core_l1_physical_subsystem/run.log`: physical core/L1
  execution and maintenance checks PASS on the final RTL.

The isolated I-cache therefore **achieves the requested 300.030 MHz routed
lower bound**. The integrated metadata-to-fetch-PC path is no longer critical;
the one-core wrapper now meets 120.482 MHz and is limited by a core-to-D-cache
request path. This does not establish a 300 MHz CPU or SoC clock. The current
four-core system authority remains 103.093 MHz until the D-cache/core, L2 and
full wrapper are optimized and rerouted.

Tradeoff: a cache hit now passes through additional registered lookup stages.
The current core is blocking and advances the fetch PC only when
`Instr_ValidF` is asserted, so this raises hit latency and can reduce IPC even
though Fmax improves. This checkpoint is accepted for the stated timing-path
objective, but application throughput must be measured before claiming a net
performance gain. A future throughput-oriented step should decouple the fetch
request/response handshake or allow pipelined outstanding fetch addresses.

## Measurement record template

### `<module>` — `<date>`

1. Critical path or bottleneck:
2. Root cause:
3. Proposed/localized optimization:
4. Expected area/timing/power impact:
5. Verification and measured result:

