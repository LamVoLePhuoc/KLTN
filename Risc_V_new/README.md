# Risc_V_new — Tiến độ & khoảng cách so với kiến trúc 4 lõi mục tiêu

Tài liệu sống, cập nhật mỗi phiên làm việc trong `Risc_V_new/`. Mục đích: nhìn một
lần là biết (1) cái gì đã xong, (2) cái gì đang dở, (3) cái gì hoàn toàn chưa có so
với kiến trúc 4 lõi mục tiêu (sơ đồ `4-CORE CPU WRAPPER` + `address_mapping`), và
(4) những quyết định kiến trúc còn treo mà thầy hướng dẫn đã yêu cầu chốt rõ.

> Xem thêm `../README.md` (gốc repo) — ghi lại chi tiết kỹ thuật của phiên xây MMU
> trước đó (xóa phần F, dựng `mmu_tlb.v`/`mmu_ptw.v`/`mmu_top.v`/`mmu_core_wrapper.v`).
> File này không lặp lại nội dung đó, chỉ tiếp nối và mở rộng thành bức tranh đầy đủ.

**Máy soạn tài liệu này không có Vivado/iverilog cài sẵn** → mọi RTL mới đều mới
chỉ được kiểm tra bằng cách đọc/suy luận thủ công cẩn thận (trace tay từng cycle),
**chưa chạy mô phỏng thật**. Việc còn lại là bạn chạy trong Vivado và báo kết quả —
đúng quy trình đã dùng ở `cache_reference/README_PHASE1.md`/`PHASE2.md`.

---

## 1. Trả lời thẳng: MMU đã "hoàn chỉnh" chưa?

**RTL: có, khá đầy đủ và được viết cẩn thận cho phạm vi 1 lõi.** `mmu_tlb.v`,
`mmu_ptw.v`, `mmu_top.v`, `mmu_core_wrapper.v` (viết từ phiên trước) đúng theo đặc tả
`address_mapping`: Sv32-style 2 cấp, TLB 16-entry fully-associative/lõi, permission
bit được kiểm tra lại ở **mọi** lần hit (không chỉ lúc nạp), fault không làm hỏng
pipeline (ép NOP / chặn store / trả 0 khi load) mà không có trap unit thật.

**Nhưng "hoàn chỉnh" thì chưa, theo đúng nghĩa sẵn sàng dùng**, vì 3 lý do cụ thể:

1. **Chưa từng được mô phỏng.** Không có testbench nào tồn tại trước phiên này.
   → Đã bổ sung `Risc_V/sim/tb_mmu_core.v` (xem mục 2). Bạn cần chạy nó.
2. **Chưa được nối vào bất kỳ top-level nào.** `mmu_core_wrapper` không được
   instantiate ở `RV32IMA_DualCore_Wrapper.v` hay `BoardTop.v` — nó vẫn là một khối
   rời, cố ý (đã ghi rõ trong `../README.md` mục 2.2, điểm 6).
3. **Chưa an toàn nếu nối thẳng vào bus dùng chung hiện tại.** Phát hiện mới trong
   phiên này: `mmu_ptw` được `mmu_top` gắn cứng `mem_valid=1'b1`, tức là giả định
   cổng nhớ của PTW là **riêng, không tranh chấp, luôn phục vụ trong đúng 1 chu kỳ**.
   Nếu nối `ptw_mem_req/ptw_mem_addr/ptw_mem_rdata` thẳng vào
   `round_robin_arbiter_2core` hiện tại, bất kỳ chu kỳ nào trọng tài từ chối cấp
   quyền, PTW sẽ **âm thầm coi dữ liệu rác/của lõi khác là PTE thật** — sai mà không
   báo lỗi. Đã ghi chú rõ trong `rtl/mmu_top.v` (comment "CAUTION"). Hướng giải quyết
   đúng không phải là vá nhanh, mà là: một khi có L1 D-cache riêng từng lõi (đang ở
   kiến trúc mục tiêu), PTW đọc page table qua chính D-cache đó — vốn dĩ đã cần
   giao thức valid/miss thật — nên vấn đề này tự biến mất khi Phase cache xong.
   Cho tới lúc đó: **không nối MMU vào bus dùng chung hiện tại.**

**Kết luận:** phần lõi MMU (TLB+PTW+wrapper 1 lõi) coi như xong về mặt thiết kế,
đang chờ bạn xác nhận bằng mô phỏng thật. Phần "MMU trong hệ 4 lõi" thì chưa bắt đầu
và phụ thuộc vào các khối chưa tồn tại (cache L1, bus thật) — xem mục 4.

