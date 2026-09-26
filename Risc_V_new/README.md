# KLTN — Bộ xử lý RISC-V RV32IMA 4 lõi

README này mô tả **trạng thái hiện hành** của thiết kế trong `Risc_V_new/Risc_V`.
Mức độ hoàn thành chỉ được đánh giá bằng RTL, testbench và kết quả đã kiểm tra;
không dùng số lượng module hoặc số dòng code làm bằng chứng hoàn tất hệ thống.

## 1. Mục tiêu

Thiết kế một SoC 4 lõi RISC-V RV32IMA phục vụ nghiên cứu hệ thống nhúng đa lõi, gồm:

- pipeline RV32IMA 5 tầng cho từng lõi;
- CSR, trap và ba mức đặc quyền M/S/U;
- MMU Sv32, iTLB/dTLB, superpage TLB và Page Table Walker;
- L1 instruction/data cache riêng, L2 cache dùng chung;
- coherence MSI cho dữ liệu chia sẻ giữa 4 lõi;
- AHB-Lite ở miền cache/coherence và AXI4 ở miền hệ thống;
- boot controller, DMA/DRAM wrapper và kịch bản chạy trên FPGA;
- kiểm chứng tự động không dùng UVM: testbench tự kiểm, regression và hardware test.

## 2. Trạng thái tổng quan

| Hạng mục | Trạng thái | Bằng chứng/ghi chú |
|---|---|---|
| RV32IMA pipeline | RTL đã có | Pipeline 5 tầng, hazard/forwarding, MDU và RV32A |
| CSR/trap/privilege | Đang hoàn thiện | Còn lỗi regression ở đường `medeleg`/cause của `tb_csr_priv.v` |
| MMU/TLB/PTW Sv32 | RTL đã có | Có testbench; cần chạy lại toàn bộ regression sau tái cấu trúc |
| L1/L2 cache | RTL đã có | Có testbench FENCE.I, AMO, LR/SC; cần chạy lại đầy đủ |
| Coherence MSI | **PASS hiện tại** | `MSI_COHERENCE_TB` và `MSI_COHERENCE_AHB_TB` đã chạy lại bằng QuestaSim |
| AHB-Lite adapters | **PASS trong integration MSI/AHB** | Đã kiểm tra RFO, `HMASTLOCK`, `HREADY`, snoop và writeback |
| AXI4/boot wrapper | RTL đã có | Chưa có bằng chứng synthesis/board end-to-end |
| Vivado synthesis/implementation | Chưa xác nhận | Chưa có report utilization, timing hoặc power hiện hành |
| FPGA hardware test | Chưa hoàn tất | Chưa chứng minh luồng SD–DRAM–CPU–SD trên board thật |

> **Mốc kiểm tra gần nhất:** toàn bộ source trong
> [`Risc_V/rtl/files.f`](Risc_V/rtl/files.f) compile thành công bằng QuestaSim 10.2c.
> Hai regression coherence nêu trên đều PASS sau khi source được chia lại theo block.

## 3. Kiến trúc hệ thống

```text
Core 0..3
  ├─ RV32IMA pipeline + CSR/trap
  ├─ MMU: iTLB + dTLB + super-TLB + PTW
  └─ L1 I-cache + L1 D-cache
             │
             ▼
       AHB-Lite adapters
             │
             ▼
       MSI coherence manager
             │
             ├─ Shared L2 cache
             └─ AXI4 system boundary
                    ├─ DRAM
                    ├─ DMA/storage
                    └─ Boot control/peripherals
```

Tài liệu và hình kiến trúc chi tiết:

- [`Risc_V/docs/architecture/ARCHITECTURE.md`](Risc_V/docs/architecture/ARCHITECTURE.md)
- `system_overview.svg`: kiến trúc tổng thể;
- `core_pipeline.svg`: pipeline RV32IMA;
- `mmu.svg`: MMU/TLB/PTW;
- `cache_coherence.svg`: L1/L2 và MSI;
- `bus_domains.svg`: ranh giới AHB-Lite/AXI4;
- `boot_flow.svg`: luồng boot và DMA;
- `verification.svg`: chiến lược kiểm chứng;
- `rtl_tree.svg`: cấu trúc source theo block.

## 4. Cấu trúc source hiện tại

