# KLTN — Thiết kế bộ vi xử lý RISC-V RV32IMA 4 lõi

Repository phục vụ khóa luận tốt nghiệp về thiết kế và kiểm chứng một hệ thống xử lý
4 lõi RISC-V RV32IMA, tích hợp MMU Sv32, phân cấp cache L1/L2, coherence MSI,
AHB-Lite, AXI4 và luồng boot hướng tới triển khai trên FPGA.

> README kỹ thuật và bảng tiến độ chi tiết nằm tại
> [`Risc_V_new/README.md`](Risc_V_new/README.md).

## 1. Mục tiêu chính

- Xây dựng 4 lõi RV32IMA pipeline 5 tầng.
- Hỗ trợ CSR, trap và các mức đặc quyền M/S/U.
- Tích hợp MMU/TLB/PTW Sv32 riêng theo từng lõi.
- Tổ chức L1 I/D cache riêng và L2 cache dùng chung.
- Bảo đảm nhất quán dữ liệu bằng giao thức MSI.
- Sử dụng AHB-Lite ở miền cache/coherence và AXI4 ở miền hệ thống.
- Tổng hợp, triển khai và đánh giá tự động trên FPGA.

## 2. Trạng thái hiện tại

| Hạng mục | Trạng thái |
|---|---|
| RV32IMA pipeline, CSR/trap | Đã có RTL; privilege regression còn cần sửa |
| MMU/TLB/PTW Sv32 | Đã có RTL và testbench; cần chạy lại full regression |
| L1/L2 cache và MSI | Đã có RTL |
| Coherence MSI | Hai regression chính đã chạy lại và PASS |
| AHB-Lite | Integration MSI/AHB đã chạy lại và PASS |
| AXI4 và boot wrapper | Đã có RTL; chưa xác nhận end-to-end trên board |
| Vivado synthesis/implementation | Chưa có report hiện hành |
| FPGA hardware test | Chưa hoàn tất |

Mốc kiểm tra gần nhất:

- toàn bộ source trong `Risc_V_new/Risc_V/rtl/files.f` compile bằng QuestaSim 10.2c;
- `MSI_COHERENCE_TB: PASS`;
- `MSI_COHERENCE_AHB_TB: PASS`.

Các kết quả MMU/cache/CSR từng được ghi nhận trong log cũ phải được chạy lại sau khi
tái cấu trúc source trước khi đưa vào kết luận cuối cùng.

## 3. Cấu trúc repository

```text
KLTN/
├── Risc_V_new/
│   ├── README.md                 Tiến độ và tài liệu kỹ thuật hiện hành
│   └── Risc_V/
│       ├── rtl/                  RTL được chia theo block kiến trúc
│       ├── sim/                  Self-checking testbenches
│       ├── scripts/              Vivado build scripts
│       ├── docs/architecture/    Tài liệu và hình kiến trúc
│       └── Risc_V.xpr            Vivado project
├── Controller_Cache_2Cores_RV32IA/  Tài liệu/RTL tham khảo 2 lõi
├── cache_reference/              Các thử nghiệm cache/MMU trước đây
├── mmu_reference/                Mã nguồn MMU tham khảo
├── ahb3lite_interconnect-master_reference/  AHB-Lite tham khảo
├── output/                       Slide và các sản phẩm bàn giao
└── README.md                     Trang tổng quan này
```

Nhánh phát triển chính là [`Risc_V_new/Risc_V`](Risc_V_new/Risc_V). Các thư mục có
tên `reference` chỉ dùng tham khảo, không phải source của hierarchy 4 lõi hiện hành.

## 4. Cấu trúc RTL

```text
Risc_V_new/Risc_V/rtl/
├── core/              RV32IMA pipeline, CSR, trap và privilege
├── mmu/               iTLB, dTLB, super-TLB, PTW và region policy
├── cache/             L1 I/D cache, L2 cache và core-L1 wrapper
├── coherence/         MSI coherence manager
├── interconnect/ahb/  AHB-Lite adapters
├── soc/               Quad-core SoC và AXI4 wrappers
├── boot/              Boot controller
├── debug/             Trace buffers tùy chọn
├── legacy_2core/      Baseline 2 lõi cũ
└── files.f            Danh sách source chuẩn theo thứ tự compile
```

Quy tắc quản lý source được mô tả tại
[`Risc_V_new/Risc_V/rtl/README.md`](Risc_V_new/Risc_V/rtl/README.md).

## 5. Tài liệu kiến trúc

Tài liệu tổng hợp:

- [`ARCHITECTURE.md`](Risc_V_new/Risc_V/docs/architecture/ARCHITECTURE.md);
- sơ đồ kiến trúc tổng thể;
- pipeline RV32IMA;
- MMU/TLB/PTW;
- cache và coherence MSI;
- phân chia miền bus AHB-Lite/AXI4;
- boot/DMA flow;
- cấu trúc thư mục RTL;
- chiến lược kiểm chứng không dùng UVM.

Các hình SVG và PNG nằm trong
[`Risc_V_new/Risc_V/docs/architecture`](Risc_V_new/Risc_V/docs/architecture).

## 6. Slide trình bày

Bản slide 21 trang trình bày toàn bộ đề tài, kiến trúc từng block, trạng thái kiểm
chứng, giới hạn và lộ trình nằm tại:

[`output/KLTN_QuadCore_RV32IMA_ToanBoKienTruc_v2.pptx`](output/KLTN_QuadCore_RV32IMA_ToanBoKienTruc_v2.pptx)

## 7. Chiến lược kiểm chứng

Đề tài không dùng UVM. Quy trình kiểm chứng gồm:

1. self-checking RTL testbench với kết quả PASS/FAIL tự động;
2. integration test và regression cho core–MMU–cache–coherence–bus;
3. Vivado synthesis/implementation và kiểm tra timing/tài nguyên;
4. hardware test tự động trên FPGA, không phụ thuộc thao tác thủ công.

Waveform được dùng để chẩn đoán lỗi, không phải bằng chứng duy nhất về correctness.

## 8. Ưu tiên tháng 9–10

1. Chạy lại và khóa regression MMU/TLB/PTW.
2. Hoàn thiện AHB-Lite handshake và đường truyền lỗi.
3. Ổn định AXI4 boundary, byte strobe và uncached/MMIO path.
4. Sửa regression CSR privilege/delegation.
5. Chỉ mở rộng boot/DMA và đánh giá board sau khi các block nền tảng ổn định.

## 9. Công việc còn lại

- Chạy full regression MMU, cache, CSR và integration 4 lõi.
- Sửa lỗi `medeleg`/cause trong privilege regression.
- Hoàn thiện uncached/MMIO và byte strobe.
- Xác định protocol coherence cho DMA.
- Chạy Vivado synthesis/implementation, timing và power analysis.
- Bring-up DRAM, storage và boot flow trên board thật.
- Đánh giá workload 1/2/4 lõi với cùng board, clock, compiler flags và input.

Khóa luận chỉ được coi là hoàn tất khi có cả regression, report Vivado và demo FPGA
end-to-end có thể tái lập.
