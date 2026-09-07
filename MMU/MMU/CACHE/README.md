# CACHE architecture files

This folder contains the cache-side RTL scaffold for `ARCHITECTURE.png`.

## Files

- `SetAssociativeCache.sv`: reusable 2-way set-associative cache.
- `CacheController.sv`: blocking cache controller with parameterized tag/index/offset decoding.
- `CacheTagArray.sv`, `CacheDataArray.sv`, `CacheComparator.sv`: cache storage and hit logic.
- `SimpleCacheToAxiMaster.sv`: converts a cache-line request interface into one-beat AXI4 master transactions.
- `AxiSlaveToSimpleCache.sv`: converts one-beat AXI4 slave transactions into the simple cache request interface used by L2.
- `CoherenceManager.sv`: placeholder for future MSI/MESI invalidation/snoop logic.
- `CacheArchitecture.sv`: top-level cache subsystem for 4 cores:
  - 4 private 32KB L1 I-caches.
  - 4 private 32KB L1 D-caches.
  - AXI interconnect from 8 L1 miss ports to shared L2.
  - 512KB shared L2 cache.
  - line-width DRAM request interface below L2.
- `cache_architecture.f`: compile file list for the cache architecture and AXI interconnect RTL.

## Capacity parameters

The default line size is 256 bits, or 32 bytes.

L1 default:

```text
512 sets * 2 ways * 32 bytes = 32KB
```

L2 default:

```text
8192 sets * 2 ways * 32 bytes = 512KB
```

## Compile note

Compile these files together with `AXI4-Interconnect-main/rtl/axi_interconnect.v` and its RTL dependencies.
The AXI adapters currently issue one-beat, full-line transactions. Burst refill/writeback support and real coherence are left as explicit integration points.

`CacheArchitecture.sv` maps the single L2 slave through AXI slave-select bit 0. L1 miss addresses are cache-line aligned, so bit 0 is always zero and routes to the only L2 slave.