```text
Risc_V_new/Risc_V/
├── rtl/
│   ├── core/              Pipeline, ALU, register file, CSR và trap
│   ├── mmu/               TLB, super-TLB, PTW, region policy và wrapper
│   ├── cache/             L1 I/D, L2 và core-L1 wrapper
│   ├── coherence/         MSI coherence manager và directory/snoop control
│   ├── interconnect/ahb/  AHB-Lite master/slave adapters
│   ├── soc/               Quad-core SoC và AXI4-facing wrappers
│   ├── boot/              Boot controller
│   ├── debug/             MMU/cache trace buffers tùy chọn
│   ├── legacy_2core/      Baseline 2 lõi cũ, không thuộc hierarchy 4 lõi chính
│   ├── files.f            Danh sách source chuẩn theo thứ tự compile
│   └── README.md          Quy tắc tổ chức và dependency
├── sim/                   Self-checking testbenches
├── scripts/               Vivado build scripts
├── docs/architecture/     Tài liệu và hình kiến trúc
└── Risc_V.xpr             Vivado project đã cập nhật đường dẫn source mới
```

Tên module và interface RTL được giữ nguyên; thay đổi chính là vị trí source. Ba
script Vivado dùng cơ chế tìm source bên dưới `rtl/`, vì vậy không cần đưa file trở
lại thư mục phẳng khi thêm block mới.

## 5. Vai trò từng block

### 5.1. Core

- ISA mục tiêu: RV32I + M + A; không triển khai F/D/C.
- Pipeline 5 tầng: IF, ID, EX, MEM và WB.
- Forwarding, load-use hazard, branch redirect và stall ngoài.
- CSR/trap cung cấp `satp`, `SUM`, `MXR`, privilege mode và trap redirect cho MMU.
- RV32A gồm LR/SC và các AMO word; reservation được theo dõi theo địa chỉ vật lý.

### 5.2. MMU

- Sv32 hai cấp, hỗ trợ page 4 KiB và superpage 4 MiB.
- iTLB/dTLB 16 entry theo cấu trúc 4 set × 4 way; super-TLB tách riêng.
- Kiểm tra U/S, `SUM`, `MXR`, quyền R/W/X và Accessed/Dirty.
- PTW dùng chung giữa instruction/data; core bị stall trong lúc walk/refill.
- Region policy có thể chặn sớm truy cập sai vùng trước khi phát PTW request.

### 5.3. Cache và MSI coherence

- Mỗi lõi có L1 I-cache và L1 D-cache; L2 dùng chung.
- D-cache dùng ba trạng thái MSI: Invalid, Shared và Modified.
- Read miss phát BusRd; write miss hoặc `S -> M` phát RFO/BusRdX.
- Owner ở M phải forward dirty line khi bị remote read và hạ về S.
- Dirty eviction/flush thực hiện full-line writeback trước khi invalidate.
- Coherence manager hiện blocking và tuần tự hóa một transaction toàn hệ thống để
  ưu tiên correctness; đây chưa phải thiết kế non-blocking tối ưu throughput.

### 5.4. Bus và SoC wrapper

- AHB-Lite dùng ở ranh giới L1/coherence; `HMASTLOCK` bảo toàn ý nghĩa RFO.
- AXI4 dùng cho ranh giới hệ thống với DRAM, DMA và các IP ngoài.
- `quad_core_axi_wrapper_ahb_bootable.v` là entry point tích hợp đầy đủ nhất hiện có.
- Boot controller cung cấp entry point và điều khiển thả core sau khi image sẵn sàng.

## 6. Kiểm chứng

Thiết kế không dùng UVM. Bằng chứng được tổ chức theo ba lớp:

1. **RTL self-checking:** testbench phải tự phát PASS/FAIL; waveform dùng để chẩn
   đoán, không phải bằng chứng duy nhất.
2. **Integration/regression:** kiểm tra đường core–MMU–cache–coherence–bus và khóa
   các lỗi đã sửa.
3. **FPGA hardware test:** synthesis/implementation và workload tự động trên board,
   không dựa vào thao tác thủ công để xác nhận kết quả.

### 6.1. Đã xác nhận sau khi chia lại thư mục RTL

