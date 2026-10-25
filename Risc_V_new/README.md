# KLTN — Bộ xử lý RISC-V RV32IMA 4 lõi

README này mô tả **trạng thái hiện hành** của thiết kế trong `Risc_V_new/Risc_V`.
Mức độ hoàn thành chỉ được đánh giá bằng RTL, testbench và kết quả đã kiểm tra;
không dùng số lượng module hoặc số dòng code làm bằng chứng hoàn tất hệ thống.

## 1. Mục tiêu

Thiết kế một SoC 4 lõi RISC-V RV32IMA phục vụ nghiên cứu hệ thống nhúng đa lõi, gồm:

- pipeline RV32IMA 5 tầng cho từng lõi;
- CSR, trap và ba mức đặc quyền M/S/U;
- khối dịch địa chỉ Sv32 theo từng core: iTLB/dTLB, superpage TLB và PTW;
- cache controller dùng chung ("MMU" theo cách gọi của giảng viên) điều phối L1,
  L2, MSI và CPU memory port;
- L1 instruction/data cache riêng, L2 cache dùng chung;
- coherence MSI cho dữ liệu chia sẻ giữa 4 lõi;
- AHB-Lite ở miền cache/coherence và AXI4 ở miền hệ thống;
- boot controller, DMA/DRAM wrapper và kịch bản chạy trên FPGA;
- kiểm chứng tự động không dùng UVM: testbench tự kiểm, regression và hardware test.

## 2. Trạng thái tổng quan

| Hạng mục | Trạng thái | Bằng chứng/ghi chú |
|---|---|---|
| RV32IMA pipeline | RTL đã rà soát/bổ sung test | Pipeline 5 tầng, hazard/forwarding, MDU, RV32A, legality decode; `tb_core_rv32ima_isa.v` mới cần chạy regression |
| CSR/trap/privilege | **PASS hiện tại** | ECALL/EBREAK, M/S/U transition và `medeleg` đã được khóa bằng `tb_csr_priv.v` |
| MMU/TLB/PTW Sv32 | **PASS hiện tại** | Bộ regression MMU + CSR SUM/MXR/access-fault đã PASS; flush giữa PTW được kiểm chứng |
| Shared cache controller (MMU) | **PASS hiện tại** | Đồng cấp với L2; round-robin 8 nguồn, block transfer và MSI chạy trong `tb_coherence.v` |
| L1/L2 cache | **PASS hiện tại** | FENCE.I, AMO, LR/SC, MSI, error sideband và uncached/MMIO đã chạy lại |
| Coherence MSI | **PASS hiện tại** | `MSI_COHERENCE_TB` và `MSI_COHERENCE_AHB_TB` đã chạy lại bằng QuestaSim |
| AHB-Lite adapters | **PASS trong integration MSI/AHB** | Đã kiểm tra RFO, `HMASTLOCK`, `HREADY`, snoop và writeback |
| AXI4/boot wrapper | **Synthesis PASS (wrapper AHB/AXI4)** | `quad_core_axi_wrapper_ahb` đã synthesize; bootable wrapper và board end-to-end chưa xác nhận |
| Source-level DMA | RTL + testbench đã có, **chưa chạy lại** | AXI4 burst memcpy, AXI-Lite register, pre/post cache maintenance và `tb_dma_end_to_end.v` |
| Vivado synthesis/implementation | **Full-BD synthesis PASS** | Vivado 2022.2, `xc7z030fbv676-1`: 0 error/0 critical warning; post-synthesis timing 100 MHz chưa đạt, implementation/power chưa chạy |
| FPGA hardware test | Chưa hoàn tất | Chưa chứng minh luồng SD–DRAM–CPU–SD trên board thật |

> **Mốc đã xác nhận gần nhất:** phiên bản nền trước đợt bổ sung legality decode và
> DMA compile thành công, **26/26** testbench PASS bằng QuestaSim 10.2c. Source hiện
> có thêm test RV32IMA/DMA; cần chạy lại regression trước khi nâng mốc xác nhận.

## 3. Kiến trúc hệ thống

```text
Core 0..3
  ├─ RV32IMA pipeline + CSR/trap
  ├─ Sv32 address translation: iTLB + dTLB + super-TLB + PTW
  └─ L1 I-cache + L1 D-cache
             │
             ▼
       AHB-Lite adapters
             │
             ▼
       Cache controller (MMU) ◄────► Shared L2 cache
             │
             └─ AXI4 system boundary
                    ├─ DRAM
                    ├─ DMA/storage
                    └─ Boot control/peripherals
```

