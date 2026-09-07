# Phase 2 — 4-core system: interconnect, shared L2, coherence

Builds on Phase 1 (see `README_PHASE1.md`) — same `core_top` per core,
now x4, sharing one L2 and one DRAM through a new interconnect, with a
coherence mechanism so writes from one core become visible to the others.

## What this delivers

```
   core_top[0]  core_top[1]  core_top[2]  core_top[3]
   (I$+D$)      (I$+D$)      (I$+D$)      (I$+D$)
       \            \            /            /
        \____________\  interconnect  /______/
                     (8:1 round-robin arbiter
                      + coherence snoop broadcast)
                              |
                          L2_Cache (512KB, 2-way, 8192 sets)
                              |
                         mem_model256 (DRAM, sim only)
```

- `multicore/interconnect.sv` — arbitrates 8 requester ports (each
  core's I-cache and D-cache miss/write-through traffic) down to one L2
  port; broadcasts a coherence invalidate to sibling D-caches whenever a
  D-side write completes.
- `multicore/L2_TagArray.sv`, `L2_DataArray.sv`, `L2_CacheController.sv`,
  `L2_Cache.sv` — the shared L2, structured like the L1 caches but
  whole-line (256-bit) transactions only, 8192 sets (512KB with 32B
  lines), write-allocate + write-back to DRAM.
- `multicore/multicore_top.sv` — instantiates 4x `core_top` (each with
  a distinct `RESET_PC` so they boot into separate program regions),
  the interconnect, the L2, and one DRAM model.
- `multicore/tb_multicore_top.sv` — 4 parallel programs (one per core)
  plus a genuine producer/consumer coherence test between core 0 and
  core 1 (see below).

## Coherence scheme (what it is, and isn't)

This is a simple **invalidate-broadcast**, not a full MESI/MOESI
directory protocol:

1. Every store from a private D-cache is now **write-through** (see the
   `D_CacheController.sv` change below) — it always pushes the updated
   line to L2 before the CPU is told the store completed. L2 is always
   the freshest copy.
2. Whenever the interconnect sees a D-side write complete, it pulses
   `snoop_en` + the line's address to every *other* core's D-cache
   `TagArray` (new port, see below), which drops that line if it has it
   cached.
3. A core that had a stale cached copy simply misses on its next access
   to that line and re-fetches the fresh data from L2.

This is correct for the single-writer / multiple-reader pattern the
testbench exercises (and for programs that don't have two cores racing
to write the *same* line without their own synchronization), but it is
**not** a general MESI protocol — there's no shared/exclusive/modified
state tracking, no ownership transfer between private caches (every
line's true home is always L2), and no handling of two cores writing
the same line back-to-back without an intervening read (the last
write-through wins, which is coherent but not necessarily what a
real multi-writer program would want without its own locking). A
directory-based MESI upgrade is a reasonable next step once this is
verified working.

## Changes to existing files

- **`TagArray.sv`**: added a `snoop_en`/`snoop_index`/`snoop_tag` port.
  On a snoop hit, the matching way's valid bit is cleared. `I_Cache.sv`
  ties this off (instructions aren't coherence traffic here);
  `D_Cache.sv` exposes it as a byte-address `snoop_addr`/`snoop_en` pair
  and decodes it into index/tag internally.
- **`D_CacheController.sv`**: stores no longer just mark the local line
  dirty and stop — a new `WRITE_THROUGH` state pushes the updated line
  to L2 (via the same `mem_req_*` port, now connected to the
  interconnect instead of directly to DRAM) before acking the CPU. This
  is what makes the invalidate-broadcast coherence scheme correct (see
  above) — without it, an invalidated sibling would refetch from L2 and
  still see stale data.
- **`MMU.sv`** / **`core_top.sv`**: threaded the new `snoop_en` /
  `snoop_addr` ports through from the top level down to `D_Cache`.
- **`pc_unit.v`** / **`core_top.sv`**: added a `RESET_PC` parameter so
  `multicore_top.sv` can boot each core into its own program region
  (0x0000, 0x1000, 0x2000, 0x3000 for cores 0..3). Previously every core
  would have booted at address 0 and executed core 0's program.
- **`RV32/source/tb_core_top.sv`** (Phase 1 testbench): updated to tie
  off the new `snoop_en`/`snoop_addr` inputs (`1'b0`/`32'b0`) — Phase 1
  is still single-core, no coherence traffic. Still passes as before.

## Known pre-existing bug found while writing the coherence test

`D_CacheController.sv` (inherited from before Phase 1, not something
either phase introduced) selects its within-line storage slot using
only `cpu_addr[4:3]` — an 8-byte granularity — and always writes/reads
the **low 32 bits** of that 64-bit slot. `cpu_addr[2]` is never
consulted. Practically: **two 32-bit addresses only 4 bytes apart (e.g.
0x100 and 0x104) alias to the exact same storage** and a store to one
will silently corrupt the other. This didn't show up in Phase 1's test
program (which never had two live 32-bit values that close together),
but it did show up immediately when writing Phase 2's shared
`SHARED_DATA` / `SHARED_FLAG` test (originally 4 bytes apart) — the flag
write was clobbering the data write. Worked around in
`tb_multicore_top.sv` by spacing every test address >=16 bytes apart;
documented instead of fixed because the real fix (widen the D-cache's
offset to `cpu_addr[4:2]` and patch at 32-bit granularity instead of
64-bit) touches the same FSM the write-through change just modified,
and deserves its own focused pass + re-verification rather than being
bundled in here. **This should be the first thing addressed in Phase 3.**

## How to simulate in Vivado

Add as **Design Sources** (in addition to everything already added for
Phase 1 — `MMU.sv` and friends are shared/modified, re-add if your
project doesn't already have the edited versions):

- Everything from Phase 1's design-source list (`MMU.sv`, `I_Cache.sv`,
  `D_Cache.sv`, `I_CacheController.sv`, `D_CacheController.sv`,
  `TagArray.sv`, `DataArray.sv`, `Comparator.sv`, `decode.v`,
  `execute.v`, `write_back.v`, `pc_unit.v`, `core_top.sv`)
- `multicore/L2_TagArray.sv`
- `multicore/L2_DataArray.sv`
- `multicore/L2_CacheController.sv`
- `multicore/L2_Cache.sv`
- `multicore/interconnect.sv`
- `multicore/multicore_top.sv`

Add as **Simulation Sources**:

- `RV32/source/mem_model.sv` (reused as-is for the DRAM behind L2)
- `multicore/tb_multicore_top.sv`

Set `tb_multicore_top` as the simulation top, run Behavioral Simulation,
then in the Tcl Console: `run -all`. Watch for `PHASE2 TEST: PASS` /
`FAIL`. If core 1 never stops spinning, the timeout message will tell
you — that specifically points at the coherence snoop path
(`interconnect.sv` -> `TagArray.sv`).

## Target ISA update: RV32IMA (F dropped)

Decision after Phase 2: the target is now **RV32IMA**, not RV32IFMA — F
(floating point) is dropped as too heavy for the remaining scope. This
actually helps Phase 3: no FPU block needed from the RV64 reference
folder, and A (atomics) is arguably more valuable for a 4-core system
than F anyway, since it gives programs a real synchronization primitive
(LR/SC or AMOs) instead of relying on coherence alone — the Phase 2
testbench's core0/core1 handshake is a *spin-flag* pattern that happens
to work because there's exactly one writer per address, but it's not a
real lock. A-extension support would let a future test use an actual
atomic read-modify-write for mutual exclusion.

## Proposed Phase 3 scope

1. Fix the `cpu_addr[2]`-blind D-cache aliasing bug described above.
   Do this first — both M and A extension work will add more load/store
   traffic that's likely to hit it again otherwise.
2. Add the **M extension** (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU) to
   `decode.v` (opcode 0110011 with funct7=0000001) and `execute.v` (a
   multiplier/divider block — single-cycle combinational multiply is
   fine to start; DIV/REM will need a multi-cycle unit + a stall signal
   into `core_top`'s retire logic, same pattern already used for cache
   misses).
2. Add the **A extension** (LR.W/SC.W at minimum, AMOSWAP/AMOADD/... if
   time allows) — needs a new decode case (opcode 0101111), and at the
   D-cache/interconnect level, a reservation register per core for
   LR/SC, or an atomic-RMW request type the interconnect can service
   without another core's request interleaving in between.
3. Add the sleep/active power-mode FSM per core (per your architecture
   diagram) — likely gates the core's clock/requests and lets the
   interconnect skip a sleeping core when arbitrating.
4. Upgrade coherence from invalidate-broadcast to a real MESI directory
   if multi-writer contention becomes something you need to support
   beyond what LR/SC-based locking gives you.
5. Rename/re-tag the project deliverables from "IFMA" to "IMA" in the
   thesis document/slide once the RTL matches (worth doing early so
   there's no mismatch between what's built and what's written up).
