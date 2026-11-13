# Compiled four-core workload

Generated: Fri Nov 13 23:46:18 +0700 2026

- Result: 2/2 PASS
- Program image: `quad_cache_workload.mem` (RV32IMA, four harts at 0x1000)
- Workload SAIF: disabled

| Protocol | Status | Statistics | SAIF bytes |
|---|---:|---|---:|
| MSI | PASS | `QUAD_WORKLOAD_STATS protocol=MSI cycles=67238 retired=22191 ipc_milli=330 l1_accesses=4279 l1_hits=3429 l1_misses=850 miss_rate_ppm=198644 ahb_transfer_cycles=7556 ahb_occupied_cycles=41292 ahb_util_ppm=614117 axi_read_txn=174 axi_write_txn=4 axi_read_beats=1392 axi_write_beats=4 axi_burst_reads=174 axi_burst_writes=0 d_reads=443 rfos=407 writebacks=0 l2_hits=770 l2_misses=174 snoops=1384 controller_busy_cycles=45018 etom_reads=4 etom_rfos=4 etom_s_grants=4 etom_e_grants=0` | 0 |
| MESI | PASS | `QUAD_WORKLOAD_STATS protocol=MESI cycles=67082 retired=22191 ipc_milli=330 l1_accesses=4279 l1_hits=3433 l1_misses=846 miss_rate_ppm=197709 ahb_transfer_cycles=7524 ahb_occupied_cycles=41164 ahb_util_ppm=613637 axi_read_txn=174 axi_write_txn=4 axi_read_beats=1392 axi_write_beats=4 axi_burst_reads=174 axi_burst_writes=0 d_reads=443 rfos=403 writebacks=0 l2_hits=766 l2_misses=174 snoops=1384 controller_busy_cycles=44874 etom_reads=4 etom_rfos=0 etom_s_grants=0 etom_e_grants=4` | 0 |

> `ipc_milli=1000` means aggregate IPC=1.000; rates ending in `_ppm` are parts per million.

## Exclusive-to-Modified evidence

Each hart cold-loads one private 32-byte line, then stores to that same line.
Counters below are accepted controller transactions/read grants for only those four lines.

| Protocol | Cold reads | S grants | E grants | RFOs | Total cycles | Total RFOs |
|---|---:|---:|---:|---:|---:|---:|
| MSI | 4 | 4 | 0 | 4 | 67238 | 407 |
| MESI | 4 | 0 | 4 | 0 | 67082 | 403 |

> Measured MESI reduction: `4` RFOs in the isolated E-to-M phase and `4` RFOs over the complete workload.
