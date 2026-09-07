# Phase 1 — Single-core RV32I + MMU (L0/L1 private cache), verified

## What this delivers

A complete, self-contained single RV32I core wired to the existing
`MMU.sv` private cache subsystem (I-cache + D-cache, 2-way set-associative,
32 sets, 32-byte lines), plus a self-checking testbench you can run in
Vivado. This is the foundation Phase 2 will replicate ×4 and connect
through a shared interconnect + coherence manager.

## New files (`MMU/RV32/source/`)

- `pc_unit.v` — PC register and next-PC mux.
- `core_top.sv` — top-level integration: `pc_unit` + `decode.v` +
  `execute.v` + `write_back.v` + `MMU.sv`, with correct stall handling.
- `mem_model256.sv` (`mem_model.sv`) — behavioral backing memory for
  simulation, standing in for the shared L2/DRAM until Phase 2's
  interconnect is built.
- `tb_core_top.sv` — self-checking testbench (hand-assembled RV32I
  program exercising ADDI, ADD, SW, LW, BEQ, JAL, JALR).

## Status: PASS

`tb_core_top` (Vivado XSIM, `run -all`) prints `PHASE1 TEST: PASS` — all
11 checked registers match, covering ADDI, ADD, SW, LW, BEQ (both taken
and not-taken), JAL, and JALR.

## Bugs found and fixed in the existing pipeline

The old `fetch.v` / `decode.v` / `execute.v` / `write_back.v` chain (as
wired by `rv32i.v`) had five bugs that would have broken any real
program. All five were found by actually simulating in Vivado XSIM and
tracing register/PC mismatches back to their source — not by inspection
alone, so it's worth running the testbench yourself after any further
edits to this datapath.

1. **PC never stalled.** `fetch.v` updated `pc_reg` on every clock edge
   regardless of `cpu_ready`, so on a cache miss the core would race
   ahead and fetch garbage. `core_top.sv` now gates the PC (and the
   register-file write) with `instr_done = i_cpu_ready & (needs_mem ?
   d_cpu_ready : 1)`, computed each cycle from the currently fetched
   instruction.
2. **JAL/JALR always jumped to address 0.** `mux_pc`'s case for
   `pc_sel==2'b11` (used by both JAL and JALR) returned a hardcoded
   `32'h0` instead of the ALU result (which is exactly the computed jump
   target: `PC+imm` for JAL, `rs1+imm` for JALR). Fixed in the new
   `pc_unit.v`.
3. **`write_back.v`'s `wb_sel` encoding didn't match `decode.v`'s
   `Controller`.** LOAD used `wb_sel=2'b10` expecting `data_mem`, but
   `write_back.v` returned `pc_plus_4` for that code; JAL/JALR used
   `wb_sel=2'b11` expecting `pc_plus_4`, but the `default` case returned
   `0`. Both loads and jump-and-link would have written the wrong value
   into `rd`. Fixed by re-aligning the case statement.
4. **`execute.v`'s `b_sel` mux was inverted.** `decode.v`'s own comments
   say `b_sel=0` selects the immediate and `b_sel=1` selects `rs2`, but
   `execute.v` implemented `src_B = b_sel ? Imm : DataB` — the opposite.
   Every immediate-using instruction (ADDI, LOAD, STORE, JAL, JALR, Bxx)
   was reading `rs2` instead of the immediate, and R-type instructions
   were adding in the (usually zero) immediate instead of `rs2`. This is
   what made JAL's target collapse to `PC + 0 = PC` — an instant
   self-loop — when this was first tested. Fixed by flipping the mux.
5. **`execute.v`'s LUI case double-shifted.** `decode.v` already builds
   the U-type immediate as `{instr[31:12], 12'b0}` (pre-shifted into
   position), but the ALU's `4'b1010` (LUI) case did `in2 << 12` again,
   corrupting every LUI result. Fixed to pass `in2` through unshifted.
6. **`decode.v`'s `branch_signal` didn't match what `execute.v` expected.**
   For B-type instructions, `branch_signal_reg = {funct7, funct3}` used
   `instr[31:25]` as if it were a funct7 field — but for branches those
   bits are part of the offset immediate (`imm[12]`, `imm[10:5]`), not a
   funct7. `execute.v`'s case statement, meanwhile, matches against
   constants like `10'b1100011000`, whose upper 7 bits are the B-type
   *opcode* (`7'b1100011`). The two only agreed by coincidence, so
   `branch_taken` was almost always 0 — no branch ever actually took,
   including the `BEQ x0,x0,0` self-loop the testbench uses to detect
   "program finished," which sent the core running off into
   uninitialized memory instead of halting. Fixed by packing
   `{opcode, funct3}` instead.