---

## 2. Việc đã làm trong phiên này

| File | Thay đổi |
|---|---|
| `Risc_V/sim/tb_mmu_core.v` | **Mới.** Testbench tự kiểm (self-checking) cho `mmu_core_wrapper`, độc lập, không đụng tới `RV32IMA_DualCore_Wrapper`/`BoardTop` đã tổng hợp trên FPGA. Dựng sẵn 1 page table 2 cấp (root @ PA 0x0000, L0 @ PA 0x1000) ánh xạ 3 trang khác nhau (code R+X, data R+W, data R-only) và cố ý để 1 trang không map, rồi chạy 1 chương trình 13 lệnh tay-assemble kiểm: dịch địa chỉ đúng (VA≠PA thật sự, không phải identity map), TLB refill, store bị chặn đúng khi ghi vào trang read-only (bắt được ngay trong lúc PTW walk, không cần refill TLB trước), not-present fault trả load=0, dữ liệu ở trang RO không bị hỏng. Xem header file để biết cách chạy trong Vivado XSIM. |
| `Risc_V/rtl/mmu_top.v` | Thêm comment "CAUTION" giải thích rõ giới hạn `mem_valid=1'b1` (mục 1, điểm 3) — không sửa logic, chỉ ghi chú để không ai vô tình nối sai. |
| `Risc_V/sim/tb_top.v` | Sửa lỗi elaborate đã biết (ghi trong `../README.md` mục 2.1): bỏ `#(.CORE0_RESET_ADDR(...), .CORE1_RESET_ADDR(...))` khi instantiate `RV32IMA_DualCore_Wrapper` vì module đó không khai báo 2 parameter này (cố ý, để tránh lỗi Vivado synth đã từng gặp — xem comment mới trong file). Hệ quả: 2 lõi trong `tb_top` giờ cùng boot ở `RESET_ADDR` mặc định (0x1000) thay vì 0x0/0x100 như ý định ban đầu của testbench — xem mục 5, hạng mục "boot address per-core" trong danh sách rủi ro. |
| `Risc_V_new/README.md` | File này. |

**Chưa làm** (cố ý, xem lý do ở mục 3 và mục "Quyết định cần chốt"): chưa viết
`RV32IMA_DualCore_MMU_Wrapper.v` để thật sự nối MMU vào dual-core — vì làm đúng cách
đòi hỏi giải quyết vấn đề `mem_valid`/arbiter ở trên trước, nếu không sẽ tạo ra một
khối "trông như chạy được" nhưng sai âm thầm dưới tải — không phù hợp với yêu cầu
"cẩn thận, logic" của bạn.

### Cách chạy `tb_mmu_core.v` trong Vivado

1. Add as simulation/design sources: toàn bộ `Risc_V/rtl/*.v` (đặc biệt `mmu_tlb.v`,
   `mmu_ptw.v`, `mmu_top.v`, `mmu_core_wrapper.v`, `RV32IMA.v` và mọi file nó include)
   cộng `Risc_V/sim/tb_mmu_core.v`.
2. Set `tb_mmu_core` làm simulation top.
3. Run Behavioral Simulation, `run -all` ở Tcl Console.
4. Kỳ vọng thấy 12 dòng `[PASS] ...` và cuối cùng `MMU_TB: PASS`. Nếu có `[FAIL]`,
   gửi lại log — đó chính xác là chỗ cần sửa trong `mmu_top.v`/`mmu_ptw.v`/`mmu_tlb.v`.

---

## 3. Kiến trúc mục tiêu (theo sơ đồ 4-CORE CPU WRAPPER + `address_mapping`)

```
4 x [Register File | ALU | Pipeline IF/ID/EX/MEM/WB | MMU+TLB | L1 D$ | L1 I$]
              │ (mỗi core)
        HIGH-SPEED BUS (AHB)
              │
   SHARE L2 CACHE  <──>  COHERENCE MANAGEMENT UNIT
              │
        CPU MEMORY PORT
              │
        SYSTEM BUS (AXI4)
     ┌────────┼────────┬─────────────┐
   DMA      SRAM      MEMORY       INTERRUPT
 CONTROLLER CONTROLLER CONTROLLER  CONTROLLER
              │            │
            SRAM         DDRAM
```