Tài liệu và hình kiến trúc chi tiết:

- [`Risc_V/docs/architecture/ARCHITECTURE.md`](Risc_V/docs/architecture/ARCHITECTURE.md)
- [`Risc_V/docs/architecture/MMU_CACHE_CONTROLLER_REDESIGN.md`](Risc_V/docs/architecture/MMU_CACHE_CONTROLLER_REDESIGN.md): đối chiếu lời thầy, mã tham khảo và ranh giới RTL mới;
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
│   ├── mmu/               Sv32 TLB/PTW và shared cache-controller MMU facade
│   ├── cache/             L1 I/D, L2 và core-L1 wrapper
│   ├── coherence/         MSI policy engine, round-robin và directory/snoop control
│   ├── interconnect/ahb/  AHB-Lite master/slave adapters
│   ├── soc/               Quad-core SoC và AXI4-facing wrappers
│   ├── boot/              Boot controller
│   ├── debug/             MMU/cache trace buffers tùy chọn
│   ├── legacy_2core/      Baseline 2 lõi cũ, không thuộc hierarchy 4 lõi chính
│   ├── files.f            Danh sách source chuẩn theo thứ tự compile
│   └── README.md          Quy tắc tổ chức và dependency
├── sim/                   Self-checking testbenches
├── scripts/               Vivado build scripts
├── software/ps_loader/    PS-side boot/DMA register API and integration example
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
- Decoder kiểm tra cả opcode lẫn các tổ hợp `funct3/funct7/funct5` dành riêng và
  triệt side effect của illegal instruction ngay tại Decode.
- `mhartid` được tham số hóa xuyên qua wrapper; bốn core nhận giá trị 0, 1, 2, 3.

### 5.2. MMU

Trong mục này, "MMU" là MMU chuẩn RISC-V dùng để dịch VA→PA. Nó khác với
`cache_controller_mmu` dùng chung ở mục 5.3; tài liệu redesign giải thích rõ hai
cách dùng thuật ngữ để tránh gộp TLB/PTW vào cache controller.

- Sv32 hai cấp, hỗ trợ page 4 KiB và superpage 4 MiB.
- iTLB/dTLB 16 entry theo cấu trúc 4 set × 4 way; super-TLB tách riêng.
- Kiểm tra U/S, `SUM`, `MXR`, quyền R/W/X và Accessed/Dirty.
- PTW dùng chung giữa instruction/data; core bị stall trong lúc walk/refill.
- Region policy có thể chặn sớm truy cập sai vùng trước khi phát PTW request.
- Đổi `satp`/mode tự động vô hiệu TLB; thay đổi privilege/SUM/MXR giữa PTW làm kết
  quả cũ bị discard và kiểm tra lại, không stale-refill/stale-fault.
- Đường D-cache/coherence cập nhật A/D bằng AMOOR.W; watchdog PTW 4096 chu kỳ được
  giữ làm sticky diagnostic cho ILA mà không tự abort giao dịch bus.
- `mmu_ip_wrapper` kiểm tra AXI `RRESP/BRESP`: lỗi fetch/load/store hoặc lỗi trong
  page walk tạo architectural access fault cause 1/5/7 và không refill TLB.

### 5.3. Cache và MSI coherence

- Mỗi lõi có L1 I-cache và L1 D-cache; L2 dùng chung.
- Data/tag/state của L1 được truy cập đồng bộ bằng XPM Block RAM; data L2 512 KiB
  được chia thành tám bank 32-bit để Vivado suy diễn RAMB36 thay vì dựng một mux
  khổng lồ từ mảng bất đồng bộ. D-cache scrub 512 set sau reset; L2 scrub 4096 set
  và giữ request đầu tiên trong lúc khởi tạo. Vì vậy reset-to-first-response có độ
  trễ hữu hạn nhưng synthesis không còn mắc ở biến data 4.194.304 bit.
- `cache_controller_mmu` là controller chung của toàn CPU 4 core và là instance
  đồng cấp với `l2_cache` trong cả top direct-wire lẫn top AHB. Giao diện giữa hai
  khối mang command/address/data và status hit/miss/victim/dirty/sharer.
