# Compiled four-core workload

Generated: Fri Nov 13 17:21:59 +0700 2026

- Result: 2/2 PASS
- Program image: `quad_cache_workload.mem` (RV32IMA, four harts at 0x1000)
- Workload SAIF: disabled

| Protocol | Status | Statistics | SAIF bytes |
|---|---:|---|---:|
| MSI | PASS | `QUAD_WORKLOAD_STATS protocol=MSI cycles=66486 retired=22074 ipc_milli=332 l1_accesses=4242 l1_hits=3405 l1_misses=837 miss_rate_ppm=197312 ahb_transfer_cycles=7412 ahb_occupied_cycles=40596 ahb_util_ppm=610594 axi_read_txn=169 axi_write_txn=4 axi_read_beats=1352 axi_write_beats=4 axi_burst_reads=169 axi_burst_writes=0 l2_hits=757 l2_misses=169 snoops=1372` | 0 |
| MESI | PASS | `QUAD_WORKLOAD_STATS protocol=MESI cycles=66486 retired=22074 ipc_milli=332 l1_accesses=4242 l1_hits=3405 l1_misses=837 miss_rate_ppm=197312 ahb_transfer_cycles=7412 ahb_occupied_cycles=40596 ahb_util_ppm=610594 axi_read_txn=169 axi_write_txn=4 axi_read_beats=1352 axi_write_beats=4 axi_burst_reads=169 axi_burst_writes=0 l2_hits=757 l2_misses=169 snoops=1372` | 0 |

> `ipc_milli=1000` means aggregate IPC=1.000; rates ending in `_ppm` are parts per million.
