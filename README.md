# KLTN — Thiết kế bộ vi xử lý RISC-V đa lõi (RV32IMA)

Tài liệu này tổng hợp (1) những thay đổi quan trọng đã thực hiện trong phiên làm việc gần nhất trên nhánh đang phát triển tích cực `Risc_V_new/Risc_V`, và (2) toàn cảnh các thư mục còn lại trong repo, để dùng làm tài liệu chuẩn bị trình bày trước hội đồng.

> Lưu ý: tài liệu này mô tả **trạng thái RTL hiện tại trên đĩa**, được viết dựa trên việc đọc trực tiếp mã nguồn. Phần hành vi (behavior) của các khối mới (đặc biệt là MMU) **chưa được mô phỏng** vì máy soạn tài liệu này không có Vivado/simulator cài sẵn — xem mục "Hạn chế" bên dưới.

---

## 1. Cấu trúc repo

```
KLTN/
├── Risc_V_new/Risc_V/         <- Lõi RV32IMA đang phát triển tích cực (nội dung 2 của đề cương)
├── Controller_Cache_2Cores_RV32IA/  <- Tài liệu/RTL tham khảo (báo cáo + slide + demo của một đề tài cùng hướng)
├── cache_reference/            <- Bản lưu công việc private-cache/MMU cũ (Phase 1–2), dùng để tham khảo
├── mmu_reference/               <- MMU Sv39 mã nguồn mở của BSC (Barcelona Supercomputing Center), tải về tham khảo thiết kế
└── README.md                    <- File này
```

---

## 2. Công việc đã thực hiện trong phiên này (`Risc_V_new/Risc_V`)

Lõi xử lý trước khi bắt đầu phiên này có tên **RV32IMFA** (I + M + F + A), pipeline 5 tầng (Fetch–Decode–Execute–Memory–Writeback), đã có sẵn RV32I, RV32M (nhân/chia), RV32A (LR/SC + AMO*), và RV32F (số thực, dùng định dạng lệnh chuẩn nhưng PTE/thanh ghi tự thiết kế).

### 2.1. Loại bỏ hoàn toàn phần mở rộng F (số thực) → RV32IMA

**Lý do:** nhóm quyết định chỉ giữ I/M/A, bỏ F để giảm tải khối lượng công việc (khớp với quyết định "Target ISA update: RV32IMA (F dropped)" đã ghi trong `cache_reference/README_PHASE2.md` từ trước).

**Đã xóa 9 file thuần F** khỏi `rtl/` và khỏi `Risc_V.xpr`:
`FPU.v`, `FPU_Decoder.v`, `FP_Add.v`, `FP_Mul.v`, `FP_Div.v`, `FP_FMA.v`, `FP_sqrt.v`, `FP_CVT.v`, `FP_Register_File.v`.

**Đã đổi tên** (khớp tên module với ISA thật sự hỗ trợ):

| Trước | Sau |
|---|---|
| `RV32IMFA.v` (`module RV32IMFA`) | `RV32IMA.v` (`module RV32IMA`) |
| `RV32IMFA_DualCore_Wrapper.v` | `RV32IMA_DualCore_Wrapper.v` |
| `RV32IMFA_DualCore_BoardTop.v` | `RV32IMA_DualCore_BoardTop.v` |
| `module RV32IMFA_IP_Wrapper` (trong `RV32_IP_Wrapper.v`) | `module RV32IMA_IP_Wrapper` |

**Đã sửa nội dung** các file điều khiển/pipeline để gỡ toàn bộ đường dẫn dữ liệu số thực (FP register file, FP forwarding, `FPU_Start`, `FPUControl`, kết quả `ResultSrc=FPU`...): `Main_Decoder.v`, `Control_Unit.v`, `decode_stage.v`, `id_ex_registers.v`, `ex_mem_registers.v`, `mem_wb_registers.v`, `execute_stage.v`, `hazard_unit.v`, `writeback_stage.v`. Đơn vị nhân/chia (MDU) trong `execute_stage.v` **giữ nguyên hoàn toàn**, không đụng tới.

**Kiểm tra đã thực hiện** (không có Vivado trên máy soạn nên chỉ kiểm tra tĩnh): viết script Python đối chiếu **mọi lệnh instantiate module** trong `rtl/` với đúng port list khai báo (không thiếu/thừa port) và kiểm tra cân bằng `module/begin/case/endmodule` trên toàn bộ file — cả hai đều sạch.

**Việc chưa làm / hạn chế đã biết còn tồn tại (không phải do phiên này gây ra):**
- `sim/tb_top.v` truyền `.CORE0_RESET_ADDR`/`.CORE1_RESET_ADDR` vào `RV32IMA_DualCore_Wrapper`, nhưng module này **không khai báo hai parameter đó** — lỗi elaborate có sẵn từ trước, cần sửa trước khi mô phỏng được `tb_top`.