- D-cache dùng ba trạng thái MSI: Invalid, Shared và Modified.
- Read miss phát BusRd; write miss hoặc `S -> M` phát RFO/BusRdX.
- Owner ở M phải forward dirty line khi bị remote read và hạ về S.
- Dirty eviction/flush thực hiện full-line writeback trước khi invalidate.
- Vùng vật lý `0xC000_0000..0xFFFF_FFFF` đi theo đường uncached một word, không
  allocate L1/L2 và không phát snoop; `LB/LH/LW` vẫn được format ở D-cache, còn
  `SB/SH/SW` truyền byte-enable đến tận AXI `WSTRB`. AMO vào vùng này trả access
  fault thay vì âm thầm hạ cấp thành một read-modify-write không atomic.
- AXI `RRESP/BRESP` lỗi được giữ theo transaction, trả về đúng I$ hoặc D$; line lỗi
  không được allocate. Nếu writeback victim dirty lỗi giữa chừng, coherence manager
  phục hồi bản authoritative vào L2 ở trạng thái dirty trước khi trả access fault.
- Coherence manager hiện blocking và tuần tự hóa một transaction toàn hệ thống để
  ưu tiên correctness; đây chưa phải thiết kế non-blocking tối ưu throughput.
- `Cache_Flush` có handshake `Cache_Flush_Busy/Done/Error` xuyên suốt từ từng
  core-L1 subsystem đến các SoC/AXI wrapper. Tác nhân ngoài chỉ bắt đầu DMA sau
  `Done`; `Error` là sticky diagnostic báo clean/writeback không thành công.
- Bộ tổng hợp maintenance có watchdog chẩn đoán. Timeout giữ `Busy=1`, đặt
  `Error=1` và không tạo `Done` giả vì đường memory chưa có cancel/drain an toàn.

### 5.4. Bus và SoC wrapper

- AHB-Lite dùng ở ranh giới L1/coherence; `HMASTLOCK` bảo toàn ý nghĩa RFO.
- Cầu AHB dùng `HPROT[3]` và `HSIZE` để giữ thuộc tính non-cacheable cùng kích
  thước byte/half/word; một MMIO access chỉ tạo đúng một AHB transfer.
- AXI4 dùng cho ranh giới hệ thống với DRAM, DMA và các IP ngoài.
- AXI wrapper latch request nội bộ và giữ `ARVALID/AWVALID/WVALID`, địa chỉ, dữ
  liệu và `WSTRB` ổn định qua backpressure; AW và W được bắt tay độc lập.
- `quad_core_axi_wrapper_ahb_bootable.v` là entry point tích hợp đầy đủ nhất hiện có.
- Boot controller cung cấp entry point và điều khiển thả core sau khi image sẵn sàng.
- Thanh ghi AXI-Lite `CACHE` tại offset `0xC` cho phép PS phát maintenance và poll
  `Busy/Done/Error/Rejected`; register map và trình tự DMA nằm trong
  `docs/BOOT_DMA_PROTOCOL.md`.

### 5.5. Source-level DMA

- `rtl/dma/soc_dma_controller.v` ghép AXI4-Lite register file, coordinator cache
  và AXI4 memory-to-memory engine; không phụ thuộc IP sinh tự động của Vivado.
- DMA dùng burst INCR có giới hạn, không vượt biên 4 KiB, kiểm tra alignment và
  lan truyền `RRESP/BRESP` lỗi.
- Trình tự bắt buộc là buffer quiesced → pre-flush → copy → post-flush. Watchdog
  chỉ chẩn đoán và không tạo completion giả khi giao dịch còn outstanding.
- `software/ps_loader/soc_dma.h` là API C độc lập BSP cho register map này.

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
- `sim/tb_mmu_advanced.v`: **`MMU_ADVANCED_TB: PASS`** — U/S, SUM/MXR, A/D,
  superpage, non-leaf reserved/G propagation, PTE[11:10]/RSW và super-TLB flush.
- `sim/tb_mmu_sfence.v`: **`MMU_SFENCE_TB: PASS`** — flush giữa PTE read hoặc A/D
  writeback đều discard mapping cũ, không stale-refill và tự walk lại.
- `sim/tb_mmu_context.v`: **`MMU_CONTEXT_TB: PASS`** — đổi root tự invalidate,
  disable/privilege-change giữa walk được drain/discard an toàn và watchdog latch.
- `sim/tb_mmu_bus_error.v`: **`MMU_BUS_ERROR_TB: PASS`** — lỗi L1/L0 PTE và A/D
  writeback đều thành access fault, không bị nhầm thành page fault hoặc refill TLB.