`address_mapping` (file text do bạn viết) bổ sung chi tiết định lượng:
- VA 32-bit, 2 cấp trang, page 4KB.
- TLB: 16-entry fully-associative / lõi.
- L1 (PIPT): 16KB, 2-way, line 32B → offset 5b / index 8b / tag 19b.
- L2 (PIPT, dùng chung): **256KB**, 4-way, line 32B → offset 5b / index 11b / tag 16b.
- Bản đồ địa chỉ vật lý 4GB: Boot ROM 64KB @ 0x0000_0000, Main RAM (cacheable) @
  0x8000_0000–0xBFFF_FFFF, còn lại reserved.
- Coherence: **MESI**, theo dõi theo physical line 32B, directory dạng bitmap 4-bit
  sharer (4 lõi), lưu tại L2.

---

## 4. Quyết định kiến trúc còn treo — CẦN CHỐT TRƯỚC KHI VIẾT THÊM RTL LỚN

Lấy từ `../Gop_y_De_cuong_KLTN.txt` (góp ý của giảng viên) + đối chiếu với những gì
đang thật sự nằm trong repo. Đây không phải việc tôi có thể tự quyết — nêu ra để bạn
chốt, vì chọn sai sẽ làm lại tốn nhiều công:

1. **AHB hay AXI4?** Đề cương cũ mâu thuẫn (mục tiêu ghi AHB, bảng kế hoạch ghi
   AXI4). Sơ đồ mới nhất của bạn thực ra dùng **cả hai** (AHB nội bộ giữa 4 core +
   L2 + coherence unit; AXI4 làm system bus ra DMA/SRAM ctrl/memory ctrl/interrupt
   ctrl) — nếu đây đúng là hướng chốt, cần ghi rõ và nhất quán trong toàn bộ đề
   cương/báo cáo (giảng viên đã lưu ý điểm mâu thuẫn này).
2. **Coherence: MESI đầy đủ hay invalidate-broadcast đơn giản?** `address_mapping`
   của bạn ghi rõ MESI 4 trạng thái + directory bitmap. Nhưng `cache_reference`
   (tham khảo) chỉ hiện thực invalidate-broadcast (tự nhận trong chính README của
   nó là "not a full MESI"), còn `Controller_Cache_2Cores_RV32IA` (tham khảo khác)
   dùng **MOESI**. Ba nguồn, ba câu trả lời khác nhau — giảng viên cũng đã chỉ ra
   đúng mâu thuẫn này (mục E.3 trong file góp ý). Cần chốt 1 phương án chính thức.
3. **MMU/virtual memory: có nằm trong phạm vi báo cáo chính thức không?**
   Giảng viên lưu ý đề cương (kể cả bản viết lại) **không hề nhắc tới MMU/TLB**, dù
   RTL đã có. Khối lượng còn lại (cache + bus + DMA + SD card) đã rất lớn cho ~3.5
   tháng — cân nhắc: nếu MMU không nằm trong cam kết điểm số, có thể để nó là "phần
   mở rộng ngoài phạm vi" (RTL vẫn giữ, không xóa) để dồn lực cho phần bắt buộc.
4. **Kích thước L2: 256KB (`address_mapping`) hay 512KB (sơ đồ + `cache_reference`
   Phase 2)?** Hai nguồn của chính bạn không khớp nhau — cần chốt 1 số.
5. **L1: 16KB/2-way dùng chung 1 kích thước (`address_mapping`) hay 32KB I$ + 32KB
   D$ tách riêng (sơ đồ)?** Cũng lệch nhau, cần chốt.
6. **Kịch bản test trên FPGA phải thật (bắt buộc theo giảng viên, mục D):**
   chương trình phải nạp từ bộ nhớ ngoài thật (thẻ SD qua SPI) vào DRAM rồi CPU mới
   chạy từ DRAM — **không được** nạp thẳng vào BlockRAM rồi chạy luôn kiểu hiện tại
   ở `BoardTop.v` (`$readmemh("program.mem", ram)` ngay trong FPGA). Đây là một khối
   lượng công việc mới, riêng biệt (bộ điều khiển SD/SPI + bootloader), chưa có bất
   kỳ RTL/tham khảo nào trong repo cho phần này.

**Tôi chưa tự ý chọn thay bạn ở bất kỳ điểm nào trên** — làm sai hướng ở đây (ví dụ
viết MESI đầy đủ trong khi bạn định chốt invalidate-broadcast) sẽ lãng phí rất nhiều
công sức không thể tận dụng lại.