---

### 2.2. Xây dựng MMU (TLB + Page Table Walker) mới

**Bối cảnh:** dựa theo `Risc_V_new/address_mapping` (đặc tả VA/PA/TLB do nhóm viết) và tham khảo kiến trúc MMU Sv39 mã nguồn mở của BSC (`mmu_reference/`). Vị trí đặt MMU theo đúng sơ đồ nhóm cung cấp: **VA (từ pipeline) → MMU/TLB (riêng theo từng lõi) → PA → phía bộ nhớ/cache**.

**4 file RTL mới trong `rtl/`** (đã đăng ký vào `Risc_V.xpr`):

| File | Vai trò |
|---|---|
| `mmu_tlb.v` | TLB 16-entry fully-associative, tra cứu tổ hợp (0 chu kỳ khi hit), nạp lại đồng bộ, thay thế round-robin. |
| `mmu_ptw.v` | Bộ dò trang (page table walker) kiểu Sv32 2 cấp: VPN[1]→bảng cấp 1→VPN[0]→bảng cấp 0→PTE lá. |
| `mmu_top.v` | Ghép iTLB + dTLB + PTW dùng chung, trọng tài ưu tiên bên dữ liệu (D) khi cả hai bên cùng miss, **kiểm tra lại quyền truy cập ở mọi lần hit** (không chỉ lúc nạp TLB). |
| `mmu_core_wrapper.v` | Bọc lõi `RV32IMA` gốc (không sửa file lõi), dịch VA→PA cho cả nhánh lệnh và dữ liệu, dùng lại cơ chế `Stall_Core_External` sẵn có để đóng băng pipeline khi PTW đang walk. |

**Định dạng PTE tự định nghĩa** (lệch có chủ đích so với Sv32 chuẩn — vì `address_mapping` yêu cầu PA 32-bit/PPN 20-bit, không phải PA 34-bit/PPN 22-bit như Sv32 gốc): giữ nguyên vị trí bit cờ `V,R,W,X,U,G,A,D` (bit 0–7) như Sv32 thật, nhưng trường PPN đặt ở `[31:12]` (20 bit).

**Các giới hạn cố ý, cần nắm rõ khi trình bày:**
1. Không hỗ trợ superpage 4MB (PTE lá ở cấp 1) — vì định dạng entry TLB theo `address_mapping` chỉ có "VPN(20b)→PPN(20b)", không có trường cấp trang.
2. PTW **chỉ đọc**, không ghi lại bit A/D vào page table (không có hardware update-on-first-access).
3. Không có phân quyền S/U (bit U được lưu nhưng không enforce) vì lõi hiện chưa có CSR mode.
4. **Chưa có cơ chế trap/exception thật** — lõi hiện tại không có đơn vị xử lý ngoại lệ. Khi fault: lệnh fetch bị ép thành NOP, store bị chặn, load trả về 0; có 2 tín hiệu `Fetch_PageFault`/`Data_PageFault` (+ mã lỗi 2-bit) nháy 1 chu kỳ để sau này nối vào một trap unit thật.
5. LR/SC giữa nhiều lõi **chưa an toàn tuyệt đối** dưới MMU: `memory_stage` so khớp địa chỉ reservation bằng VA trong khi tín hiệu snoop từ lõi khác là PA — chỉ đúng nếu mọi lõi map cùng một VA→PA cho vùng nhớ atomic dùng chung.
6. **Chưa nối `mmu_core_wrapper` vào `RV32IMA_DualCore_Wrapper`/`BoardTop`/testbench hiện có** — cố ý để MMU là khối cộng thêm, độc lập, không đụng vào bản dual-core đang chạy được, do không có simulator để xác nhận không có regression.
7. `Mmu_Enable=0` → bypass hoàn toàn trong suốt (VA=PA), hành vi giống hệt gắn thẳng `RV32IMA` — mặc định an toàn.

**Kiểm tra đã thực hiện:** script đối chiếu port (36/36 chỗ instantiate khớp chính xác, gồm cả 4 file mới) + cân bằng khối — sạch. **Chưa mô phỏng hành vi FSM/refill/fault thật** — cần Vivado/XSIM để xác nhận.

---

## 3. Trạng thái hiện tại của lõi RV32IMA (sau phiên này)