- Toàn bộ source trong `rtl/files.f`: **compile PASS** bằng QuestaSim 10.2c.
- `sim/tb_coherence.v`: **`MSI_COHERENCE_TB: PASS`**.
- `sim/tb_coherence_ahb.v`: **`MSI_COHERENCE_AHB_TB: PASS`**.

Hai test trên bao phủ các tình huống chính như I/S/M, nhiều sharer, owner forward,
invalidate, eviction, flush, AMO, RFO/`HMASTLOCK`, `HREADY` và full-line writeback.

### 6.2. Testbench đã có nhưng cần chạy lại toàn bộ

- `tb_mmu_advanced.v`, `tb_mmu_upgrade.v`, `tb_mmu_policy.v`, `tb_mmu_core.v`;
- `tb_cache_fence_i.v`, `tb_cache_amo.v`, `tb_cache_lrsc.v`,
  `tb_cache_lrsc_snoop.v`;
- `tb_csr_mmu_bits.v`, `tb_csr_trap.v`, `tb_csr_priv.v`;
- `tb_coherence_watchdog.v`.

Các README/log lịch sử có ghi nhận PASS cho nhiều test trong nhóm này, nhưng chúng
không được tính là kết quả hiện hành sau tái cấu trúc cho đến khi chạy lại regression.
Riêng `tb_csr_priv.v` đang theo dõi lỗi `medeleg`/cause và không được coi là PASS.

## 7. Entry point và build

Các entry point chính:

- `rtl/soc/quad_core_soc.v`: request/response native;
- `rtl/soc/quad_core_soc_ahb.v`: đường AHB-Lite;
- `rtl/soc/quad_core_axi_wrapper_ahb.v`: wrapper AXI4 cho SoC AHB;
- `rtl/soc/quad_core_axi_wrapper_ahb_bootable.v`: wrapper bootable;
- `rtl/files.f`: inventory chuẩn cho simulator/static checks.

Vivado scripts:

- `scripts/build_soc_4core_trial.tcl`;
- `scripts/build_soc_mmu_trial.tcl`;
- `scripts/build_soc_zu5ev_boot.tcl`.

Các script đã được cập nhật để tìm source theo cấu trúc block hiện tại.

## 8. Giới hạn và rủi ro còn lại

- Chưa có báo cáo Vivado synthesis, implementation, timing, utilization và power.
- Chưa chứng minh boot/workload 4 lõi end-to-end trên FPGA thật.
- Memory port chưa có byte strobe và uncached/MMIO bypass hoàn chỉnh; chưa nên nối
  peripheral có side effect trực tiếp qua đường cache hiện tại.
- `HRESP`/AXI error chưa được truyền ngược đầy đủ thành architectural access fault.
- DMA chưa là coherence master; cần protocol flush/invalidate trước và sau transfer.
- Coherence manager blocking giới hạn throughput khi contention cao.
- Cần sửa và khóa regression privilege delegation/ECALL.
- Kết nối SD phụ thuộc board, phải xác nhận đường vật lý trước khi chốt boot flow.

## 9. Lộ trình ưu tiên

### Tháng 9–10: khóa các block nền tảng

1. Chạy lại và khóa regression MMU/TLB/PTW.
2. Khóa AHB-Lite handshake, error path và integration với MSI.
3. Hoàn thiện AXI4 boundary, byte strobe và uncached/MMIO path.
4. Sửa regression CSR privilege/delegation.

### Sau khi bus và MMU ổn định

1. Chạy full cache/coherence regression.
2. Vivado synthesis/implementation và thu report tài nguyên/timing/power.
3. Bring-up clock, reset, DRAM, UART và storage trên board.
4. Chứng minh boot/DMA với luồng SD–DRAM–CPU–SD.
5. Đánh giá workload 1/2/4 lõi trên cùng board, clock, compiler flags và input.

## 10. Tiêu chí hoàn thành khóa luận

Khóa luận chỉ được xem là hoàn thành khi có đủ:

- full RTL regression với kết quả tự động PASS/FAIL;
- Vivado synthesis và implementation không có lỗi nghiêm trọng;
- timing closure ở clock mục tiêu;
- báo cáo LUT, FF, BRAM, Fmax và power nếu đo được;
- workload 4 lõi chạy end-to-end trên FPGA;
- dữ liệu đầu ra được kiểm tra tự động và có thể tái lập.