- `sim/tb_mmu_upgrade.v`: **`MMU_UPGRADE_TB: PASS`**.
- `sim/tb_mmu_policy.v`: **`MMU_POLICY_TB: PASS`**.
- `sim/tb_mmu_core.v`: **`MMU_TB: PASS`** — 18 check qua pipeline/core thật, gồm
  xác nhận mọi A/D update trên cấu hình cache dùng đúng AMOOR.W mask.
- `sim/tb_csr_mmu_bits.v`: **`CSR_MMU_BITS_TB: PASS`**.
- `sim/tb_csr_access_fault.v`: **`CSR_ACCESS_FAULT_TB: PASS`** — cause 1/5/7,
  `mepc` và `mtval` đúng.
- `sim/tb_csr_trap.v`: **`CSR_TRAP_TB: PASS`**.
- `sim/tb_csr_priv.v`: **`CSR_PRIV_TB: PASS`** — chuỗi M→S→U, ECALL từ U được
  `medeleg[8]` đưa sang S với `scause=8`, EBREAK không delegate đi M với `mcause=3`,
  rồi MRET/SRET trở lại đúng privilege.
- `sim/tb_cache_amo.v`: **`CACHE_AMO_TB: PASS`**.
- `sim/tb_cache_lrsc.v`: **`CACHE_LRSC_TB: PASS`**.
- `sim/tb_cache_lrsc_snoop.v`: **`CACHE_LRSC_SNOOP_TB: PASS`**.
- `sim/tb_cache_fence_i.v`: **`CACHE_FENCE_I_TB: PASS`**.
- `sim/tb_cache_maintenance.v`: **`CACHE_MAINTENANCE_TB: PASS`** — kiểm tra
  completion lệch chu kỳ giữa bốn cache, flush xếp sau FENCE.I, sticky error và
  timeout không tạo completion giả.
- `sim/tb_boot_ctrl.v`: **`BOOT_CTRL_TB: PASS`** — kiểm tra GO, RESULT byte
  strobes, maintenance command/status, done latch và busy rejection.
- `sim/tb_coherence.v`: **`MSI_COHERENCE_TB: PASS`**.
- `sim/tb_coherence_ahb.v`: **`MSI_COHERENCE_AHB_TB: PASS`**.
- `sim/tb_cache_error_path.v`: **`CACHE_ERROR_PATH_TB: PASS`** — I$/D$ không
  allocate line lỗi và có thể retry thành công.
- `sim/tb_coherence_error.v`: **`COHERENCE_ERROR_TB: PASS`** — lỗi được định tuyến
  đúng requester, không fill L2 và dirty victim được phục hồi nguyên dữ liệu.
- `sim/tb_ahb_error_sideband.v`: **`AHB_ERROR_SIDEBAND_TB: PASS`** — lỗi read/write
  đi qua `HRESP` và cầu AHB vẫn phục hồi cho giao dịch OKAY kế tiếp.
- `sim/tb_cache_uncached.v`: **`CACHE_UNCACHED_TB: PASS`** — MMIO không allocate,
  đúng load extension/byte lanes, error recovery và chặn uncached AMO.
- `sim/tb_ahb_uncached.v`: **`AHB_UNCACHED_TB: PASS`** — request uncached đi qua
  AHB bằng đúng một transfer, giữ địa chỉ, `HPROT`, `HSIZE`, `WSTRB` và read data.
- `sim/tb_axi_request_hold.v`: **`AXI_REQUEST_HOLD_TB: PASS`** — AXI VALID/payload
  được giữ qua backpressure, AW/W độc lập và BRESP lỗi quay về `mem_error`.
- `sim/tb_coherence_watchdog.v`: **`CACHE_WATCHDOG_TB: PASS`**.

Các test cache/coherence bao phủ I/S/M, nhiều sharer, owner forward, invalidate,
eviction, flush, AMO, RFO/`HMASTLOCK`, `HREADY` và full-line writeback. Test MSI
còn chạy chuỗi pseudo-random tái lập gồm 160 giao dịch ownership/read/write,
xen kẽ flush và kiểm tra 64 word cuối bằng scoreboard độc lập.

### 6.2. Tổng kết regression