- Pipeline 5 tầng: Fetch – Decode – Execute – Memory – Writeback.
- ISA: RV32I đầy đủ, RV32M (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU qua đơn vị MDU nhiều chu kỳ), RV32A (LR.W/SC.W + AMOSWAP/ADD/XOR/OR/AND/MIN/MAX/MINU/MAXU.W).
- Forwarding + phát hiện hazard load-use + stall cho MDU nhiều chu kỳ.
- Hỗ trợ **2 lõi** dùng chung một bus dữ liệu qua `round_robin_arbiter_2core.v` (trọng tài round-robin 2 chiều, **chưa phải AHB/AXI interconnect thật**) và cơ chế LR/SC snoop giữa 2 lõi.
- **Chưa có cache L1/L2 thật** — hiện tại lõi (và cả `mmu_core_wrapper` mới) nối thẳng vào một mô hình RAM tổ hợp (combinational, 0 chu kỳ chờ) trong testbench/board-top, không phải cache thật với miss/refill.
- **Chưa có CSR, chưa có trap/exception, chưa có chế độ đặc quyền (M/S/U).**
- MMU (TLB+PTW) đã có RTL nhưng **chưa được nối vào core đang chạy trong dual-core/board-top hiện tại**.

---

## 4. Các thư mục tham khảo còn lại

### 4.1. `mmu_reference/mmu-main/`
MMU mã nguồn mở của **BSC (Barcelona Supercomputing Center)**, hỗ trợ Sv39 3 cấp, TLB + PTW, có cả tầng ảo hóa 2 giai đoạn (VS/G-stage), pseudo-LRU. Dùng làm tài liệu tham khảo kiến trúc khi thiết kế MMU RV32/Sv32 ở mục 2.2 — **không dùng trực tiếp** vì quá phức tạp so với phạm vi đề tài (Sv39, có ảo hóa, PPN 44-bit).

### 4.2. `cache_reference/`
Bản lưu một nỗ lực trước đó (Phase 1 – lõi đơn RV32I + MMU private cache; Phase 2 – mở rộng 4 lõi với interconnect, L2 dùng chung, cơ chế coherence dạng invalidate-broadcast). Có `README_PHASE1.md` và `README_PHASE2.md` mô tả chi tiết:
- Phase 1: đã PASS testbench, có ghi lại **5–6 lỗi cụ thể** từng gặp trong pipeline cũ (PC không stall khi cache miss, JAL/JALR nhảy sai, `wb_sel` sai, mux `b_sel` bị đảo, LUI bị shift 2 lần, `branch_signal` không khớp) — rất hữu ích để tránh lặp lại khi viết lại lõi mới.
- Phase 2: coherence mới ở mức **invalidate-broadcast** (ghi write-through về L2 + snoop invalidate các cache riêng khác), **chưa phải MESI đầy đủ** (không có trạng thái M/E/S/I, không có ownership transfer). Có ghi nhận **1 bug alias địa chỉ** trong D-cache cũ (`cpu_addr[2]` không được xét tới, hai địa chỉ cách nhau 4 byte bị đè lên nhau) — được đánh dấu "nên sửa đầu tiên ở Phase 3".
- Đây cũng là nơi đầu tiên ghi lại quyết định "bỏ F, giữ IMA" mà phiên làm việc này đã thực hiện trên `Risc_V_new/Risc_V`.

### 4.3. `Controller_Cache_2Cores_RV32IA/`
Chứa báo cáo chi tiết (`BaoCaoChiTiet`), báo cáo tóm tắt (`BaoCaoTomTat`), slide và link demo (`Link_Demo.txt`) của một đề tài **cùng hướng** ("Thiết kế bộ điều khiển đồng bộ cache cho các hệ thống 2 lõi dựa trên RV32IA"), kèm bộ RTL riêng, độc lập với `Risc_V_new` (core `RV32IA.v`, `dual_core.v`, `cache_L2.v`, `cache_coherence.v`, `moesi_controller.v`, có cả bộ dự đoán rẽ nhánh `BPU.v`/`BTB.v`/`PHT.v`). Đây là tài liệu tham khảo về **định dạng báo cáo/slide** và một cách hiện thực coherence khác (MOESI) — không phải là nhánh code đang phát triển của nhóm.

---

## 5. Việc cần làm tiếp (gợi ý, dựa trên khoảng cách giữa RTL hiện tại và mục tiêu đề tài)

1. Sửa lỗi elaborate của `tb_top.v` (mục 2.1) để mô phỏng được lại.
2. Mô phỏng thật `mmu_core_wrapper.v` (mục 2.2) để xác nhận FSM walk/refill/fault đúng như thiết kế — hiện mới kiểm tra tĩnh.
3. Thiết kế cache L1 (I/D) riêng cho từng lõi và cache L2 dùng chung — hiện tại **chưa tồn tại**, đang là RAM tổ hợp trực tiếp.
4. Thay `round_robin_arbiter_2core.v` (2 lõi) bằng interconnect thật (AHB/AXI) hỗ trợ 4 lõi.
5. Thiết kế cơ chế coherence (chọn rõ: invalidate-broadcast đơn giản hay MESI đầy đủ — xem file góp ý đề cương để biết vì sao điểm này cần chốt rõ).
6. Mở rộng từ 2 lõi lên 4 lõi.
7. Quyết định có đưa MMU/virtual memory vào phạm vi báo cáo chính thức hay không (hiện đề cương không nhắc tới MMU/TLB).
