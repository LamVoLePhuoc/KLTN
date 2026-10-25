# Source-level AXI DMA

`soc_dma_controller` is a small non-coherent memory-to-memory DMA subsystem for
the thesis SoC. It is ordinary RTL and does not depend on generated Vivado IP.

## Blocks

- `axi_lite_dma_regs.v`: AXI4-Lite programming/status registers. AW and W are
  accepted independently and a start request remains pending until accepted.
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

## AXI4-Lite register map

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
Connect `M_AXI` as another master of the system AXI fabric and `S_AXI` to the
control interconnect. `buffer_quiesced` is the hardware proof that software or
the producer/consumer protocol has stopped all CPU users of the buffer; tying it
high is only safe when that ownership rule is enforced in software.

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