Baseline trước thay đổi core/DMA có 26 testbench tự kiểm compile sạch và đều PASS;
log nằm ở `Risc_V/reports/full-regression-latest/`. Source hiện bổ sung
`tb_core_rv32ima_isa.v`, `tb_core_instruction_legality.v` và
`tb_dma_end_to_end.v`. Chưa được phép ghi nhận chúng PASS cho tới khi simulator
chạy lại thành công. Kết quả RTL simulation cũng không thay thế XSIM, synthesis,
implementation hoặc kiểm thử trên board.

Sau thay đổi lưu trữ cache đồng bộ, các test trọng yếu `tb_cache_error_path`,
`tb_cache_fence_i`, `tb_cache_maintenance`, `tb_coherence` và
`tb_coherence_ahb` cũng đã PASS trên Vivado XSIM 2022.2. Watchdog của
cache-controller là 8192 chu kỳ để bao phủ scrub 4096 set của L2.

## 7. Entry point và build

Các entry point chính:

- `rtl/soc/quad_core_soc.v`: request/response native;
- `rtl/soc/quad_core_soc_ahb.v`: đường AHB-Lite;
- `rtl/soc/quad_core_axi_wrapper_ahb.v`: wrapper AXI4 cho SoC AHB;
- `rtl/soc/quad_core_axi_wrapper_ahb_bootable.v`: wrapper bootable;
- `rtl/dma/soc_dma_controller.v`: DMA AXI4 + AXI4-Lite, tự điều phối cache;
- `rtl/files.f`: inventory chuẩn cho simulator/static checks.

Vivado scripts:

- `scripts/build_soc_4core_trial.tcl`;
- `scripts/build_soc_mmu_trial.tcl`;
- `scripts/build_soc_zu5ev_boot.tcl`.
- `software/ps_loader/boot_ctrl.h`: register map/API độc lập BSP cho PS loader và
  cache maintenance trước/sau DMA.
- `software/ps_loader/soc_dma.h`: register map/API cho source-level DMA.

Questa full regression (tự compile toàn bộ `rtl/files.f`, tìm mọi `sim/tb_*.v`,
ghi log và tạo lại `reports/full-regression-latest/summary.{md,csv}`):

```powershell
pwsh -File scripts/run_full_regression.ps1
```

Các script đã được cập nhật để tìm source theo cấu trúc block hiện tại.

### 7.1. Kết quả synthesis cache/quad-core gần nhất

Ngày 18-10-2026, `quad_core_axi_wrapper_ahb` được synthesize trực tiếp bằng
Vivado 2022.2 cho `xc7z030fbv676-1`, dùng `auto_detect_xpm` và
`flatten_hierarchy=rebuilt`:

| Chỉ số | Kết quả |
|---|---:|
| Thời gian `synth_design` | 6 phút 05 giây |
| Peak memory | 2.17 GiB |
| Slice LUT | 54,636 / 78,600 (69.51%) |
| Slice register | 34,250 / 157,200 (21.79%) |
| Block RAM tile | 232 / 265 (87.55%) |
| DSP48E1 | 48 / 400 (12.00%) |
| Lỗi / critical warning | 0 / 0 |

BRAM là tài nguyên sát giới hạn nhất. Không tăng dung lượng cache hoặc thêm BRAM
khác trước khi chạy lại utilization. Project-flow của Vivado tự nhận XPM; với
non-project flow phải gọi `auto_detect_xpm` trước `synth_design`.

### 7.2. Kết quả synthesis toàn Block Design `soc_4core_trial`

Ngày 19-10-2026, toàn hierarchy `soc_4core_trial_wrapper` được synthesize sạch
bằng Vivado 2022.2 trên cùng part `xc7z030fbv676-1`:

| Chỉ số | Kết quả |
|---|---:|
| Thời gian `synth_design` | 10 phút 40 giây |
| Thời gian launch/wait toàn run | 11 phút 40 giây |
| Peak memory | 2.10 GiB |
| Slice LUT | 56,443 / 78,600 (71.81%) |
| Slice register | 35,943 / 157,200 (22.86%) |
| Block RAM tile | 248 / 265 (93.58%) |
| DSP48E1 | 48 / 400 (12.00%) |
| Lỗi / critical warning | 0 / 0 |
| Post-synthesis WNS tại 100 MHz | -5.308 ns (**chưa đạt**) |