---

## 5. Bảng khoảng cách (gap analysis) — theo từng khối trong sơ đồ

| # | Khối (theo sơ đồ) | Trạng thái trong `Risc_V_new` | Tham khảo có sẵn |
|---|---|---|---|
| 1 | CPU core (Register File/ALU/Pipeline 5 tầng) | **Có**, `RV32IMA.v`, RV32IMA đầy đủ (I/M/A). Mới **2 lõi** instantiate (`RV32IMA_DualCore_Wrapper.v`), sơ đồ cần **4**. | — |
| 2 | MMU + TLB (per-core) | RTL **có, đã unit-test bằng `tb_mmu_core.v` (chờ bạn chạy)**; **chưa nối vào top nào**; **chưa an toàn sau bus dùng chung** (mục 1). | `mmu_reference/mmu-main` (Sv39 BSC, tham khảo thiết kế, không dùng trực tiếp — quá nặng: Sv39 + ảo hóa 2 giai đoạn + PPN 44-bit). |
| 3 | L1 I-Cache / D-Cache (per-core) | **Hoàn toàn chưa có.** Hiện tại core (và cả `mmu_core_wrapper`) nối thẳng vào RAM tổ hợp 0-chu-kỳ, không phải cache thật. | `cache_reference/MMU/{I_Cache,D_Cache,I_CacheController,D_CacheController,TagArray,DataArray,Comparator}.sv` (dùng cho core khác — `core_top.sv`, không phải `RV32IMA.v` — cần viết lại giao diện, không copy nguyên); `Controller_Cache_2Cores_RV32IA/RTL/{icache,dcache,icache_controller,dcache_controller}.v`. **Lưu ý bug đã biết:** D-cache cũ ở `cache_reference` chọn slot chỉ bằng `cpu_addr[4:3]`, bỏ qua `cpu_addr[2]` → 2 địa chỉ cách nhau 4 byte bị đè lên nhau (ghi rõ trong `README_PHASE2.md` và được giảng viên nhắc lại ở mục E.7) — nếu tái dùng thiết kế này, **sửa bug này trước tiên**. |
| 4 | AHB shared bus (4 core + L2 + coherence) | **Chưa có.** Đang dùng `round_robin_arbiter_2core.v` — trọng tài word-level tự viết, không phải AHB thật, chỉ 2-way. | Không có AHB IP tham khảo trong 3 folder; `cache_reference/MMU/AXI4-Interconnect-main` là AXI4, không phải AHB. |
| 5 | Shared L2 Cache | **Chưa có** trong `Risc_V_new`. | `cache_reference/MMU/multicore/{L2_Cache,L2_CacheController,L2_TagArray,L2_DataArray}.sv` — 512KB, 2-way, 8192 sets, line 256-bit (⚠ lệch line size 32B mà `address_mapping` yêu cầu — cần đối chiếu lại nếu tái dùng). |
| 6 | Coherence Management Unit | **Chưa có.** | `cache_reference/MMU/multicore/interconnect.sv` (invalidate-broadcast, không phải MESI); `Controller_Cache_2Cores_RV32IA/RTL/{moesi_controller,cache_coherence,snoop_controller,d_coherence}.v` (MOESI — **lưu ý**: `moesi_controller.v` có comment "from Lee Min Hunz with luv", khả năng có nguồn gốc bên ngoài — nên xác minh lại tính đúng đắn/bản quyền trước khi tái sử dụng trong đồ án của chính mình, không nên coi là đã kiểm chứng chỉ vì nó tồn tại trong repo tham khảo). |
| 7 | CPU Memory Port / System Bus (AXI4) | **Chưa có.** | `cache_reference/MMU/AXI4-Interconnect-main/` (rtl AXI4 interconnect đầy đủ: dispatcher, arbitration, R/W/AR/AW/B channel splitters, skid buffer, FIFO — có vẻ là IP ngoài, kiểm tra license trước khi nộp báo cáo). |
| 8 | DMA Controller | **Chưa có RTL ở bất kỳ đâu trong repo** (kể cả 3 folder tham khảo) — cần thiết kế mới hoặc tìm IP ngoài. Theo góp ý giảng viên, mục đích chính là phục vụ luồng nạp chương trình SD-card → DRAM (mục 4, điểm 6), không phải tính năng phụ. | Không có. |
| 9 | SRAM Controller + SRAM | **Chưa có.** | Không có. |
| 10 | Memory Controller (DDR) + DDRAM | **Chưa có** bộ điều khiển DDR thật tổng hợp được. `cache_reference/.../mem_model.sv` chỉ là mô hình hành vi cho mô phỏng, không synthesize lên FPGA thật được. | Không có IP DDR controller tham khảo trong repo — thường dùng MIG (Memory Interconnect Generator) IP có sẵn của Vivado cho board mục tiêu. |
| 11 | Interrupt Controller | **Chưa có**, và core hiện tại cũng chưa có CSR/trap/privilege mode để nhận interrupt. | Không có. |
| 12 | Mở rộng 2→4 core + interconnect tương ứng | `round_robin_arbiter_2core.v` hard-code 2-way — cần thiết kế lại (round-robin 4-way tối thiểu, hoặc bỏ hẳn để thay bằng AHB/crossbar thật). | — |
| 13 | Trap/exception unit, CSR, privilege mode (M/S/U) | **Chưa có.** Page fault từ MMU hiện chỉ ép NOP/chặn store/trả 0 — không trap thật (đã tự flag trong `mmu_core_wrapper.v`). Cần thiết nếu muốn MMU "dùng thật" (ví dụ demo page-fault handler), và cũng cần cho U-bit của PTE có ý nghĩa. | — |
| 14 | LR/SC đúng đắn khi có MMU (nhiều lõi, page table độc lập) | **Chưa an toàn tuyệt đối** — đã tự flag trong `mmu_core_wrapper.v`: snoop so khớp PA từ lõi khác với VA nội bộ (trên MMU), chỉ đúng nếu mọi lõi map cùng VA→PA cho vùng atomic dùng chung. | — |
| 15 | Bootloader thật từ SD card (SPI) → DRAM | **Chưa có gì** — không RTL, không tham khảo. Bắt buộc theo giảng viên (mục D góp ý) để kịch bản FPGA là "processor thật", không phải "nạp sẵn vào BlockRAM". Cần chọn: tự viết SPI/SD controller, hay dùng Vivado AXI SD/SDIO IP, hay driver SPI mã nguồn mở đã kiểm chứng. | Không có trong repo. |
| 16 | Kịch bản đánh giá tự động trên FPGA (không xem waveform thủ công) | **Chưa có** — cần cơ chế tự báo PASS/FAIL trên board (LED mã hóa, UART log, hoặc tương tự). | `tb_top.v`/`tb_mmu_core.v` mới chỉ tự-kiểm trong **mô phỏng**, chưa phải "tự động trên FPGA thật". |