Also added: `MMU.sv` now exposes `d_cpu_ready` as a real output port —
previously it was declared as an internal signal "not used, floating for
future use" and had no way to reach the core, so a load/store could
never actually be told "not ready yet."

## What was deliberately *not* reused

`RV32/source/Cache.v`, `CacheController.v`, `memory_access.v`,
`rv32i.v`, `core_wrapper.v`, `soc.v`, and the `AXI_*` /
`sdram_wrapper.v` files are the **older** pipeline path. They're left in
place for reference, but `core_top.sv` bypasses them: `memory_access.v`
ties `cpu_ready` and the module's own `mem_ready` input to the *same*
net through two different instance ports, which is a multiple-driver
conflict, and the `AXI_Interconnect` / `sdram_wrapper` pairing has data
width mismatches (32-bit vs. the cache's 256-bit line interface) that
won't compile as-is. Untangling those was out of scope for getting a
verified core running; Phase 2's real interconnect will replace this
path entirely rather than repair it.

## How to simulate in Vivado

1. Create/open the project, add as simulation sources:
   - `MMU/MMU/*.sv` (`MMU.sv`, `I_Cache.sv`, `D_Cache.sv`,
     `I_CacheController.sv`, `D_CacheController.sv`, `TagArray.sv`,
     `DataArray.sv`, `Comparator.sv`)
   - `MMU/RV32/source/decode.v`, `execute.v`, `write_back.v`,
     `pc_unit.v`, `core_top.sv`, `mem_model.sv`, `tb_core_top.sv`
   - Do **not** add `rv32i.v`, `core_wrapper.v`, `fetch.v`,
     `memory_access.v`, `Cache.v`, `CacheController.v`, `soc.v`,
     `sdram_wrapper.v`, or the `AXI_*.v` files to this simulation set —
     they belong to the superseded path above and will produce
     duplicate-module or width-mismatch errors if mixed in.
2. Set `tb_core_top` as the simulation top module.
3. Run Behavioral Simulation. Watch the Tcl console: it prints a
   PASS/FAIL line per register plus a final
   `PHASE1 TEST: PASS` or `PHASE1 TEST: FAIL`.

## Known limitations of Phase 1 (by design, to be resolved in Phase 2+)

- Single core only — no interconnect, no coherence manager, no shared L2.
- Data-side CPU interface is 12 bits (`d_cpu_mem_addr`), i.e. a 4 KB
  addressable data window — matches the existing `MMU.sv` port as given;
  widening this (or adding a separate path to shared memory) is part of
  the multicore work.
- No CSRs, no exceptions/interrupts, no privilege modes.
- No sleep/active power-mode FSM yet (per your architecture diagram).
- RV32I only — F/M/A (IFMA) extension not yet integrated (the RV64
  reference folder has FPU building blocks that can be adapted).

## Proposed Phase 2 scope

1. Instantiate 4× `core_top`-style cores, each keeping its own private
   L1 (current `MMU.sv` instance).
2. Design the interconnect (arbitrated bus or crossbar) + a real shared
   L2 (512 KB, per your diagram) backed by a DRAM controller.
3. Add a coherence manager (start with a simple MSI directory or
   snooping protocol across the 4 private L1s).
4. Add the sleep/active mode FSM per core (clock-gate or freeze the
   core + gate its L1 requests when asleep).
5. Multicore testbench: a small parallel test program (e.g. increment a
   shared counter with load-store, or four independent cores each
   writing a known value to a distinct address) to prove coherence and
   the interconnect under contention.
6. Only after 1–5 are verified: extend the ISA to F/M/A.

Let me know when you've run Phase 1 in Vivado (or if it doesn't build/
pass) and I'll continue with Phase 2 — building the interconnect +
coherence manager + replicating this core to 4 instances.