BRAM 64 KiB trong Block Design chỉ là bộ nhớ thử nghiệm đứng thay DDR ở ngoài
CPU; thay đổi này không giảm L1 hoặc L2 (L2 vẫn 512 KiB). Cấu hình cũ dùng BRAM
256 KiB làm bộ nhớ ngoài khiến tổng tài nguyên lên 296/265 tile và không thể đặt
lên part hiện tại. Nền tảng DDR thật không bị giới hạn bởi dung lượng BRAM thử này.

Synthesis đã thành công nhưng chưa được xem là timing closure. Cảnh báo quan trọng
còn lại cho thấy thanh ghi đầu ra BRAM của L2 có thể cải thiện timing; hướng tối ưu
tiếp theo là thêm pipeline có kiểm soát tại đường đọc L2, cập nhật latency/handshake
và regression, rồi mới chạy implementation/place-and-route ở 100 MHz.

### 7.3. Làm mới module reference và chạy synthesis trong Vivado

Mở `Risc_V.xpr`, chọn **Window → Tcl Console** và chạy từ thư mục project:

```tcl
set_property SOURCE_MGMT_MODE All [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
update_compile_order -fileset sources_1
open_bd_design [get_files */soc_4core_trial.bd]
update_module_reference [get_ips soc_4core_trial_cpu0_0]
validate_bd_design
save_bd_design
generate_target -force all [get_files */soc_4core_trial.bd]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
```

Nếu `soc_4core_trial` ở gốc Sources không có menu **Generate Output Products** thì
đó không phải lỗi: lệnh `generate_target` phía trên hoặc
`source scripts/build_soc_4core_trial.tcl` sẽ tạo output products. Không chuyển
compile order về Manual vì `update_module_reference` không hỗ trợ chế độ đó.

## 8. Giới hạn và rủi ro còn lại

- Chưa có báo cáo implementation, post-route timing và power. Ước lượng
  post-synthesis của full BD tại 100 MHz hiện có WNS -5.308 ns, vì vậy chưa timing
  closure và chưa nên dùng kết quả này để kết luận Fmax.
- Chưa chứng minh boot/workload 4 lõi end-to-end trên FPGA thật.
- Uncached/MMIO hiện là cửa sổ vật lý tham số hóa mặc định
  `0xC000_0000..0xFFFF_FFFF`, blocking và tối đa một word; chưa hỗ trợ atomic trên
  device memory, AXI burst hoặc nhiều transaction outstanding.
- AXI error đã được xử lý end-to-end cho cả wrapper một lõi và bốn lõi, gồm cầu AHB.
  Riêng lỗi writeback khi chạy `FENCE.I`/`Cache_Flush` không có load/store kiến trúc
  để gán cause 5/7: D$ giữ dirty line, không invalidate I$, nhả stall và latch cờ
  `cache_maintenance_error`; lỗi đã tới chân top-level và thanh ghi PS `CACHE`,
  nhưng machine-check chính xác cho chính CPU vẫn là phần mở rộng sau.
- Watchdog PTW hiện chỉ báo lỗi; chưa thể tự recovery an toàn khi bus treo vì đường
  memory chưa có cancel/drain cho response đến muộn.
- A/D atomic đã đóng ở đường L1 D-cache/coherence; `mmu_ip_wrapper` AXI trực tiếp vẫn
  dùng full-word PTE write cho đến khi AXI atomic/lock được triển khai.
- DMA chưa là coherence master trực tiếp. `soc_dma_controller` hiện thực protocol
  coarse-grain tự động (quiesce, pre-flush, DMA, post-flush); PS vẫn có thể dùng
  đường thủ công qua `boot_ctrl.CACHE`. Coherent DMA theo từng line và scatter-
  gather vẫn là phần mở rộng sau.
- Coherence manager blocking giới hạn throughput khi contention cao.
- Kết nối SD phụ thuộc board, phải xác nhận đường vật lý trước khi chốt boot flow.

## 9. Lộ trình ưu tiên

### Tháng 9–10: khóa các block nền tảng

1. Chạy lại bộ MMU trên Vivado XSIM và synthesis để đối chiếu kết quả QuestaSim.
2. Chạy error path AHB/AXI/MSI trên Vivado XSIM và fault-injection trên FPGA.
3. Mở rộng AXI4 boundary sang burst/ID nếu kết quả timing cho thấy các beat word
   hiện tại là nút thắt; đường byte strobe và uncached/MMIO cơ bản đã đóng bằng RTL.
4. Đối chiếu privilege/delegation trên Vivado XSIM và waveform trap redirect.

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