---

## 6. Đánh giá 3 folder tham khảo (mức độ tin cậy, cách dùng đúng)

- **`mmu_reference/mmu-main/`** — MMU Sv39 mã nguồn mở thật của BSC, chất lượng
  công nghiệp (pseudo-LRU thay vì round-robin, PTW có arbiter riêng `ptw_arb.sv`,
  hỗ trợ ảo hóa 2 giai đoạn). Dùng để **học cách họ giải quyết các vấn đề khó**
  (VD: thay thế TLB thông minh hơn round-robin hiện tại của bạn) chứ không copy —
  interface/convention khác hẳn (`bsc_mmu_hpdc_adapter.sv` cho thấy nó được thiết kế
  cho một cache/core khác), và scope (Sv39, PA 34-bit) vượt quá nhu cầu Sv32/PA
  32-bit của bạn.
- **`cache_reference/`** — Đây thực chất là **một nhánh phát triển song song, tự
  đứng riêng** (core `core_top.sv`/`decode.v`/`execute.v`/`write_back.v` — khác hẳn
  `RV32IMA.v` 5-tầng của bạn), đã tự báo PASS Phase 1 (lõi đơn + MMU cache) và có
  thiết kế Phase 2 (4 lõi + L2 512KB + coherence invalidate-broadcast) — nhưng
  **PASS đó là của core khác**, không tự động nói lên gì về `Risc_V_new`. Giá trị
  thật: (a) danh sách 5-6 lỗi cụ thể đã từng gặp và sửa trong một pipeline RV32I
  tương tự (đáng đọc để tránh lặp lại — xem `README_PHASE1.md`), (b) cấu trúc thiết
  kế L2/interconnect/coherence có thể học theo (không copy thẳng, vì line size
  256-bit ở đó lệch với 32B trong `address_mapping` của bạn), (c) bug alias địa chỉ
  D-cache đã biết, cần tránh lặp lại.
