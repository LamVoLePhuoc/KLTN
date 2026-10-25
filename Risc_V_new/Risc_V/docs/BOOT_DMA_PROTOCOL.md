# Boot and non-coherent DMA maintenance protocol

The bootable top levels expose `boot_ctrl` through AXI4-Lite. The actual base
address is assigned by the Vivado address editor; offsets below are relative to
that base.

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x0` | `CTRL` | R/W | Bit 0 is write-one/sticky `GO`; it releases the RISC-V subsystem from reset. |
| `0x4` | `STATUS` | R | Bit 0 mirrors `GO`. |
| `0x8` | `RESULT` | R/W | Software-defined 32-bit workload result; byte strobes are honored. |
| `0xC` | `CACHE` | R/W | Write bit 0 to request global clean/invalidate. Read bit 0 `BUSY`, bit 1 latched `DONE`, bit 2 sticky `ERROR`, bit 3 `REJECTED`. |

`CACHE` commands are accepted only after `GO=1` and while `BUSY=0`. An accepted
command clears the previous `DONE` and `REJECTED` bits and emits exactly one
maintenance pulse. A rejected command does not disturb an operation already in
progress. `DONE` remains readable until the next accepted command.

## PS/loader boot sequence

1. Keep `GO=0` while the PS copies the RISC-V image from SD to DRAM.
2. Complete and verify the PS-side DMA or file copy.
3. Write `GO=1` through `CTRL`.
4. Poll `STATUS.GO` if software needs readback confirmation.

No cache maintenance is needed before the first `GO`: the complete RISC-V
subsystem, including L1/L2 state, is held in reset while the image is copied.

## DMA sequence after the RISC-V cores are running

There are two supported control paths. Use exactly one for a transfer.

### External/PS DMA with manual maintenance

1. Software must quiesce every core that can access the DMA buffer, using a lock,
   barrier, or ownership protocol appropriate to the workload.
2. The PS writes `1` to `CACHE` and polls it.
3. Abort the transfer if `REJECTED=1`. If `ERROR=1`, keep the buffer quiescent and
   reset/recover the subsystem; a maintenance timeout deliberately does not fake
   completion.
4. Start DMA only after observing `DONE=1` and `BUSY=0`.
5. Wait for DMA completion.
6. Issue and complete a second `CACHE` command before allowing any RISC-V core to
   consume data written by DMA.
7. Release the software ownership/lock for the buffer.

The first pass writes back Modified CPU data before DMA reads memory. The second
pass invalidates clean CPU copies that may be stale after DMA writes. This is a
safe global, coarse-grained protocol; it does not turn the DMA into a line-level
MSI coherence master and software must not access the buffer during the transfer.

### Source-level `soc_dma_controller`

The RTL DMA in `rtl/dma/` automates the same ordering:

1. Software establishes exclusive buffer ownership and the integration logic
   asserts `buffer_quiesced`.
2. Program source (`0x08`), destination (`0x0c`) and aligned byte length
   (`0x10`), then write `CONTROL.START` at `0x00`.
3. The coordinator completes pre-maintenance, runs the AXI4 copy, and completes
   post-maintenance. Poll `STATUS` at `0x04`: bit 0 `BUSY`, bit 1 sticky `DONE`,
   bit 2 `ERROR`, bits 10:8 error code.
4. Release buffer ownership only after `DONE=1`, `BUSY=0`, and `ERROR=0`.

`software/ps_loader/soc_dma.h` provides the register definition and polling
helper. This controller is a non-coherent AXI master; it is not a line-level MSI
snoop agent.

## Failure semantics

- A writeback error retains the dirty D-cache line and sets `ERROR`.
- A watchdog timeout sets `ERROR` while leaving `BUSY` asserted; automatic abort
  would be unsafe because the memory interface has no cancel/drain mechanism.
- `ERROR` is sticky until subsystem reset. Software must not start DMA merely
  because `DONE` was observed if `ERROR` is also set.
- A source read error aborts before any destination burst for that buffered
  chunk. A write response error still executes post-maintenance because earlier
  destination beats may already have reached memory.
