# Source-level AXI DMA

> Reference-only implementation. This directory is excluded from
> `rtl/files.f`, the Vivado `sources_1` fileset and the active regression.
> The active platform instantiates Xilinx `axi_cdma:4.1` below the CPU's AXI4
> boundary; do not add these files back to the four-core RTL source set.

`soc_dma_controller` is a small non-coherent memory-to-memory DMA subsystem for
the thesis SoC. It is ordinary RTL and does not depend on generated Vivado IP.

## Blocks

- `apb_dma_regs.v`: APB4 programming/status registers. The register page is
  zero-wait-state, supports byte strobes, and holds start pending until accepted.
- `dma_cache_coordinator.v`: orders buffer quiescence, global pre-flush, DMA,
  and global post-flush. A watchdog is diagnostic only; it never fabricates
  completion while cache or AXI traffic can still be outstanding.
- `axi_memcpy_dma.v`: aligned, full-width AXI4 INCR copy engine. One bounded
  read burst is buffered and then written, with no burst crossing a 4 KiB AXI
  boundary. A failed/malformed read burst is never written to the destination.
- `soc_dma_controller.v`: source-level integration top for the three blocks.

The intentionally blocking datapath trades peak bandwidth for deterministic
ordering and a small verification surface. `MAX_BURST_LEN` must be in `1..256`;
the current SoC wrapper uses a 32-bit AXI data path and requires source,
destination, and byte length to be four-byte aligned.

## APB register map

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | `CONTROL` | W | bit 0 start, bit 1 clear sticky status |
| `0x04` | `STATUS` | R | bit 0 busy, bit 1 done, bit 2 error, bits 10:8 error code |
| `0x08` | `SRC_ADDR` | R/W | source byte address |
| `0x0c` | `DST_ADDR` | R/W | destination byte address |
| `0x10` | `LENGTH` | R/W | aligned nonzero byte count |

Error codes are `0` none, `1` pre-flush, `2` DMA/AXI, `3` post-flush, `4`
watchdog and `5` rejected duplicate start.

`TIMEOUT_CYCLES` is an inactivity limit. During AXI copying, every accepted
address, data, or response beat restarts the timer, so a healthy multi-burst
copy is not incorrectly timed out merely because its total latency exceeds the
configured limit.

## Integration contract

Connect `cache_flush`, `cache_flush_busy`, `cache_flush_done`, and
`cache_flush_error` to the four-core aggregate cache-maintenance handshake.
Connect `M_AXI` as another master of the system AXI fabric and `S_APB` behind
an AXI-to-APB bridge (or a native APB master). `buffer_quiesced` is the hardware
proof that software or the producer/consumer protocol has stopped all CPU users
of the buffer; tying it high is only safe when that ownership rule is enforced
in software.

## Vivado IP packaging and Block Design

Run `scripts/package_soc_dma_ip.tcl` with Vivado 2022.2 to generate the reusable
IP-XACT core `kltn.local:user:soc_dma_controller:1.0` under
`ip_repo/soc_dma_controller_1_0`. The package exposes `S_APB`, `M_AXI`, `clk`,
and active-high `rst` as standard interfaces, plus the cache-maintenance and
status pins.

`scripts/build_soc_4core_trial.tcl` instantiates that IP with Xilinx
`axi_apb_bridge:3.0` configured for one APB4 slave. The CPU-visible AXI control
aperture is `0x4000_0000..0x4000_FFFF`; the register offsets above are unchanged.
The DMA data path remains an AXI4 master connected to the memory interconnect.
The bootable ZU5EV script uses the same topology, but its PS clock/reset and HPM
port still depend on the selected Genesys ZU board preset.

The external `AXI_to_APB_Bridge/` reference was reviewed but is not instantiated:
it implements a larger burst/clock-domain-crossing design, depends on additional
FIFO/decoder modules, and has not been protocol-verified in this repository. The
installed Xilinx bridge is used for the production Block Design path.

The DMA is deliberately not an MSI snoop master. Correctness therefore depends
on the coordinator's complete pre/post global maintenance sequence. After a DMA
write response error, post-flush is still mandatory because AXI does not promise
that no earlier destination beat reached memory.

`sim/tb_dma_end_to_end.v` checks programming, quiescence gating, cache ordering,
burst/4-KiB boundaries, copies, read-error write suppression, write-error
post-flush, and non-fabricated watchdog completion.

The supplied `DMA_reference` design was used only as a conceptual comparison
for command/status/count sequencing. Its legacy bidirectional buses, event
controls, and delay-based simulation constructs are not copied into this AXI4
implementation.