- **`Controller_Cache_2Cores_RV32IA/`** — Đồ án của nhóm khác, 2 lõi, kèm báo cáo
  đầy đủ. Tham khảo tốt cho **cách trình bày báo cáo/slide** và cho **thiết kế
  MOESI** (gần với "coherence thật" hơn invalidate-broadcast ở trên) — nhưng đây là
  **RTL của người khác cho đề tài của người khác**: (1) chưa được tôi (hay ai trong
  phiên này) kiểm chứng đúng/sai, (2) `moesi_controller.v` có dòng comment gợi ý
  nguồn gốc bên ngoài ("from Lee Min Hunz") — cần tự xác minh lại trước khi dựa vào,
  đặc biệt nếu định trích dẫn/tái sử dụng trong báo cáo tốt nghiệp của chính bạn.

---

## 7. Lộ trình đề xuất (theo pha, để bạn ưu tiên — không tự ý làm hết)

- [x] **Phase 0** — Lõi RV32IMA 2 lõi chạy được trên FPGA (đã tổng hợp, xem
      `Risc_V.runs/`), MMU 1-lõi viết xong về thiết kế.
- [ ] **Phase 1a** — Bạn chạy `tb_mmu_core.v` trong Vivado, xác nhận PASS/FAIL,
      báo lại kết quả để sửa tiếp nếu có FAIL. *(Việc cụ thể tiếp theo, nhỏ, rõ.)*
- [ ] **Phase 1b** — Chốt 5 quyết định kiến trúc ở mục 4 (AHB/AXI4 dùng thế nào,
      coherence protocol, MMU in/out scope, kích thước L1/L2). *(Không thể làm thay.)*
- [ ] **Phase 2** — Thiết kế L1 I$/D$ set-associative riêng từng lõi theo đúng
      `address_mapping` (16KB, 2-way, line 32B, PIPT — tức là **sau** MMU, không phải
      trước, vì PIPT cần địa chỉ vật lý đã dịch), viết lại từ đầu cho khớp giao diện
      `RV32IMA`/`mmu_core_wrapper` (không copy thẳng cache_reference — xem mục 6).
- [ ] **Phase 3** — Nhân bản lên 4 core; thiết kế AHB (hoặc bus đã chốt ở 1b) thay
      `round_robin_arbiter_2core.v`.
- [ ] **Phase 4** — Shared L2 (256KB hoặc 512KB, đã chốt) + Coherence Management
      Unit theo giao thức đã chốt (MESI/MOESI/invalidate-broadcast).
- [ ] **Phase 5** — AXI4 system bus + Memory Controller (DDR, có thể dùng MIG IP) +
      SRAM Controller + Interrupt Controller + DMA Controller.
- [ ] **Phase 6** — Bootloader SD/SPI → DRAM (bắt buộc theo giảng viên) + kịch bản
      đánh giá tự động thật trên FPGA.
- [ ] **Phase 7 (tùy chọn)** — Trap/exception unit + CSR + privilege mode, để MMU
      page-fault thật sự trap được (chỉ làm nếu Phase 1b giữ MMU trong phạm vi).

---

## 8. Sổ rủi ro / việc dễ quên

1. `mmu_top.v`'s `mem_valid=1'b1` không an toàn sau bus dùng chung — xem mục 1.
2. D-cache alias bug (`cpu_addr[2]` bị bỏ qua) trong thiết kế tham khảo
   `cache_reference` — đừng lặp lại nếu viết L1 D-cache mới dựa theo cấu trúc đó.
3. `tb_top.v` hiện để 2 lõi boot cùng địa chỉ (0x1000) thay vì khác nhau — nếu cần
   kịch bản 2 chương trình độc lập, phải giải quyết lại việc parameterize
   `RV32IMA_DualCore_Wrapper.v` **một cách an toàn cho synthesis** (không lặp lại
   lỗi Vivado cũ đã khiến ai đó bỏ `#(.RESET_ADDR(...))` đi).
4. LR/SC qua nhiều lõi chưa đúng dưới MMU độc lập theo lõi (mục 5, #14).
5. `moesi_controller.v` (tham khảo) có dấu hiệu nguồn gốc ngoài — xác minh trước
   khi trích dẫn/tái dùng trong báo cáo.
6. Kích thước L2 và L1 lệch nhau giữa `address_mapping` và sơ đồ — đừng bắt đầu
   viết RTL cache tới khi chốt số liệu (mục 4, #4-#5).
