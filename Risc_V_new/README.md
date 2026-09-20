# Risc_V_new — Tiến độ & khoảng cách so với kiến trúc 4 lõi mục tiêu

Tài liệu sống, cập nhật mỗi phiên làm việc trong `Risc_V_new/`. Mục đích: nhìn một
lần là biết (1) cái gì đã xong, (2) cái gì đang dở, (3) cái gì hoàn toàn chưa có so
với kiến trúc 4 lõi mục tiêu (sơ đồ `4-CORE CPU WRAPPER` + `address_mapping`), và
(4) những quyết định kiến trúc còn treo mà thầy hướng dẫn đã yêu cầu chốt rõ.

> Xem thêm `../README.md` (gốc repo) — ghi lại chi tiết kỹ thuật của phiên xây MMU
> đầu tiên (xóa phần F, dựng `mmu_tlb.v`/`mmu_ptw.v`/`mmu_top.v`/`mmu_core_wrapper.v`).
> File này không lặp lại nội dung đó, chỉ tiếp nối và mở rộng thành bức tranh đầy đủ.

**Máy soạn tài liệu này không có Vivado/iverilog cài sẵn** → mọi RTL mới đều mới
chỉ được kiểm tra bằng cách đọc/suy luận thủ công cẩn thận (trace tay từng cycle,
nhiều vòng review lại chính mình), **chưa chạy mô phỏng thật**. Việc còn lại là bạn
chạy trong Vivado và báo kết quả — đúng quy trình đã dùng ở
`cache_reference/README_PHASE1.md`/`PHASE2.md`.

---

## -1. Sắp xếp lại thư mục (mới nhất)

Theo yêu cầu, đã gom 4 file thuộc nhánh 2 lõi cũ (đã chạy trên FPGA thật, xem mục 0)
vào `rtl/legacy_2core/`: `RV32IMA_DualCore_Wrapper.v`, `RV32IMA_DualCore_BoardTop.v`,
`round_robin_arbiter_2core.v`, `RV32_IP_Wrapper.v` — cộng testbench tương ứng
`sim/tb_top.v` → `sim/legacy_2core/tb_top.v`. Đã xác nhận: không có script hay file
RTL mới nào phụ thuộc chức năng vào đường dẫn cũ của 4 file này (chỉ có comment nhắc
tên). **Chưa sửa `Risc_V.xpr`** (theo đúng yêu cầu, không đụng vào project hiện tại)
— lần tới mở Vivado, project sẽ báo "missing source" cho đúng 4 file đã chuyển, bạn
cần tự relocate lại trong GUI (Add Sources hoặc chuột phải vào source báo lỗi >
Re-locate to). Mọi file khác (pipeline gốc dùng chung, MMU, hệ 4 lõi mới) vẫn nằm
nguyên ở `rtl/`/`sim/` như cũ, không di chuyển.

---

## -0.5. Phiên mới nhất: Trap/Exception Unit + CSR + Privilege Mode (M/S/U), AHB-Lite adapter, khảo sát board

Tiếp theo yêu cầu "hoàn thiện Trap/Exception Unit + CSR + Privilege Mode", "phát triển
AHB-Lite dựa trên `ahb3lite_interconnect-master_reference/`", và "xây kịch bản triển
khai cho Genesys ZU-5EV rồi VCU129". Đây là phiên **lớn và rủi ro cao thứ nhì** sau
phần coherence (mục 2) — sửa sâu vào pipeline core đã chạy trên FPGA thật, dù chỉ ở
nhánh MỚI (không đụng `legacy_2core/` về mặt logic, chỉ tie-off 2 port mới cho khỏi
nổi X — xem mục -0.5.3).

### -0.5.1. CSR / Trap / Privilege — file mới

| File | Vai trò |
|---|---|
| `rtl/sys_decoder.v` | Giải mã tinh (fine-grain) không gian SYSTEM/funct3=0: ECALL/EBREAK/MRET/SRET/WFI/SFENCE.VMA, cộng kiểm tra "opcode có hợp lệ không" (illegal instruction). Tách riêng khỏi `Main_Decoder.v` — `Main_Decoder.v` chỉ cần biết "CSR op có ghi rd hay không", không cần biết đây là lệnh gì trong nhóm funct3=0. |
| `rtl/csr_trap_unit.v` | CSR file M/S (mstatus/sstatus, mtvec/stvec, mepc/sepc, mcause/scause, mtval/stval, mscratch/sscratch, medeleg/mideleg, satp, misa, mhartid) + máy trạng thái đặc quyền (M/S/U) + phát hiện và xử lý exception đồng bộ (ECALL/EBREAK/illegal instruction/page fault) + MRET/SRET + tính PC redirect. **File phức tạp và rủi ro nhất trong đợt này.** |

### -0.5.2. CSR / Trap / Privilege — vì sao phải sửa nhiều file pipeline cũ (không tránh được)

Khác với MMU (chỉ cần bọc wrapper bên ngoài `RV32IMA.v`, không đụng file gốc), CSR
**bắt buộc** phải sửa sâu vì giá trị đọc CSR phải chảy tới tận writeback để ghi vào
`rd`, và trạng thái đặc quyền phải chặn được PC ngay tại fetch. Đã cố gắng tối giản
tối đa trước khi sửa (xem chi tiết trong từng file):
- Tận dụng encoding **có sẵn nhưng chưa dùng**: `ResultSrc=2'b11` (trước đây rơi vào
  `default` trả về 0), `ImmSrc=3'b110` (Sign_Extend.v **đã có sẵn case CSR imm** từ
  trước — không phải viết mới).
- Tận dụng tín hiệu **có sẵn nhưng đặt sai chỗ**: `CSR_D`→`CSR_E`→`CSR_M` (cờ CSR)
  và `MemOpM` (= funct3, gán vô điều kiện cho mọi lệnh, không chỉ load/store) đã tồn
  tại xuyên suốt pipeline từ trước — tái dùng thay vì thêm field mới.
- Tận dụng giá trị forwarded **đã tính sẵn** trong `execute_stage.v` (`SrcA_Forwarded`)
  cho toán hạng rs1 của CSRRW/S/C thay vì viết lại logic forwarding.
- `PCM` tính bằng `PCPlus4M - 4` (không có lệnh nén) thay vì thêm hẳn 1 field PC mới
  xuyên suốt id_ex/ex_mem_registers.
- 8 tín hiệu exception (`FetchPageFault`+7 cờ từ `sys_decoder.v`) đóng gói chung 1 bus
  8-bit khi truyền qua `id_ex_registers.v`/`ex_mem_registers.v`, tránh nổ số lượng port.
- Redirect PC/flush khi trap: **không sửa `fetch_stage.v` hay `hazard_unit.v`** — chỉ
  OR thêm `TrapTakenM` vào đúng các dây `PCSrcE`/`FlushD`/`FlushE` **ở ngoài**, tại
  `RV32IMA.v`, trước khi đưa vào 2 module đó. Mux 2-ngã sẵn có của chúng tự động xử lý
  đúng ưu tiên (lệnh trap luôn già hơn lệnh đang ở E, nên luôn thắng) mà không cần sửa
  logic bên trong.

**Danh sách đầy đủ file bị sửa** (tất cả đều additive — thêm port/field, không xóa gì
sẵn có): `Main_Decoder.v`, `Control_Unit.v` (1 dòng), `decode_stage.v`, `if_id_registers.v`,
`id_ex_registers.v`, `execute_stage.v`, `ex_mem_registers.v`, `mem_wb_registers.v`,
`writeback_stage.v`, `RV32IMA.v` (nhiều nhất — nơi ráp mọi thứ + gọi `csr_trap_unit`),
`mmu_core_wrapper.v` (nối `Fetch_PageFault_In`/`Data_PageFault_In` từ 2 wire nội bộ
sẵn có `fetch_fault`/`mem_fault` — page fault từ MMU giờ **trap thật** thay vì chỉ ép
NOP như trước). **Đã đối chiếu tự động port giữa mọi module và chỗ gọi nó** (giống
cách làm ở phiên coherence) — khớp 100% cho mọi kết nối thật sự dùng.

**3 bug thật đã bắt và sửa khi tự review `csr_trap_unit.v`**:
1. Field nhiều bit (MPP, SPP...) bị "dịch" về bit0 rồi ghép với `CsrWDataM` — nhưng
   `CsrWDataM` vẫn giữ nguyên vị trí bit thật (VD: MPP ở bit[12:11], không phải
   bit[1:0]) → CSRRS/CSRRC sẽ đọc sai hoàn toàn bit của `mstatus`/`sstatus`/`satp`.
   Sửa bằng cách luôn ghép ở đúng vị trí bit thật rồi mới trích ra.
2. `TrapPCM` (địa chỉ nhảy tới) được gán trong khối tuần tự (`<=`), nhưng `TrapTakenM`
   lại tổ hợp (combinational) — nghĩa là đúng chu kỳ `TrapTakenM` báo có trap, `TrapPCM`
   vẫn còn giữ giá trị CŨ của lần trap trước, trễ mất 1 chu kỳ. Sửa bằng cách làm
   `TrapPCM` cũng tổ hợp, đọc thẳng `mepc`/`sepc`/`mtvec`/`stvec` hiện tại.
3. Một dòng label rác còn sót lại từ lúc soạn thảo (`integer_unused:` không gắn với
   statement nào) — lỗi cú pháp Verilog thật, sẽ chặn compile ngay từ đầu. Đã xóa.

**Giới hạn có chủ đích** (ghi đầy đủ trong header `csr_trap_unit.v`): chưa có ngắt
(interrupt) — không có nguồn ngắt thật nào trong hệ thống (đúng như gap đã ghi ở mục
5, dòng #11 cũ); `satp` là CSR thật (đọc/ghi được) nhưng **chưa nối vào `mmu_core_wrapper`
thật** — `Mmu_Enable_Csr`/`Satp_PPN_Csr` đã lộ ra ngoài làm output quan sát được,
nhưng cố ý **chưa** dây vào chỗ đang nhận `Mmu_Enable`/`Satp_PPN` từ bên ngoài, để
không chồng 2 thay đổi lớn chưa mô phỏng lên cùng 1 đường tín hiệu trong cùng 1 phiên.

### -0.5.3. Vì sao phải sửa `legacy_2core/` — ngoại lệ duy nhất, có lý do rõ

`RV32IMA.v` giờ có 2 input mới bắt buộc (`Fetch_PageFault_In`, `Data_PageFault_In`).
2 file trong `legacy_2core/` (`RV32IMA_DualCore_Wrapper.v`, `RV32_IP_Wrapper.v`) gọi
thẳng `RV32IMA` — nếu không nối, 2 input này sẽ nổi (X trong mô phỏng), có thể làm
`csr_trap_unit.v` bên trong tự trap linh tinh, **âm thầm phá luôn khả năng mô phỏng
lại** của đúng nhánh 2 lõi mà bạn muốn giữ làm fallback đã chứng minh. Đây là ngoại lệ
DUY NHẤT với yêu cầu "không đụng file cũ": chỉ tie `1'b0` vào đúng 2 port đó ở cả 3 chỗ
gọi (`core0`, `core1`, `RV32_IP_Wrapper`'s `core`) — không đổi bất kỳ dòng logic nào
khác. Bitstream đã build sẵn trong `Risc_V.runs/` hoàn toàn không bị ảnh hưởng (đó là
file nhị phân đã đóng băng, không phụ thuộc mã nguồn hiện tại).

### -0.5.4. AHB-Lite

Đã đọc `ahb3lite_interconnect-master_reference/` (IP thật của Roa Logic) để lấy đúng
quy ước giao thức — **không** gắn trực tiếp vì 3 lý do: (1) giấy phép Non-Commercial
(có thể dùng cho mục đích học thuật nhưng cần trích dẫn/kiểm tra chính sách trường nếu
đưa vào báo cáo), (2) thiếu submodule phụ thuộc `ahb3lite_pkg` (repo chỉ tải về phần
chính, chưa có package types), (3) là crossbar multi-layer N-master/N-slave — thừa so
với nhu cầu thực tế (mọi traffic đều dồn về đúng 1 L2/coherence engine).

Thay vào đó: file mới `rtl/ahb_lite_l1_adapter.v` — bộ chuyển đổi cổng miss/writeback
của 1 cache L1 (`l1_icache.v`/`l1_dcache.v`) sang tín hiệu AHB-Lite **thật** (HADDR/
HWRITE/HSIZE/HTRANS/HWDATA/HRDATA/HREADY/HRESP đúng tên, đúng pha địa chỉ-rồi-dữ-liệu
theo chuẩn AMBA — không phải API kiểu AXI dán nhãn AHB). Đã tự bắt và sửa 2 lỗi khi
review: 1 ký tự `#` gõ nhầm (đáng lẽ `//`) làm hỏng cú pháp comment, và 1 lỗi cộng dồn
địa chỉ 2 lần (tăng `line_addr` cả trong thanh ghi lẫn trong phép tính `HADDR`, khiến
địa chỉ sai kể từ word thứ 2 trở đi).

**CẬP NHẬT (mục -0.25.2, phiên này): đã nối vào top-level 4 lõi** — thêm file slave
phía bên kia (`ahb_lite_l1_slave_adapter.v`) + 1 biến thể top-level mới
(`quad_core_soc_ahb.v`, song song với `quad_core_soc.v`, không sửa file cũ). Xem mục
-0.25.2 cho toàn bộ chi tiết thiết kế/giới hạn.

**Việc còn treo (không đổi)**: `coherence_manager.v`'s bus nội bộ (8 nguồn → L2) vẫn
dùng giao thức tự đặt (`dreq_valid`/`dreq_type`/...), không phải tên tín hiệu AHB-Lite
chuẩn — cố ý không đổi vì file đó đã qua nhiều vòng review/có testbench riêng
(`tb_coherence.v`), đổi tên tín hiệu lúc này có nguy cơ đưa bug mới vào logic đã tin
tưởng. `quad_core_soc_ahb.v` (mục -0.25.2) giải quyết đúng khoảng cách này ở biên
CORE↔BUS (nơi sơ đồ thật sự vẽ AHB) mà không cần đổi `coherence_manager.v` — nếu đề
cương/hội đồng vẫn cần đúng tên tín hiệu AHB-Lite ở SÂU hơn nữa (bên trong chính trọng
tài), đó là việc đổi lớp vỏ tín hiệu tại biên trọng tài của `coherence_manager.v`,
không phải viết lại logic — nên làm SAU khi `tb_coherence.v` chạy PASS trong Vivado.

### -0.5.5. Khảo sát board (Genesys ZU-5EV → VCU129)

Đã tra cứu thông số thật qua web (không đoán số liệu phần cứng) — nguồn đầy đủ ở cuối
mục này.

**Genesys ZU-5EV** (bước demo gần, khuyến nghị bắt đầu ở đây):
- Chip: Zynq UltraScale+ **XCZU5EV-SFVC784-1-E** — có PS cứng (4× Cortex-A53 + 2×
  Cortex-R5), có PL (logic khả trình) để đặt lõi RISC-V tự thiết kế.
- RAM: 4GB DDR4-2133 (qua PS, hoặc PL truy cập qua cổng AXI HP của PS7 — xem
  `scripts/build_soc_mmu_trial.tcl` header vì sao chưa dùng PS7 ngay trong bản trước).
- **Có khe microSD** — khớp thẳng với yêu cầu bắt buộc của giảng viên (mục D trong
  `Gop_y_De_cuong_KLTN.txt`: chương trình phải nạp từ thẻ SD thật qua SPI, không được
  nạp sẵn vào BlockRAM). Đây là lý do chính nên bắt đầu demo ở board này.
- Không xác nhận được đúng tên board file Vivado qua tìm kiếm — cần cài qua Vivado
  Board Store hoặc theo hướng dẫn trong tài liệu Digilent trước khi tạo project mới.

**VCU129** (bước triển khai cuối — **cần bạn xác nhận lại trước khi đầu tư công sức**):
- Chip: Virtex UltraScale+ **XCVU29P-L2FSGA2577E**, mục tiêu ứng dụng "56G PAM4"
  (backplane 56G, 400GbE...) — đây là board **thuần PL, không có PS/lõi ARM nào** —
  khác hẳn kiến trúc Genesys ZU-5EV.
- RAM: DDR4 DIMM 72-bit (16GB lắp sẵn) + RLD3 288MB — **không có PS**, nên phải dùng
  MIG (Memory Interface Generator) IP của Vivado để điều khiển DDR4, không có đường
  tắt qua PS7 như Genesys ZU-5EV.
- Giao tiếp chính: QSFP56-DD ×2, OSFP, SFP56, QSFP28 ×2 — toàn bộ hướng tới mạng tốc
  độ cao/trung tâm dữ liệu.
- **Chưa xác nhận được có khe SD/microSD hay không** — danh sách tính năng chính thức
  tìm được KHÔNG nhắc tới SD card (khác với board "họ hàng" VCU118, có ghi rõ
  "Micro-SD Card Interface" trong tài liệu). Đây là **rủi ro thật**: nếu VCU129 không
  có khe SD, kịch bản "nạp chương trình từ SD card" bắt buộc của giảng viên (mục D)
  **không thực hiện được trực tiếp trên board này** ở bước cuối — cần bạn tự kiểm tra
  vật lý board hoặc đọc kỹ `UG1318` (link bên dưới) trước khi chốt đây là board triển
  khai cuối cùng.
- Đây là board eval cấp cao, chuyên biệt cho silicon mạng tốc độ cao (thường vài chục
  nghìn USD) — khác hẳn quy mô 1 con CPU RISC-V demo học thuật. Không phải việc tôi tự
  quyết được, nhưng đáng để bạn xác nhận lại đây đúng là board phòng lab có sẵn/dự
  định dùng, không phải nhầm với 1 board VCU khác (VD VCU118 — cũng Virtex
  UltraScale+, nhưng hướng tổng quát hơn, có SD card, ít chuyên biệt về mạng hơn).

**Kịch bản triển khai đề xuất theo 2 bước** (kế hoạch, KHÔNG phải file .xdc — chưa có
đủ thông tin xác minh để viết constraint cụ thể):
1. **Genesys ZU-5EV**: build `quad_core_axi_wrapper.v`/`mmu_ip_wrapper.v` (đã có) qua
   AXI Interconnect + BRAM (như 2 script hiện tại) để xác nhận logic đúng trước, RỒI
   chuyển sang dùng PS7 thật (DDR4 qua AXI HP port) + thêm bộ điều khiển SD/SPI (chưa
   có RTL — xem gap #15 ở mục 5) để thỏa mãn đúng yêu cầu giảng viên. Tận dụng được cả
   PL (RISC-V core tự thiết kế) lẫn khả năng debug qua PS (UART/JTAG có sẵn).
2. **VCU129**: chỉ nên làm SAU khi (1) đã chạy ổn định, VÀ sau khi xác nhận được thẻ
   SD có khả thi trên board này. Cần thêm: MIG IP cho DDR4 (thay cho PS7's DDR), XDC
   pin constraint riêng (khác hoàn toàn Genesys ZU-5EV, phải lấy từ UG1318), và khả
   năng bỏ chính bước "SD → DRAM" nếu board thật sự không có khe SD (thay bằng nạp qua
   JTAG/Vivado Hardware Manager — KHÔNG thỏa mãn yêu cầu giảng viên, cần bạn cân nhắc).

Sources:
- [Genesys ZU: Zynq Ultrascale+ MPSoC Development Board - Digilent](https://digilent.com/shop/genesys-zu-zynq-ultrascale-mpsoc-development-board/)
- [410-383-5EV DIGILENT, XCZU5EV-SFVC784-1-E | Newark](https://www.newark.com/digilent/410-383-5ev/dev-board-64bit-zynq-ultrascale/dp/72AJ8284)
- [Genesys ZU Reference Manual (PDF)](https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/209/Genesys_ZU_Reference_Manual_Web.pdf)
- [EK-U1-VCU129-G, XCVU29P-L2FSGA2577E | Newark](https://www.newark.com/xilinx/ek-u1-vcu129-g/eval-kit-virtex-ultrascale-fpga/dp/92AH1208)
- [VCU129 Evaluation Board User Guide UG1318 (PDF)](https://www.mouser.com/datasheet/2/903/ug1318_vcu129_eval_bd-1634092.pdf)
- [AMD VCU129 product page](https://www.amd.com/en/products/adaptive-socs-and-fpgas/evaluation-boards/vcu129.html)

---

## -0.25. Phiên này: Hướng 2 — `satp` CSR → MMU thật, AHB-Lite → top-level 4 lõi (MỚI)

Bạn yêu cầu làm theo thứ tự **Hướng 2 → Hướng 1 → Hướng 3** (3 hướng do tôi tự đề xuất
ở cuối phiên trước làm "việc còn thiếu tiếp theo"), và từ phiên này trở đi, **mặc định
xuất/cập nhật README sau mỗi lần build hay thay đổi** — không cần bạn nhắc. Đây là
Hướng 2, gồm 2 phần độc lập nhưng cùng chủ đề "nối cái đã viết vào đúng chỗ trong hệ
thống thật":

### -0.25.1. `satp`/`Mmu_Enable` CSR → điều khiển MMU thật

**Vấn đề trước phiên này**: `csr_trap_unit.v` đọc/ghi `satp` đúng (CSRRW hoạt động),
và `mmu_core_wrapper.v` đã expose `Mmu_Enable_Csr`/`Satp_PPN_Csr` ra ngoài — nhưng
**2 tín hiệu đó chưa hề vòng lại vào chính MMU nó thuộc về**. `mmu_top` bên trong vẫn
nhận `mmu_enable`/`satp_ppn` từ 2 port ngoài riêng biệt (`Mmu_Enable`/`Satp_PPN`) —
nghĩa là phần mềm ghi `satp` xong, MMU vẫn dùng giá trị cũ do ai đó nối từ bên ngoài.
Đây chính là việc mục 9, dòng 10 (phiên trước) đã cảnh báo trước.

**Sửa gì, ở đâu, vì sao (đọc theo đúng thứ tự nối dây)**:

1. **`csr_trap_unit.v`** — `Mmu_Enable_Csr` trước đây = thẳng `satp_mode` (bit MODE
   thô). Theo đúng ngữ nghĩa RISC-V thật: **M-mode không bao giờ dịch địa chỉ**, bất
   kể `satp.MODE` là gì (thiết kế này không có `mstatus.MPRV`, nên không có ngoại lệ
   nào cho quy tắc đó) — `satp` chỉ chi phối S-mode/U-mode. Sửa thành
   `Mmu_Enable_Csr = satp_mode & (priv != PRIV_M)`, tính ngay tại nơi sở hữu cả `satp`
   lẫn `priv`, để **mọi nơi dùng tín hiệu này sau này đều tự động đúng**, không phải
   tự suy luận lại quy tắc M-mode-bypass mỗi nơi dùng.
2. **`mmu_core_wrapper.v`** — thêm parameter mới `MMU_CTRL_FROM_CSR` (mặc định `0`):
   - `0` (mặc định): `mmu_top` vẫn nhận `Mmu_Enable`/`Satp_PPN` từ port ngoài **y hệt
     trước phiên này** — đây là lý do `tb_mmu_core.v` và `mmu_ip_wrapper.v` (bản 1
     lõi) **không cần sửa gì cả, vẫn chạy đúng hệt cũ** (cả 2 đều instantiate
     `mmu_core_wrapper` mà không ghi đè parameter này). Test MMU/PTW/TLB tách biệt
     khỏi CSR — vẫn là 1 chiến lược test hợp lệ, không nên phá.
   - `1`: `mmu_top` nhận `Mmu_Enable_Csr`/`Satp_PPN_Csr` (đã tính đúng ở bước 1) thay
     vì port ngoài — `core_l1_wrapper.v` (hệ thật) dùng chế độ này.
   - `Mmu_Flush` (port ngoài) luôn được OR với `Mmu_Flush_Csr` (từ `sfence.vma`), bất
     kể parameter — 1 lần flush TLB thừa chỉ tốn 1 lần nạp lại, không bao giờ sai, nên
     không cần che dưới parameter.
   - **Không có vòng lặp tổ hợp (combinational loop)**: `Mmu_Enable_Csr`/
     `Satp_PPN_Csr`/`Mmu_Flush_Csr` đều là trạng thái CSR **có chốt (registered)**
     thuần trong `csr_trap_unit.v`, không có đường tổ hợp nào từ output của `mmu_top`
     quay ngược lại `csr_trap_unit.v` — đã kiểm tra kỹ trước khi nối (đây là câu hỏi
     thiết kế quan trọng nhất phải trả lời trước khi nối bất kỳ tín hiệu "output quay
     lại làm input" nào).
3. **`core_l1_wrapper.v`** — set `MMU_CTRL_FROM_CSR=1`. Hệ quả: **xoá hẳn 2 port
   ngoài `Mmu_Enable`/`Satp_PPN`** khỏi `core_l1_wrapper.v` (không chỉ để mặc định
   `0`/không dùng — xoá thật). Lý do xoá thay vì để im: phần cứng thật không có chân
   "bật MMU từ bên ngoài" — `satp` là trạng thái nội bộ mỗi hart, chỉ phần mềm chạy
   TRÊN chính hart đó mới ghi được. Để lại 2 port đó (dù không dùng) sẽ tạo ra **2
   nguồn "sự thật" có thể mâu thuẫn nhau** — đúng thứ lỗi mà việc nối dây này phải
   giải quyết, không phải chỉ dời chỗ nó. `Mmu_Flush` port vẫn giữ (lý do OR ở bước 2).
4. **`quad_core_soc.v`** — hệ quả dây chuyền: xoá `Mmu_Enable`/`Satp_PPN0..3` khỏi
   port ngoài + khỏi cả 4 chỗ instantiate `core_l1_wrapper`. Comment cũ "mỗi core có
   `Satp_PPN` riêng vì mỗi OS/hart có 1 bảng trang riêng" **vẫn đúng về mặt ý tưởng**
   — chỉ là giờ mỗi core tự quản lý việc đó qua CSR của chính nó, không cần ai bơm từ
   ngoài vào nữa.
5. **`quad_core_axi_wrapper.v`** — cùng lý do, xoá `Mmu_Enable`/`Satp_PPN0..3` khỏi
   port ngoài cấp cao nhất (nơi trước đây dự định tie-off bằng Constant IP trong
   Vivado) + khỏi chỗ instantiate `quad_core_soc`.
6. **`scripts/build_soc_4core_trial.tcl`** — xoá đoạn tạo 5 khối `xlconstant`
   (`CONST_MMU_ENABLE` + `CONST_SATP_PPN0..3`) tie-off cho 5 port vừa xoá ở bước 5 —
   không xoá sẽ làm script lỗi thật (`connect_bd_net` vào 1 pin không còn tồn tại).
   Giữ nguyên `CONST_MMU_FLUSH`/`CONST_CACHE_FLUSH`. Cập nhật lại 2 đoạn comment/
   `puts` từng nhắc "flip CONST_MMU_ENABLE thành 1" — giờ đúng ra là "chương trình
   boot tự CSRRW satp".

**Phạm vi ảnh hưởng đã kiểm tra kỹ** (chỉ 1 chuỗi gọi thật, không lan rộng hơn):
`quad_core_axi_wrapper.v` là **nơi duy nhất** instantiate `quad_core_soc.v` trong toàn
repo (đã `grep` xác nhận), và `quad_core_soc.v`/`core_l1_wrapper.v` cũng chỉ có đúng
những chỗ gọi đã liệt kê ở trên — không có file nào khác bị ảnh hưởng ngoài 6 file kể
trên.

**Có phải giờ MMU tự nhiên bật lên không?** Không — `satp` reset về `satp_mode=0`
(Bare/bypass) giống hệt hành vi cũ (`CONST_MMU_ENABLE=0`), nên **hành vi mặc định khi
chưa chạy phần mềm nào ghi `satp` là không đổi**. Khác biệt duy nhất: giờ nếu chương
trình chạy trên 1 core tự `CSRRW satp, ...`, việc đó **có tác dụng thật** — trước đây
thì không (bị port ngoài đè lên).

### -0.25.2. `ahb_lite_l1_adapter.v` → top-level 4 lõi

**Vấn đề trước phiên này**: `ahb_lite_l1_adapter.v` (phiên trước) đã đúng là 1 AHB-Lite
master thật (HADDR/HWRITE/HTRANS/HWDATA/HRDATA/HREADY/HRESP đúng pha địa chỉ-rồi-dữ-liệu),
nhưng **chưa có ai đóng vai slave phía bên kia** — không nối được vào đâu cả.

**File mới #1 — `rtl/ahb_lite_l1_slave_adapter.v`**: nửa còn lại của cặp — 1 AHB-Lite
**slave** nhận đúng 8 lần truyền word tuần tự mà `ahb_lite_l1_adapter.v` phát ra, và
nói giao thức `dreq_valid`/`dreq_type`/`dreq_addr`/`dreq_line` ↔
`dresp_valid`/`dresp_line`/`dresp_state` mà `coherence_manager.v` đã hiểu sẵn (dùng lại
được nguyên cho cả cổng I$, chỉ cần bỏ trống `dreq_type`/`dresp_state` vì I$ không có
khái niệm đó). Thiết kế:
- **Đường đọc**: word đầu tiên (word_idx=0) phát `dreq_valid` ngay, giữ `HREADYOUT=0`
  tới khi `dresp_valid` trả về **cả line** — trả word 0 luôn lúc đó; word 1..7 đã có
  sẵn trong buffer nội bộ nên trả ngay, không phải chờ thêm.
- **Đường ghi**: word 0..6 nhận ngay vào buffer (không đụng backend); chỉ word 7 mới
  phát `dreq_valid` (loại WRITEBACK, cả line đã ráp xong) và **giữ transfer thứ 8 đó**
  tới khi `dresp_valid` xác nhận thật — cố ý **không** làm "posted write" (báo xong
  ngay rồi ack ngầm sau), vì vậy sẽ tạo ra 1 race thật: L1 tưởng writeback đã xong
  trong khi L2 chưa nhận được.
- **Giới hạn có chủ đích, cần biết trước khi coi đây là "miễn phí"**: `dresp_state`
  (trạng thái MESI thật được cấp — S/E/M) **không có chỗ biểu diễn chuẩn trong
  AHB-Lite** (`HRESP` chỉ có OKAY/ERROR) — `ahb_lite_l1_adapter.v` (phía master) vứt
  bỏ nó, luôn báo về `l1_dcache.v` là "S" bất kể thật sự cấp gì. **An toàn** (S luôn là
  ước lượng dưới đúng, ghi cục bộ đầu tiên sẽ tự phát hiện "chưa phải M/E" và xin RFO
  đúng cách) nhưng **không miễn phí**: 1 line lẽ ra được cấp Exclusive giờ tốn thêm 1
  vòng bus (RFO) ở lần ghi cục bộ đầu tiên, thay vì được nâng cấp E→M âm thầm ngay tại
  chỗ như khi nối dây trực tiếp (`quad_core_soc.v`, không qua AHB-Lite).

**File mới #2 — `rtl/quad_core_soc_ahb.v`**: **biến thể top-level mới**, song song với
`quad_core_soc.v` (không sửa `quad_core_soc.v`) — cùng 4× `core_l1_wrapper` +
1× `coherence_manager`, nhưng cổng I$/D$ line-fill/writeback của mỗi core giờ đi qua 1
cặp adapter (master + slave) thay vì nối dây trực tiếp. Vì sao file mới thay vì sửa
`quad_core_soc.v`: sửa trực tiếp sẽ làm tăng diện tích chưa-được-verify trên 1 file đã
qua nhiều vòng review + có testbench riêng (`tb_coherence.v`) — tách file giữ
`quad_core_soc.v` nguyên vẹn, hoạt động y hệt trước, trong khi biến thể AHB-Lite được
review độc lập.

**Quyết định thiết kế quan trọng nhất — vì sao 8 liên kết điểm-nối-điểm, không phải 1
bus AHB-Lite dùng chung nhiều master**: 1 bus AHB-Lite thật với >1 master cần trọng tài
pha-địa-chỉ riêng của chính nó (đúng thứ `ahb3lite_interconnect-master_reference/` hiện
thực — và chính là lý do phiên trước không gắn trực tiếp: sai giấy phép, thiếu
submodule, topology multi-layer thừa phức tạp). Xây thêm 1 trọng tài AHB-Lite ở đây sẽ
**thừa hoàn toàn**: `coherence_manager.v` đã có sẵn trọng tài 8-nguồn ưu-tiên-cố-định
riêng (xem mục 2.2), ngay phía bên kia của 8 slave adapter. Mỗi core có 1 liên kết
AHB-Lite riêng cho I$ và 1 riêng cho D$ — không tranh chấp lẫn nhau, không cần trọng tài
thêm.

**Đường snoop KHÔNG đi qua AHB-Lite**: `dsnoop_valid`/`dsnoop_type`/`dsnoop_addr` +
`dsnoop_ack_*` vẫn nối thẳng `core_l1_wrapper` ↔ `coherence_manager`, y hệt
`quad_core_soc.v`. Lý do: AHB-Lite (bản Lite, không phải ACE) không có cơ chế chuẩn nào
cho "slave chủ động xin master làm gì đó" (snoop/invalidate) — cần mở rộng ACE hoặc bus
sideband riêng, vượt phạm vi AHB-Lite thật. Đưa đường snoop qua 1 giao thức không biểu
diễn được nó sẽ không làm thiết kế đúng hơn, chỉ phức tạp hơn.

**Đã tự kiểm tra (chưa mô phỏng được, xem cảnh báo ở mục 9)**:
- Đối chiếu port tự động (script PowerShell) cho **toàn bộ 17 chỗ instantiate mới**
  trong `quad_core_soc_ahb.v` (1× `coherence_manager` + 16× adapter) — khớp chính xác
  100%, 0 thiếu/0 dư.
- Đối chiếu lại port ở **mọi** chỗ gọi `mmu_core_wrapper`/`core_l1_wrapper`/
  `quad_core_soc` bị ảnh hưởng gián tiếp bởi việc xoá port ở -0.25.1 (`mmu_ip_wrapper`,
  `tb_mmu_core`, cả 4 core trong `quad_core_soc.v` VÀ `quad_core_soc_ahb.v`,
  `quad_core_axi_wrapper`) — xác nhận **không có chỗ nào bị lệch port** sau khi xoá.
- Cân bằng `begin`/`end` (sau khi bỏ comment) cho mọi file mới/sửa trong mục này —
  khớp chính xác ở từng file.
- Trace tay xác nhận không có multi-driver: mỗi dây AHB-Lite điểm-nối-điểm trong
  `quad_core_soc_ahb.v` chỉ có đúng 1 driver (ví dụ `i_hready[n]` chỉ được lái bởi
  `HREADYOUT` của slave adapter, đọc bởi `HREADY` của master adapter — không có chiều
  ngược lại).

**Việc còn thiếu, chưa làm trong mục này**: `quad_core_soc_ahb.v` **chưa có testbench
riêng nào** — `tb_coherence.v` (đã viết, chưa chạy) chỉ test `coherence_manager.v` +
`l1_dcache.v` + `l2_cache.v` trực tiếp, không đi qua cặp adapter AHB-Lite mới này. Nếu
cần bằng chứng adapter hoạt động đúng (không chỉ "tên tín hiệu đúng"), cần viết thêm 1
testbench nhắm riêng vào `ahb_lite_l1_adapter.v`+`ahb_lite_l1_slave_adapter.v` (hoặc mở
rộng `tb_coherence.v` để lái qua đường AHB-Lite thay vì trực tiếp) — chưa nằm trong
phạm vi Hướng 2, có thể cân nhắc thêm vào Hướng 1 hoặc để riêng.

---

## -0.1. Phiên này: Hướng 1 — mở rộng testbench CSR/trap (M/S/U thật, `medeleg`, MMU page-fault-trap)

Tiếp theo mục -0.25 (Hướng 2), đây là Hướng 1: mở rộng phần kiểm thử CSR/Trap/Privilege
để phủ 3 việc `tb_csr_trap.v` (phiên trước) tự nhận là chưa làm — chuyển đổi M/S/U
**thật** (test cũ ở nguyên M-mode xuyên suốt), delegation qua `medeleg`, và 1 kịch bản
MMU-page-fault-thật-sự-trap.

### -0.1.1. Bug thật phát hiện được TRƯỚC KHI viết testbench mới: `tb_mmu_core.v` đã lỗi thời

Trước khi viết gì mới, việc đầu tiên là suy nghĩ xem "MMU page fault thật sự trap" nghĩa
là gì với testbench MMU đã có sẵn (`tb_mmu_core.v`) — và phát hiện ra nó **đã âm thầm
sai** kể từ phiên xây CSR/Trap (mục -0.5), dù chưa ai chạy lại nó để thấy:

- `tb_mmu_core.v` được viết TRƯỚC KHI `csr_trap_unit.v` tồn tại — lúc đó một page fault
  chỉ ép NOP/chặn store, không có gì để "trap" vào cả.
- Phiên -0.5 sau đó nối `mmu_core_wrapper.v`'s `fetch_fault`/`mem_fault` thẳng vào
  `Fetch_PageFault_In`/`Data_PageFault_In` của core bên trong — nghĩa là 1 page fault
  bây giờ **thật sự nhảy tới `mtvec`**.
- Nhưng `tb_mmu_core.v` **chưa từng set `mtvec`** — giá trị reset là 0. Lần fault đầu
  tiên (RO store tại VA 0x4000) sẽ nhảy PC về địa chỉ 0, nơi chứa **dữ liệu bảng trang**
  (`0x0000_1001`), không phải lệnh hợp lệ — dẫn tới illegal-instruction-trap-loop tại PC
  0 mãi mãi (mtvec vẫn là 0), treo tới khi hết ngân sách chu kỳ và FAIL.
- Đây là hệ quả tất yếu của việc nối 2 phần (CSR/trap + MMU) đã được xây RIÊNG BIỆT,
  đúng kiểu vấn đề Hướng 1 được giao để đi tìm — tìm bằng cách suy luận cẩn thận, không
  phải chạy simulator (vẫn không có trong môi trường này).

**Đã sửa `tb_mmu_core.v`** (ngoại lệ hợp lý với "không sửa file cũ" — file này thật sự
sai với RTL hiện tại, để nguyên sẽ đánh lừa bạn khi chạy lại): thêm 3 lệnh đầu chương
trình set `mtvec = VA 0x1100`, thêm 1 handler chung 4 lệnh tại VA 0x1100 (cùng dạng với
handler của `tb_csr_trap.v`), đặt bên trong CHÍNH trang đã map R+X sẵn (VA 0x1000-0x1FFF)
để việc fetch handler không tự gây fault. Toàn bộ địa chỉ chương trình gốc dịch +0xC để
nhường chỗ. Thêm 1 check mới: `x11 = mcause` đọc lại sau lần trap gần nhất (kỳ vọng 13,
not-present load) — chứng minh trạng thái CSR sau trap thật là đúng, không chỉ "có nhảy
PC là được". Các check cũ (x1-x10, "PA 0x4000 không đổi", số lần page-fault pulse) đều
giữ nguyên kỳ vọng — trace tay xác nhận cả 2 lần fault (RO store, not-present load) vẫn
bị chặn/trả 0 đúng như trước, CHỈ THÊM việc chúng giờ cũng thật sự trap-và-resume đúng
chỗ.

### -0.1.2. File mới: `sim/tb_csr_priv.v` — M/S/U thật + `medeleg`

DUT giống `tb_csr_trap.v` (RV32IMA thô, không qua MMU — lý do y hệt: cô lập việc kiểm
thử privilege/delegation khỏi việc PTW cũng đang chạy). Kịch bản đầy đủ, dùng đúng cách
thật của RISC-V để đổi quyền (không có lệnh "hạ quyền" nào khác ngoài qua trap/return):

```
M (reset) --MRET(mstatus.MPP=S)--> S --SRET(sstatus.SPP=U)--> U
  --ECALL, medeleg[8]=1--> S (delegated: dùng scause/sepc/stvec, KHÔNG dùng mcause/mepc/mtvec)
  --SRET--> U
  --EBREAK, medeleg[3]=0--> M (KHÔNG delegate, dù đang ở U -- chứng minh delegation chọn
    lọc theo từng cause, không phải "cứ không phải M thì về S")
  --MRET--> U (cuối cùng; self-loop dừng ở đây)
```

Đây là con đường "giáo khoa" thật của RISC-V: chỉ M-mode mới ghi được `mstatus.MPP`
(S-mode không thấy field này qua `sstatus`, đã xác nhận bằng cách đọc đúng mask
`sstatus_r`), nên M→S phải qua MRET; S→U phải qua SRET với `sstatus.SPP`, không có
đường tắt nào khác.

**2 bug thật tự bắt được khi hand-trace trước khi tin dùng chương trình** (giống tinh
thần bug #4 ở Phase 7b, mục 7 — luôn trace tay từng lệnh CSR/immediate trước khi coi là
đúng):
- `ADDI x28, x0, 0x800` (định dùng để dựng bit MPP=S tại bit 11) **sai** — immediate
  12-bit của ADDI được sign-extend, và 0x800 tự nó có bit 11 (bit dấu của trường 12-bit)
  = 1, nên lệnh này thực ra nạp `x28 = 0xFFFFF800`, không phải `0x00000800`. Ghi thẳng
  giá trị đó vào `mstatus` sẽ khiến MPP đọc thành "11" (M) thay vì "01" (S) — MRET đầu
  tiên sẽ quay lại M thay vì hạ xuống S, làm hỏng toàn bộ kịch bản ngay bước đầu. Sửa
  bằng `ADDI x28,x0,1` (an toàn, nhỏ, dương) rồi `SLLI x28,x28,11` (dịch bit trên giá trị
  thanh ghi thật, không đi qua đường sign-extend của immediate).
- Marker cuối `ADDI x8,x0,0x999` có đúng lỗi y hệt (0x999 cũng có bit 11 = 1) — đổi
  thành `0x666` (an toàn, < 0x800).
- Địa chỉ CSR (`mtvec`=0x305, `medeleg`=0x302, `mstatus`=0x300, `mepc`=0x341,
  `stvec`=0x105, `sepc`=0x141, `scause`=0x142, `sstatus`=0x100, `mcause`=0x342) không bị
  ảnh hưởng bởi lỗi này — chúng nằm ở `instr[31:20]`, đọc ra trực tiếp không qua đường
  sign-extend, bất kể bit nào của địa chỉ được bật.

**2 cách kiểm chứng độc lập nhau trong cùng 1 testbench** (không chỉ tin vào 1 loại
bằng chứng):
1. Thanh ghi marker (x1-x8) chứng minh CÓ code chạy ở đúng từng giai đoạn, VÀ (với x5,
   x7 — đọc `scause`/`mcause`, đều là CSR bị giới hạn quyền tối thiểu S/M) việc đọc
   thành công tự nó là bằng chứng gián tiếp priv lúc đó đúng thật là S/M — nếu sai,
   `csr_access_bad` sẽ biến việc đọc đó thành illegal-instruction, và toàn bộ phần còn
   lại của chương trình sẽ không bao giờ chạy tới các marker sau.
2. Bộ đếm lịch sử `CurrentPriv` (`priv_history[]`, bắt cạnh mỗi lần đổi giá trị thật) —
   kiểm tra trực tiếp đúng 6 lần chuyển đổi, đúng thứ tự S,U,S,U,M,U — độc lập hoàn
   toàn với các thanh ghi marker.

**Chưa mô phỏng** (như mọi file khác trong repo) — chỉ đã tự kiểm tra tĩnh (đối chiếu
100% port với `RV32IMA.v`, cân bằng begin/end) + trace tay từng lệnh + xác minh từng mã
lệnh hex bằng 1 assembler/decoder nháp riêng (ngoài repo, chỉ để tự kiểm, không phải
bằng chứng RTL đúng).

---

## -0.05. Phiên này: Hướng 3 — Bootloader SD card, kịch bản đánh giá tự động, file `.xdc`

### -0.05.1. Phát hiện quan trọng làm đổi hẳn kiến trúc: SD card trên Genesys ZU-5EV nối qua PS, KHÔNG nối qua PL

Trước khi viết bất kỳ RTL/script nào, tôi tra cứu (qua web, không đoán) xem khe microSD
trên Genesys ZU-5EV nối vào đâu — vì kế hoạch ban đầu (dùng IP `axi_quad_spi` phía PL để
tự bit-bang giao thức SD qua SPI, giống hướng đi đã định trước đó) **chỉ khả thi nếu SD
card nối tới chân PL**. Kết quả: **không khả thi** — bằng chứng trực tiếp từ chính quy
trình boot Digilent công bố cho board này: SD card boot dùng `zynqmp_fsbl.elf` (First
Stage Boot Loader, chạy trên lõi ARM của PS) đóng gói cùng bitstream + `u-boot.elf` thành
`BOOT.BIN`, được **boot ROM cứng của PS** đọc trực tiếp từ SD — đây là cơ chế SD-boot
chuẩn, cố định trong silicon của toàn bộ họ Zynq/Zynq UltraScale+, chỉ hoạt động khi SD
card nối vào đúng chân MIO của PS. Không có đường điện nào từ PL tới chân SD card trên
board này — dù RTL/phần mềm phía RISC-V (PL) viết đúng cỡ nào, nó cũng không thể tự đọc
được SD card.

**Kiến trúc đúng, khả thi, ít rủi ro hơn hẳn kế hoạch ban đầu**:
```
PS boot từ SD (đã hoạt động sẵn, không cần làm gì thêm) ->
  1 loader nhỏ phía PS đọc chương trình RISC-V từ hệ thống file FAT32 trên SD card,
  ghi vào DRAM dùng chung ->
  PS ghi bit GO qua boot_ctrl.v (mục -0.05.2) ->
  Các lõi RISC-V (đang bị giữ reset từ trước) bắt đầu fetch chương trình vừa nạp.
```
So với kế hoạch ban đầu (tự viết + tự hand-assemble 1 bootloader SPI hoàn chỉnh bằng
RISC-V assembly, không có simulator để xác minh vòng lặp retry/timing của giao thức SD
thật) — kiến trúc này **rủi ro thấp hơn nhiều**: phần khó nhất (giao thức SD, hệ thống
file FAT32) do chính firmware/driver đã được Xilinx kiểm chứng kỹ (FSBL, `xilffs`) đảm
nhận, không phải RTL/assembly tự viết trong repo này.

Sources:
- [Genesys ZU getting started / SD boot flow (FSBL, BOOT.BIN) — Digilent Forum threads](https://forum.digilent.com/topic/20053-problem-with-sd-card-boot-on-genesys-zu/)
- [Genesys ZU Reference Manual - Digilent Reference](https://digilent.com/reference/programmable-logic/genesys-zu/reference-manual)

### -0.05.2. File mới: `rtl/boot_ctrl.v` — chốt chặn reset chờ PS nạp xong

Khối AXI4-Lite slave rất nhỏ, cố ý đơn giản tối đa (đúng kiểu "đúng chỉ bằng cách đọc
lại" mà phiên này ưu tiên khi không có simulator) — 3 thanh ghi:
- `REG_CTRL` (offset 0x0): bit0 = **GO**, ghi-1-là-set, **sticky** (ghi 0 sau đó KHÔNG
  tắt lại được — one-shot có chủ đích, giống hệt lý do thật: một khi RISC-V đã chạy,
  không có khái niệm "ghi phần mềm để nó tự reset lại" qua đường này).
- `REG_STATUS` (offset 0x4): đọc lại đúng giá trị GO, tiện PS polling/debug.
- `REG_RESULT` (offset 0x8): **RISC-V ghi mã PASS/FAIL vào đây, PS đọc lại** — xem mục
  -0.05.3 vì sao đi qua đây thay vì UART thật.

`core_go` (output) dùng để AND với `ARESETN` hệ thống tại `quad_core_axi_wrapper_bootable.v`
(file mới, bọc `quad_core_axi_wrapper.v` gốc — không sửa file cũ) — giữ TOÀN BỘ 4 lõi +
MMU + L1/L2/coherence (tất cả treo trên cùng 1 cây reset) ở trạng thái reset cho tới khi
PS xác nhận đã nạp xong chương trình vào DRAM dùng chung, tránh race "RISC-V fetch trước
khi PS ghi xong".

### -0.05.3. Vì sao PASS/FAIL đi qua `boot_ctrl` thay vì UART PL thật

Kế hoạch ban đầu: thêm 1 `axi_uartlite` (IP có sẵn của Vivado) ở phía PL, chương trình
RISC-V ghi chuỗi "PASS"/"FAIL" ra đó, host đọc qua cổng COM. Nhưng suy nghĩ kỹ lại: cổng
USB-UART DUY NHẤT có sẵn trên board gần như chắc chắn cũng nối vào UART cứng của PS (y
hệt lý do SD card không nối PL ở mục -0.05.1) — nghĩa là 1 `axi_uartlite` tự thêm ở PL
**không chắc có đường vật lý nào ra ngoài để host đọc được**. Thay vì đầu tư hand-assemble
+ verify 1 con đường có khả năng vô dụng trên phần cứng thật, tôi sửa lại: `boot_ctrl.v`
đóng thêm vai trò "hộp thư kết quả" — RISC-V ghi `REG_RESULT` qua đúng đường AXI đã có sẵn
(cùng interconnect với `boot_ctrl`'s GO), PS đọc lại và tự in "PASS"/"FAIL" ra **console
UART của chính PS** (chắc chắn hoạt động — đó là console bạn đã dùng để xem log FSBL/
u-boot). `axi_uartlite` vẫn được nối trong `build_soc_zu5ev_boot.tcl` như 1 ngoại vi phụ/
debug — dùng nó cho output thật CHỈ SAU KHI bạn tự xác nhận board có đầu nối UART nào đó
thật sự tới được PL.

### -0.05.4. File mới: `scripts/build_soc_zu5ev_boot.tcl`

Script thứ 3 (không sửa 2 script cũ), dựng: `ps0` (Zynq UltraScale+ PS, `zynq_ultra_ps_e`,
cấu hình qua `apply_bd_automation` dùng board preset — KHÔNG tự tay set hàng chục property
DDR/MIO, để tránh đúng kiểu "bịa dữ kiện phần cứng" đã cấm xuyên suốt dự án; xem
-0.05.1) + `cpu0` (`quad_core_axi_wrapper_bootable`, mới) + `dma0` (`axi_cdma`) + 1
`axi_interconnect_data` dùng chung (3 master: cpu0/dma0/ps0's GP master; 4 slave:
mem_ctrl, `uart0` (`axi_uartlite`, phụ/debug), dma0's control port, `boot_ctrl`'s
`S_AXI_BOOT`). `boot_ctrl` cố ý reachable từ CẢ 2 phía (cpu0 ghi RESULT, ps0 ghi GO/đọc
RESULT).

**Ghi chú trung thực quan trọng** (đọc trước khi coi chạy sạch = đúng hoàn toàn): các lệnh
`apply_bd_automation` cho Zynq PS (tên rule, tên port GP master `M_AXI_HPM0_FPD`/
`M_AXI_HPM0_LPD`) có thể lệch giữa các bản Vivado, và phiên này không có Vivado để chạy
thử. Mọi lệnh liên quan PS đều bọc `catch` + in rõ hướng dẫn sửa tay trong GUI nếu lệch —
đúng quy ước "WARNING không abort" đã dùng ở 2 script trước, chỉ áp dụng cho phần có nhiều
biến thiên hơn (PS bring-up) so với IP ngoại vi thường. **Phần clock/reset cố ý KHÔNG tự
động hoá** (đoán sai cú pháp ở đây có nguy cơ nối sai trong im lặng, tệ hơn là báo lỗi rõ
ràng) — script in hướng dẫn rõ ràng để bạn tự làm qua GUI's Run Connection Automation.

**Chưa làm trong script này**: `mem_ctrl` vẫn là BRAM (như 2 script trước), CHƯA phải DRAM
thật qua cổng HP của PS — script này chỉ chứng minh phần dây nối elaborate được, CHƯA
chứng minh luồng SD→DRAM→release-from-reset chạy đúng trên phần cứng thật với DRAM thật.
Việc thay `mem_ctrl` bằng đường HP-port-tới-DDR thật là bước tiếp theo, sau khi xác nhận
phần này elaborate sạch trong Vivado thật.

### -0.05.5. Phần mềm phía PS (loader) — mô tả, KHÔNG hand-assemble

Chạy trên lõi ARM Cortex-A53 của PS, toolchain hoàn toàn khác RISC-V (Vitis/PetaLinux,
biên dịch C thật) — **ngoài phạm vi hand-assemble hex của repo này** (khác hẳn mọi
testbench RISC-V khác trong dự án). Quy trình (thủ tục, không phải code thật):
1. Dùng thư viện `xilffs` (FAT filesystem driver có sẵn của Xilinx, đã kiểm chứng) mở
   file chương trình RISC-V (vd `riscv_app.bin`) trên phân vùng FAT32 của SD card.
2. Đọc toàn bộ file, ghi vào vùng DRAM dùng chung (địa chỉ khớp với vùng `mem_ctrl`/DRAM
   mà 4 lõi RISC-V trỏ tới sau khi dịch qua MMU/`RESET_ADDR`).
3. Ghi `boot_ctrl`'s `REG_CTRL` bit0 = 1 (địa chỉ lấy từ Address Editor sau khi chạy
   `build_soc_zu5ev_boot.tcl`, xem ghi chú cuối script).
4. Polling `boot_ctrl`'s `REG_RESULT` (hoặc chờ 1 khoảng thời gian cố định) tới khi khác
   0, rồi `printf` "PASS"/"FAIL" tương ứng ra console PS — đây chính là dòng
   `scripts/host_eval_uart.py` (mục -0.05.6) sẽ đọc được.

### -0.05.6. File mới: `scripts/host_eval_uart.py` — đánh giá tự động, không xem waveform

Script Python (dùng `pyserial`, thư viện chuẩn phổ biến) mở cổng COM của board, đọc từng
dòng, thoát với mã 0 nếu thấy "PASS", mã 1 nếu thấy "FAIL", mã 2 nếu hết thời gian chờ mà
chưa thấy gì, mã 3 nếu không mở được cổng — đúng kiểu exit-code CI/script hoá được, không
cần người ngồi xem terminal/waveform. Mặc định trỏ vào console UART của PS (mục -0.05.3);
`--port`/`--baud`/`--timeout` đều chỉnh được qua tham số dòng lệnh.

### -0.05.7. File `.xdc` — KHÔNG bịa số chân

Thư mục mới `constraints/` với 2 file **template**, không phải file constraint hoàn
chỉnh: `genesys_zu5ev_boot_template.xdc` và `vcu129_template.xdc`. Lý do không điền số
chân thật: mọi lần thử trích xuất trang schematic/reference-manual PDF thật của cả 2
board trong phiên này đều thất bại (PDF nén theo cách công cụ đọc hiện có không giải mã
được, và không có Vivado để đối chiếu ngược qua board file) — **bịa số chân, đặc biệt
IOSTANDARD/điện áp, có thể làm hỏng board thật**, không chỉ đơn giản là sai logic. Mỗi
file ghi rõ: (a) vì sao ngắn/dài khác nhau (ZU-5EV dùng PS + board-preset automation nên
hầu như không cần XDC tay cho DDR/MIO; VCU129 thuần PL nên cần XDC tay cho mọi thứ), (b)
chính xác nguồn nào cần tra để điền đúng (link reference manual/schematic Digilent, UG1318
của AMD), (c) với riêng VCU129: nhắc lại rõ ràng câu hỏi kiến trúc còn treo ở mục -0.05.8.

### -0.05.8. VCU129: câu hỏi kiến trúc còn treo — KHÔNG đầu tư RTL khi chưa xác nhận

VCU129 là board PL thuần, **không có PS** (đã xác nhận phiên trước) — nghĩa là kiến trúc
"PS-mediated boot" ở mục -0.05.1 **không áp dụng được cho VCU129 dù nó có đúng với
Genesys ZU-5EV**. Nếu VCU129 cần hỗ trợ SD-boot theo đúng yêu cầu giảng viên, đường duy
nhất còn lại là 1 bootloader SD-qua-SPI thật thi hành hoàn toàn trong PL (IP
`axi_quad_spi` + 1 chương trình RISC-V tự bit-bang giao thức SD chuẩn: CMD0 → CMD8 →
vòng lặp ACMD41 → CMD16 → CMD17 từng block). Đây CHÍNH LÀ kế hoạch ban đầu của tôi trước
khi phát hiện ra nó không áp dụng được cho ZU-5EV — thuật toán vẫn đúng và có thể dùng lại
cho VCU129, NHƯNG:
1. **Chưa xác nhận VCU129 có khe SD/microSD nào không** — danh sách tính năng chính thức
   không nhắc tới (đã ghi ở mục -0.5.5 phiên trước).
2. **Chưa xác nhận (nếu có) SD card có nối tới chân PL nào không** — câu hỏi giống hệt
   mục -0.05.1 nhưng cho board này.
3. Một bootloader SD-SPI thật, hand-assemble bằng RISC-V (không có toolchain/simulator
   thật để verify) có rủi ro bug thật sự cao — đúng bài học ở mục -0.1 (2 bug sign-extend
   bắt được khi hand-trace `tb_csr_priv.v`, một chương trình ĐƠN GIẢN HƠN NHIỀU so với 1
   bootloader SD-SPI thật với vòng lặp retry/polling).

**Quyết định phiên này**: KHÔNG đầu tư viết RTL/hand-assemble bootloader SD-SPI cho VCU129
khi (1)/(2) chưa được xác nhận — tránh lặp lại đúng rủi ro "đầu tư công sức vào thứ có thể
không dùng được trên phần cứng thật" mà mục -0.5.5 phiên trước đã cảnh báo. Thuật toán
giao thức SD-SPI (CMD0/CMD8/ACMD41/CMD16/CMD17, hoàn toàn chuẩn, ổn định, đã hiểu rõ) sẵn
sàng hiện thực ngay khi bạn xác nhận được (1) và (2) — chỉ cần yêu cầu lại, không cần
nghiên cứu lại từ đầu.

---

## -0.02. Phiên này: chốt 5 quyết định kiến trúc còn treo + sửa LR/SC VA-vs-PA

Bạn đã chốt: **bus core↔system là AHB-Lite**, **MESI đầy đủ** (đã chọn từ trước, nay xác
nhận lại), **MMU nằm trong phạm vi báo cáo chính thức**, **L2 = 512KB**, **L1 = 32KB D$ +
32KB I$ tách riêng**. Mục 4 (các quyết định còn treo) cập nhật lại theo đây — không còn
"còn treo" cho 5 điểm này nữa.

### -0.02.1. Resize L1/L2 — chỉ đổi 1 tham số mỗi file, không có hardcode ẩn

Đọc kỹ cả 3 file trước khi sửa (đúng tinh thần "cẩn thận, tỉ mỉ") để chắc chắn không có
giá trị hardcode nào ăn theo kích thước cũ ngoài đúng 1 tham số `INDEX_BITS`:
- `l2_cache.v`: `TAG_BITS`/`SETS`/`addr_tag`/`addr_index` đều là `localparam` tính TỪ
  `INDEX_BITS` — không có gì hardcode khác. 256KB→512KB: `INDEX_BITS` 11→12 (4096 sets).
- `l1_icache.v`/`l1_dcache.v`: `WAYS=2` là `localparam` cố định (đã ghi rõ từ trước:
  "hardcoded to WAYS=2... not a drop-in 'set WAYS=4' parametrization") — nhưng tôi
  KHÔNG đổi `WAYS`, chỉ đổi `INDEX_BITS`, nên giới hạn đó không áp dụng ở đây. 16KB→32KB
  (2-way, line 32B): `INDEX_BITS` 8→9 (512 sets).
- Đã kiểm tra: không có testbench nào (`tb_coherence.v`, `tb_mmu_core.v`, `tb_csr_*.v`)
  hardcode địa chỉ dựa theo index-width cũ, và không có chỗ nào instantiate 3 module này
  kèm tham số ghi đè — mọi nơi đều dùng default, nên chỉ cần đổi default là đủ, không
  phải sửa dây ở bất kỳ file nào khác.

### -0.02.2. AHB-Lite trở thành bus chính thức — cần thêm 1 lớp AXI wrapper mới

`quad_core_soc_ahb.v` (mục -0.25.2, phiên trước) đã có, nhưng **chưa có** bản bọc AXI4 +
bản bootable tương ứng — `quad_core_axi_wrapper.v`/`quad_core_axi_wrapper_bootable.v` cũ
chỉ bọc `quad_core_soc.v` (bản dây nối trực tiếp), không phải bản AHB-Lite. File mới
(port-for-port giống hệt bản gốc, chỉ đổi module con được instantiate — đã đối chiếu port
100% cho cả 2):
- `rtl/quad_core_axi_wrapper_ahb.v` — bọc `quad_core_soc_ahb.v`.
- `rtl/quad_core_axi_wrapper_ahb_bootable.v` — bọc thêm `boot_ctrl.v` (dùng cho Genesys
  ZU-5EV).

**Đã cập nhật để dùng đúng bản AHB-Lite làm mặc định** (không còn là "1 trong 2 lựa
chọn" — giờ là lựa chọn chính thức):
- `scripts/build_soc_zu5ev_boot.tcl`: `cpu0` giờ instantiate
  `quad_core_axi_wrapper_ahb_bootable` thay vì `quad_core_axi_wrapper_bootable`.
- `scripts/build_soc_4core_trial.tcl`: `cpu0` giờ instantiate `quad_core_axi_wrapper_ahb`
  thay vì `quad_core_axi_wrapper`.
- Cả 2 script vẫn ĐĂNG KÝ (nhưng không dùng) source của bản dây nối trực tiếp
  (`quad_core_soc.v`/`quad_core_axi_wrapper.v`/...) — giữ lại làm tham khảo/dự phòng
  trong cùng project, không xoá.

### -0.02.3. File mới: `sim/tb_coherence_ahb.v` — đóng lỗ hổng "AHB-Lite chưa có test riêng"

Đây chính là mục còn thiếu quan trọng nhất trong danh sách "chưa hoàn thiện triệt để" mà
tôi tự liệt kê trước đó, và giờ CÀNG quan trọng hơn vì AHB-Lite đã là bus chính thức. Thay
vì viết 1 kịch bản test từ đầu (rủi ro cao hơn), tôi **dùng lại nguyên vẹn** kịch bản
MESI 5 bước (A-E) đã có sẵn trong `tb_coherence.v` — copy y hệt cách sequencing/assertion,
CHỈ đổi đúng 1 điều: đường nối `l1_dcache` ↔ `coherence_manager` giờ đi qua 1 cặp
`ahb_lite_l1_adapter` + `ahb_lite_l1_slave_adapter` (đúng như `quad_core_soc_ahb.v` đã
làm cho D$), thay vì nối dây trực tiếp. PASS ở đây là bằng chứng trực tiếp cầu AHB-Lite
trong suốt với giao thức — nếu FAIL đúng ở bước mà `tb_coherence.v` (bản gốc) từng PASS,
lỗi chắc chắn nằm ở 2 file adapter, không phải ở MESI logic (đã review riêng, không đổi
gì ở `coherence_manager.v`/`l1_dcache.v` trong file test mới này).

**Khác biệt kỳ vọng so với `tb_coherence.v` (không phải bug)**: mọi giao dịch giờ chậm
hơn hẳn (8 lần truyền word tuần tự qua AHB-Lite mỗi lần fill/writeback, thay vì gần như
1-chu-kỳ/word của giao thức tự đặt cũ) — ngân sách chu kỳ timeout đã tăng lên tương ứng
(40000 thay vì 20000 chu kỳ clock).

**Đã tự kiểm tra tĩnh**: đối chiếu port 100% cho cả 4 loại module instantiate
(`l1_dcache`, `ahb_lite_l1_adapter`, `ahb_lite_l1_slave_adapter`, `coherence_manager`),
cân bằng begin/end/task/endtask. **Chưa chạy qua Vivado** (như mọi testbench khác trong
repo).

### -0.02.4. Sửa LR/SC VA-vs-PA — bug thật đã biết từ nhiều phiên trước, giờ mới sửa

**Bug chính xác**: `memory_stage.v` (sống hoàn toàn bên trong `RV32IMA.v`, tức miền địa
chỉ ẢO, trước MMU) lưu `reservation_addr <= ALU_ResultM` (địa chỉ ảo) rồi so khớp với
`Snoop_Addr` (luôn là địa chỉ VẬT LÝ, đến từ `coherence_manager.v`, sau MMU) — 2 địa chỉ
khác miền, chỉ tình cờ đúng nếu VA→PA của core đó là ánh xạ đồng nhất (identity mapping).

**Cách sửa**: thêm 1 cổng mới `Mem_PhysAddrM` (32-bit) xuyên suốt
`memory_stage.v` → `RV32IMA.v` → nơi gọi. `memory_stage.v` giờ lưu/so khớp reservation
bằng `Mem_PhysAddrM` (vật lý) thay vì `ALU_ResultM` (ảo) — cùng miền với `Snoop_Addr`
ngay từ đầu, không cần sửa gì phía snoop.

**Ai cấp giá trị thật cho `Mem_PhysAddrM`**:
- `mmu_core_wrapper.v` (nơi CÓ MMU thật): nối `pa_mem` — địa chỉ vật lý mmu_core_wrapper
  đã tự tính sẵn mỗi chu kỳ cho đúng `mem_addr_va` hiện tại. Đã trace tay xác nhận đúng
  thời điểm: mỗi khi lõi KHÔNG bị đóng băng (`mmu_busy=0`), `pa_mem` luôn phản ánh đúng
  bản dịch mới nhất của `mem_addr_va` — đúng lúc 1 lệnh LR/SC ở M-stage thật sự "chốt".
  Đây là chỗ sửa THẬT DUY NHẤT — mọi nơi khác chỉ cần nối vòng để không phá vỡ hành vi cũ.
- 5 chỗ CÒN LẠI gọi `RV32IMA` trực tiếp (không qua MMU, VA=PA đồng nhất theo thiết kế):
  `tb_csr_trap.v`, `tb_csr_priv.v`, `legacy_2core/RV32_IP_Wrapper.v`,
  `legacy_2core/RV32IMA_DualCore_Wrapper.v` (core0 VÀ core1) — tất cả nối vòng
  `Mem_PhysAddrM` = `Mem_AddrM` (output của chính core đó) — vì không có MMU nên VA=PA
  luôn đúng 100%, nối vòng này giữ nguyên hành vi cũ tuyệt đối, không đổi gì cả.
- 2 file `legacy_2core/*` là ngoại lệ đã có tiền lệ (đã từng sửa 1 lần để tie-off
  `Fetch_PageFault_In`/`Data_PageFault_In`) — đây là lần sửa bắt buộc thứ 2 với cùng lý
  do: Verilog không cho phép bỏ trống 1 port mới thêm vào module con, để trống sẽ float
  (X trong mô phỏng) và có thể phá silently hành vi reservation của nhánh 2-lõi cũ vẫn
  đang chạy trên FPGA thật.

**Đã kiểm tra**: đối chiếu port 100% cho cả 6 chỗ gọi `RV32IMA` (0 thiếu/0 dư cho đúng
port `Mem_PhysAddrM` ở mọi nơi — 4 output debug cũ vẫn để trống ở 3 file legacy như từ
trước, không liên quan tới sửa lần này), cân bằng begin/end cho mọi file bị đụng tới.
**Chưa mô phỏng** — cùng giới hạn như mọi thứ khác trong repo.

---

## 0. TL;DR — trạng thái ngay lúc này

- **MMU 1 lõi**: RTL xong, có testbench (`tb_mmu_core.v`), có wrapper AXI4 thật
  (`mmu_ip_wrapper.v`) + script dựng thử SoC 1 lõi trên Vivado
  (`scripts/build_soc_mmu_trial.tcl`). Bạn đang chạy phần này. **Cập nhật (mục -0.1.1,
  phiên này): `tb_mmu_core.v` đã lỗi thời sau khi page fault được nối để trap thật
  (mục -0.5) — tự phát hiện + đã sửa (thêm mtvec/handler), xem mục -0.1.1 trước khi
  chạy lại.**
- **Hệ 4 lõi đầy đủ (L1 I$/D$ + L2 + MESI coherence)**: RTL đã viết **toàn bộ**
  trong phiên này (7 file mới) + wrapper AXI4 (`quad_core_axi_wrapper.v`) + script
  dựng thử SoC 4 lõi (`scripts/build_soc_4core_trial.tcl`) + **testbench riêng cho
  coherence** (`sim/tb_coherence.v`, mới thêm). **Đây vẫn là phần rủi ro cao nhất
  trong toàn bộ repo** — một giao thức MESI directory viết từ đầu, chỉ được kiểm
  tra bằng cách đọc lại nhiều vòng (đã bắt và sửa ít nhất 4 bug logic thật trong lúc
  viết — xem mục 2 và mục 9) và giờ có 1 testbench nhắm đúng vào điểm rủi ro nhất
  (mandatory-snoop-on-lone-sharer), nhưng **bản thân testbench này cũng chưa chạy
  qua Vivado** — chạy nó và báo kết quả là việc quan trọng nhất cần làm tiếp theo.
- Theo đúng yêu cầu của bạn: **không sửa/ghi đè file .v hay .tcl cũ nào đã có từ
  trước phiên này** (ngoại trừ 3 file đã sửa nhỏ, có ghi rõ lý do, ở mục 2.1 —
  `mmu_top.v`, `mmu_core_wrapper.v`, `tb_mmu_core.v` — vì chúng PHẢI đổi để MMU an
  toàn sau bus thật; mọi khối mới còn lại đều là **file mới, đứng riêng**). **Phiên
  này (mục -0.25) có sửa thêm 6 file đã tồn tại** — nhưng tất cả đều là file **do
  chính các phiên trước của quá trình này tạo ra** (không phải file gốc/đã tổng hợp
  FPGA trong repo ban đầu), và việc sửa là hệ quả trực tiếp, không tránh được, của
  đúng yêu cầu "nối satp CSR vào MMU thật": `csr_trap_unit.v`, `mmu_core_wrapper.v`,
  `core_l1_wrapper.v`, `quad_core_soc.v`, `quad_core_axi_wrapper.v`,
  `build_soc_4core_trial.tcl` — chi tiết lý do từng file ở mục -0.25.
- Theo yêu cầu: **bỏ Interrupt Controller và SRAM Controller** khỏi phạm vi kịch bản
  dựng-thử lần này (`build_soc_4core_trial.tcl` chỉ còn DMA + 1 Memory Controller).
- **Trap/Exception Unit + CSR + Privilege Mode (M/S/U)**: RTL mới xong
  (`csr_trap_unit.v` + `sys_decoder.v`), tích hợp sâu vào pipeline (9 file cũ sửa
  thêm, additive) — MMU page fault giờ **trap thật** thay vì chỉ ép NOP. Xem mục -0.5.
  **Cập nhật (mục -0.1, phiên này)**: giờ có 3 testbench phủ 3 khía cạnh khác nhau —
  `tb_csr_trap.v` (CSR cơ bản + trap ở M-mode, phiên trước), `tb_csr_priv.v` (**mới**:
  M/S/U thật + `medeleg` delegation), và `tb_mmu_core.v` (đã sửa: page fault MMU giờ
  thật sự trap-và-resume đúng). **Cả 3 đều chưa chạy qua Vivado.**
- **AHB-Lite**: file `ahb_lite_l1_adapter.v` (chuyển đổi cổng L1 sang tín hiệu AHB-Lite
  thật), tham khảo `ahb3lite_interconnect-master_reference/` nhưng không gắn trực tiếp
  (giấy phép, thiếu dependency, thừa phức tạp — xem mục -0.5.4). **Giờ ĐÃ nối vào
  top-level 4 lõi** — xem mục -0.25.
- **MỚI (phiên này) — Hướng 2 đã xong**: `satp`/`Mmu_Enable` CSR giờ **thật sự điều
  khiển MMU** (không còn là 2 nguồn "sự thật" tách rời), và có một biến thể top-level
  4 lõi mới (`quad_core_soc_ahb.v`) nối `ahb_lite_l1_adapter.v` (+ 1 file slave-side
  mới, `ahb_lite_l1_slave_adapter.v`) vào đúng biên "CORE → HIGH-SPEED BUS" của sơ đồ.
  Xem mục -0.25 cho chi tiết đầy đủ. **Cả hai đều chưa mô phỏng** — chỉ mới tự kiểm tra
  tĩnh (đối chiếu port 100%) + trace tay.
- Đã khảo sát thông số thật (qua web) cho **Genesys ZU-5EV** và **VCU129** — xem mục
  -0.5.5 để biết kịch bản triển khai 2 bước đề xuất và 1 rủi ro thật cần bạn xác nhận
  (VCU129 chưa rõ có khe SD hay không, trong khi giảng viên yêu cầu bắt buộc nạp
  chương trình từ SD card).
- **MỚI (phiên này) — Hướng 3, kiến trúc boot SD card đã đổi hẳn so với kế hoạch ban
  đầu**: phát hiện SD card trên Genesys ZU-5EV nối qua PS, không nối qua PL — xem mục
  -0.05 cho toàn bộ chi tiết. File mới: `rtl/boot_ctrl.v`,
  `rtl/quad_core_axi_wrapper_bootable.v`, `scripts/build_soc_zu5ev_boot.tcl`,
  `scripts/host_eval_uart.py`, `constraints/*_template.xdc` (2 file, chưa điền số chân
  thật — xem lý do ở mục -0.05.7). VCU129 vẫn còn treo (mục -0.05.8) — cần bạn xác nhận
  vật lý trước khi đầu tư thêm.

---

## 1. MMU: từ "viết xong" đến "gắn được vào bus thật"

Tiếp nối mục 1 của phiên trước (MMU RTL xong về thiết kế, chưa mô phỏng, chưa nối
vào top nào). Trong phiên vừa qua, bạn bắt đầu chạy `tb_mmu_core.v` trong Vivado, rồi
hỏi cách gắn nó vào một SoC thật bằng IP có sẵn của Vivado. Việc đó phơi ra đúng vấn
đề đã cảnh báo ở mục 1 phiên trước: **PTW giả định bộ nhớ luôn trả lời trong đúng 1
chu kỳ — sai ngay khi có độ trễ thật (AXI, trọng tài, ...)**. Đã sửa tận gốc, không
phải vá:

1. **`mmu_top.v`**: thêm input `ptw_mem_valid` thật (trước đây gắn cứng `1'b1`).
   Không cần sửa FSM của `mmu_ptw.v` — nó vốn đã tự lặp lại request khi
   `mem_valid=0` (đọc kỹ mới thấy), chỉ là chưa từng được cấp tín hiệu thật.
2. **`mmu_core_wrapper.v`**: thêm 3 input mới — `Instr_ValidF`, `Mem_ReadDataValidM`,
   `Mem_WriteDoneM` — và logic đóng băng pipeline (`mem_stall`) khi fetch/load/store
   chưa có phản hồi thật, dùng lại đúng cơ chế `Stall_Core_External` sẵn có (không
   đụng `RV32IMA.v`/`memory_stage.v` đã tổng hợp trên phần cứng). **Lưu ý khi đọc
   code**: `data_wait` phải xét trên `Mem_WriteEnM`/`Mem_ReadEnM` (tín hiệu ra bus
   *sau khi* đã bị chặn bởi fault), không phải tín hiệu thô từ core — nếu xét nhầm
   tín hiệu thô, một store bị MMU chặn do lỗi quyền truy cập sẽ treo mãi mãi chờ một
   `Mem_WriteDoneM` không bao giờ tới (bug này đã bắt được và sửa trong lúc viết).
3. **`mmu_ip_wrapper.v`** (file mới): bọc AXI4 thật quanh `mmu_core_wrapper` — đúng
   handshake ARVALID/ARREADY/RVALID (giữ ARVALID tới khi ARREADY, không giả định trả
   lời cùng chu kỳ), AWVALID/WVALID/BVALID tương tự cho store. Có attribute
   `X_INTERFACE_INFO` trên từng port AXI để Vivado tự nhận diện thành bus interface
   khi tạo module reference trong Block Design (không có attribute này, IP Integrator
   chỉ thấy từng tín hiệu rời rạc, không gộp thành 1 interface — đây chính là lỗi đầu
   tiên bạn gặp khi chạy `build_soc_mmu_trial.tcl` lần đầu, đã sửa).
4. **`tb_mmu_core.v`**: cập nhật theo port mới của `mmu_core_wrapper` (gắn cứng 3
   tín hiệu valid/done = 1, vì testbench này mô phỏng bộ nhớ tổ hợp 0-chu-kỳ — giữ
   nguyên hành vi PASS/FAIL như thiết kế ban đầu).
5. **`scripts/build_soc_mmu_trial.tcl`** (file mới): dựng Block Design 1 lõi (MMU +
   AXI Interconnect + 2 BRAM giả lập SRAM/DRAM + DMA + Interrupt Controller — bản
   này VẪN CÒN interrupt/SRAM vì được viết trước khi bạn yêu cầu bỏ chúng; bản 4 lõi
   ở mục 2 mới bỏ theo đúng yêu cầu mới nhất). Luôn xóa-và-dựng-lại BD từ đầu mỗi lần
   chạy (không tái dùng BD cũ dở dang) để tránh lỗi "sửa source rồi mà vẫn lỗi y hệt"
   do Vivado chỉ suy luận interface pin tại đúng thời điểm tạo cell.

**Kết luận mục 1**: MMU 1 lõi giờ *có thể* gắn an toàn vào một bus AXI4 thật (độ trễ
nhiều chu kỳ, có tranh chấp) — điều mà bản trước **không thể** làm mà không âm thầm
sai. Vẫn cần: (a) bạn chạy `tb_mmu_core.v` xác nhận PASS, (b) chạy thử
`build_soc_mmu_trial.tcl`, báo lại nếu có WARNING nào không tự sửa được.

---

## 2. Hệ 4 lõi đầy đủ: L1 Cache + L2 Cache + MESI Coherence — MỚI, TOÀN BỘ

Đây là phần việc lớn nhất phiên này, theo đúng thứ tự bạn yêu cầu: coherence, cache
L2, rồi phần còn thiếu trong wrapper. Tất cả là **file mới**, không sửa file cũ nào
(trừ 3 file ở mục 1, vì lý do đã giải thích).

### 2.1. Danh sách file mới

| File | Vai trò |
|---|---|
| `rtl/l1_icache.v` | L1 instruction cache riêng từng lõi. PIPT (đặt sau MMU — đúng vị trí `mmu_core_wrapper.v` đã ghi chú sẵn). 16KB, 2-way, line 32B theo `address_mapping`. Read-only, **không tham gia coherence** (quyết định có chủ đích — xem mục 2.2). Blocking, 1 outstanding miss (khớp với core hiện tại vốn không hỗ trợ nhiều request cùng lúc). |
| `rtl/l1_dcache.v` | L1 data cache riêng từng lõi. PIPT, MESI đầy đủ (I/S/E/M), write-back, write-allocate. 16KB, 2-way, line 32B. Đây là file phức tạp và rủi ro nhất trong nhóm L1 — xem mục 2.2 cho race điều kiện đã phát hiện và sửa. |
| `rtl/core_l1_wrapper.v` | Gộp `mmu_core_wrapper` (đã có) + `l1_icache` + `l1_dcache` thành đúng 1 khối "CORE N" trong sơ đồ. Cũng là nơi nối lại tín hiệu snoop-invalidate của L1 D$ vào `Snoop_Addr`/`Snoop_WE` cho LR/SC — xem mục 2.3. |
| `rtl/l2_cache.v` | Kho lưu trữ L2 dùng chung: tag + valid + dirty + data + **directory (sharer bitmap 4-bit/line, không có field "dirty owner" riêng — xem mục 2.2 vì sao đủ)**. 256KB, 4-way, line 32B (mặc định theo `address_mapping`; sơ đồ ghi 512KB — xem mục 4, vẫn treo). "Ngu" có chủ đích: không tự sequencing, chỉ nhận lệnh lookup/write 1-chu-kỳ-độ-trễ từ `coherence_manager.v`. |
| `rtl/coherence_manager.v` | "COHERENCE MANAGEMENT UNIT" + "HIGH-SPEED BUS (AHB)" trong sơ đồ, gộp thành 1 module (lý do: Vivado không có IP AHB nào để gọi, nên tách riêng bus AHB thành 1 module không mang lại lợi ích gì — xem chi tiết trong header file). Trọng tài 8 nguồn (4×D$ + 4×I$) ưu tiên cố định (không phải round-robin — xem mục 2.2), engine giao dịch **atomic/tuần tự** điều khiển L2 + gửi snoop tới các L1 D$ + đường ra bộ nhớ ngoài ("CPU MEMORY PORT"). **File phức tạp nhất, rủi ro cao nhất trong toàn repo.** |
| `rtl/quad_core_soc.v` | Khối "4-CORE CPU WRAPPER" đầy đủ: 4× `core_l1_wrapper` + `coherence_manager` (bên trong có `l2_cache`). Cổng bộ nhớ vật lý đơn ra ngoài. |
| `rtl/quad_core_axi_wrapper.v` | Bọc AXI4 thật (1 master gộp đọc/ghi) quanh cổng bộ nhớ của `quad_core_soc.v`, để cắm vào IP Vivado — giống vai trò `mmu_ip_wrapper.v` nhưng cho toàn hệ 4 lõi. |
| `scripts/build_soc_4core_trial.tcl` | Script mới (không đụng `build_soc_mmu_trial.tcl`), dựng Block Design 4 lõi: `quad_core_axi_wrapper` + AXI Interconnect + DMA (`axi_cdma`) + 1 Memory Controller (BRAM giả lập). **Đã bỏ Interrupt Controller và SRAM Controller theo đúng yêu cầu của bạn.** |
| `rtl/ahb_lite_l1_slave_adapter.v` | **Mới (mục -0.25.2).** Nửa slave của cặp AHB-Lite, đối tác của `ahb_lite_l1_adapter.v` — nhận 8 transfer word tuần tự, nói giao thức `dreq_*`/`dresp_*` của `coherence_manager.v` ở phía kia. Dùng chung được cho cả I$ lẫn D$. |
| `rtl/quad_core_soc_ahb.v` | **Mới (mục -0.25.2).** Biến thể top-level song song với `quad_core_soc.v`: cùng 4× `core_l1_wrapper` + `coherence_manager`, nhưng cổng I$/D$ mỗi core đi qua 1 cặp adapter AHB-Lite (8 liên kết điểm-nối-điểm, không phải 1 bus dùng chung). |
| `sim/tb_coherence.v` | **Mới, quan trọng nhất.** Testbench tự-kiểm riêng cho `coherence_manager.v`+`l2_cache.v`+`l1_dcache.v` — lái trực tiếp 4 instance `l1_dcache` thật (không qua core/pipeline, để kiểm soát chính xác thứ tự truy cập giữa các lõi), có mô hình bộ nhớ ngoài 1-chu-kỳ-độ-trễ riêng. 5 bước (A→E): core0 đọc lần đầu (miss, được cấp E) → core0 ghi cục bộ (E→M âm thầm, kiểm tra **không** có traffic ra bus) → core1 đọc cùng line (phải bắt đúng dữ liệu M "ngầm" của core0 qua snoop bắt buộc — đây là phép thử quan trọng nhất, kiểm chứng trực tiếp bất biến "1 sharer → phải snoop" ở mục 2.2) → core2 ghi (RFO) buộc invalidate cả core0 lẫn core1 → core0 đọc lại, phải thấy đúng giá trị mới nhất của core2 (qua vòng snoop bắt buộc lần 2). **Chưa test**: eviction/writeback L1 hoặc L2 (cần địa chỉ xung đột cụ thể để ép ra, chưa dựng trong bản này), lưu lượng I$. Xem header file để biết cách chạy trong Vivado XSIM. |

### 2.2. Thiết kế giao thức MESI — các quyết định cốt lõi (đọc trước khi sửa bất cứ gì)

**Atomic/tuần tự, không pipeline.** Tại một thời điểm, toàn hệ thống chỉ xử lý đúng
1 giao dịch (miss/upgrade/writeback của 1 lõi) cho tới khi hoàn tất hoàn toàn — kể cả
mọi snoop cần thiết. Đánh đổi thông lượng lấy khả năng chứng minh đúng bằng tay (vì
không có simulator để xác nhận một thiết kế pipeline phức tạp hơn). Ghi rõ trong
header `coherence_manager.v`.

**Directory chỉ cần sharer bitmap, không cần field "dirty owner" riêng.** Đây là điểm
tinh vi nhất: MESI cho phép 1 lõi đang giữ Exclusive (E) tự nâng cấp lên Modified (M)
**mà không cần thông báo cho ai** (đó chính là ý nghĩa của E). Vậy làm sao
`coherence_manager` biết 1 sharer duy nhất có đang thực sự "sạch" hay đã âm thầm
thành M? Giải pháp: **bất cứ khi nào một line có ĐÚNG 1 sharer, bắt buộc phải snoop
sharer đó trước khi làm bất cứ điều gì khác với line này** (kể cả khi request mới chỉ
là một READ muốn thêm 1 sharer thứ 2). Vì bước "1 sharer → 2+ sharer" luôn đi qua
snoop này, nên **một khi 1 line đã có 2+ sharer, chắc chắn không ai trong số đó đang
giữ M** (chứng minh bằng quy nạp) — do đó trường hợp 2+ sharer không bao giờ cần
snoop nữa. Đây là bất biến (invariant) làm cho thiết kế directory đơn giản này vẫn
đúng — sai bất biến này ở bất kỳ đâu là sập toàn bộ logic, nên **đừng "tối ưu" bỏ
bước snoop-khi-1-sharer** nếu không hiểu rõ vì sao nó ở đó.

**I$ hoàn toàn không tham gia coherence.** Core hiện tại không có FENCE.I, không có
self-modifying code, không có chế độ đặc quyền. Giữ I$ ngoài giao thức loại bỏ hẳn 1
lớp race (snoop trúng đúng lúc I$ đang fetch) mà 1 bản chưa mô phỏng thì nên tránh
nếu có thể — có ghi rõ đây là lựa chọn có chủ đích, không phải thiếu sót, trong
header `l1_icache.v`.

**Race giữa local-hit và snoop (đã phát hiện, đã sửa).** Atomicity ở
`coherence_manager` chỉ tuần tự hoá các giao dịch ĐI QUA bus/trọng tài — nhưng một
local hit (đọc/ghi trúng cache ngay tại L1, không cần đụng bus) thì KHÔNG đi qua
atomicity đó. Kịch bản: lõi X đang giữ line A ở trạng thái M; lõi Y yêu cầu A;
`coherence_manager` gửi snoop DOWNGRADE tới X; đúng lúc đó pipeline của X (độc lập,
đang chạy song song) cũng đang ghi trúng A. Cả 2 đường (snoop-handler và FSM chính
của X) cùng muốn cập nhật `state_r` của đúng 1 line trong cùng 1 chu kỳ clock — nếu
không xử lý sẽ là xung đột 2 driver thật (lỗi RTL) hoặc mất-cập-nhật (lỗi logic).
Giải quyết trong `l1_dcache.v` bằng `snoop_conflict`: khi có xung đột, snoop luôn
thắng, truy cập cục bộ của core bị ép quay lại "chưa sẵn sàng" và tự thử lại chu kỳ
sau (lúc đó snoop đã giải quyết xong, logic hit/miss bình thường tự xử lý đúng, không
cần case đặc biệt). Đọc chi tiết trong header `l1_dcache.v`.

**4 bug logic thật đã bắt được khi tự đọc lại `coherence_manager.v`** (không phải lý
thuyết — đây là những lỗi cụ thể nếu không bắt được sẽ làm sai kết quả mô phỏng):
1. Biến `[hi:lo]` với cả 2 biên phụ thuộc biến (không phải hằng số) trong phần ghép
   word vào line ở `l1_dcache.v` — Verilog không cho phép bề rộng thay đổi theo dữ
   liệu trong phép ghép `{...}`. Sửa bằng cách dùng `function merge_line` với dạng
   `[base +: width]` (width hằng số, base biến — hợp lệ).
2. `cpu_valid` bị gán bởi 2 `assign` khác nhau cùng lúc trong `l1_dcache.v` (một bản
   nháp sớm còn sót lại) — xung đột driver thật. Đã xoá bản thừa.
3. `l2_cmd_w_sharers` đọc trực tiếp thanh ghi `line_sharers` trong đúng chu kỳ mà
   `S_L2_FILL`/`S_GRANT_WRITE_L2` cũng đang ghi giá trị MỚI vào `line_sharers` (non-
   blocking `<=`, chỉ có hiệu lực chu kỳ SAU) — lệnh ghi vào L2 ở đúng chu kỳ đó vẫn
   dùng giá trị CŨ. Sửa bằng cách tính riêng 1 biểu thức tổ hợp (`grant_sharers`)
   dùng ngay tại chỗ, không đi vòng qua thanh ghi.
4. Khi snoop-ack báo "hit" cho một snoop kiểu INVALIDATE (core đó THỰC SỰ có line và
   vừa bị buộc xoá), code gốc chỉ xoá bit sharer khi ack báo "miss" (`!hit`) — đúng
   cho DOWNGRADE (hit nghĩa là "vẫn còn, giữ làm sharer") nhưng SAI cho INVALIDATE
   (hit nghĩa là "vừa bị xoá, phải bỏ khỏi sharer set"). Sửa: điều kiện xoá bit giờ
   là `!snoop_type_send || !ack_hit` (luôn xoá nếu là INVALIDATE, hoặc xoá nếu ack
   miss bất kể loại nào).

**Trọng tài ưu tiên cố định, không phải round-robin.** Thứ tự cố định (core0-D,
core0-I, core1-D, ...) — đơn giản hơn để suy luận đúng bằng tay so với round-robin
thật xoay vòng qua 8 nguồn. Đây là **giới hạn về công bằng** (core 3 lý thuyết có
thể bị đói nếu core 0 liên tục có traffic), **không phải lỗi đúng/sai** — cần nâng
cấp lên round-robin thật sau khi mô phỏng xác nhận phần logic MESI đúng trước đã.

### 2.3. Cải thiện kèm theo (không phải yêu cầu trực tiếp, nhưng đáng ghi nhận)

`core_l1_wrapper.v` nối snoop kiểu INVALIDATE của L1 D$ vào `Snoop_Addr`/`Snoop_WE`
của core (dùng cho LR/SC ở `memory_stage.v`), thay cho cơ chế "broadcast mọi lần ghi"
thô sơ của `round_robin_arbiter_2core.v` cũ. Đây là tín hiệu **chính xác hơn** (chỉ
nổ đúng lúc coherence thực sự cần invalidate line đó) — nhưng **KHÔNG** giải quyết
hạn chế đã ghi ở `mmu_core_wrapper.v` từ trước: `reservation_addr` trong
`memory_stage.v` được lấy từ `ALU_ResultM` — địa chỉ **ảo** (trước MMU) — trong khi
snoop ở tầng L1 là địa chỉ **vật lý** (sau MMU). Hai bên chỉ khớp đúng nếu VA→PA của
lõi đó tình cờ khớp số. Sửa triệt để cần đổi chỗ so khớp reservation sang miền vật
lý trong `memory_stage.v` — chưa làm, vẫn nằm ngoài phạm vi phiên này (xem mục 5,
dòng #14).

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

`address_mapping` (file text do bạn viết) bổ sung chi tiết định lượng ban đầu (256KB
L2/16KB L1 — số nháp đầu tiên, đã được thay bằng quyết định chính thức bên dưới):
- VA 32-bit, 2 cấp trang, page 4KB.
- TLB: 16-entry fully-associative / lõi.
- Bản đồ địa chỉ vật lý 4GB: Boot ROM 64KB @ 0x0000_0000, Main RAM (cacheable) @
  0x8000_0000–0xBFFF_FFFF, còn lại reserved.
- Coherence: **MESI**, theo dõi theo physical line 32B, directory dạng bitmap 4-bit
  sharer (4 lõi), lưu tại L2.

**Số liệu CHÍNH THỨC (đã chốt, mục 4 + mục -0.02.1 — không còn là số tạm)**:
- `l1_icache.v` = **32KB**, 2-way, line 32B → offset 5b / index 9b (512 sets) / tag 18b.
- `l1_dcache.v` = **32KB**, 2-way, line 32B → offset 5b / index 9b (512 sets) / tag 18b.
  (Mỗi lõi có 1 I$ 32KB + 1 D$ 32KB độc lập, đúng ý "tách riêng" của sơ đồ — không phải
  1 cache 32KB dùng chung.)
- `l2_cache.v` = **512KB**, 4-way, line 32B → offset 5b / index 12b (4096 sets) / tag 15b.
- Bus CORE↔BUS: **AHB-Lite thật** (`quad_core_soc_ahb.v`) — xem mục 4 điểm 1.

---

## 4. Quyết định kiến trúc — 5/6 ĐÃ CHỐT (phiên này), 1 còn treo

Lấy từ `../Gop_y_De_cuong_KLTN.txt` (góp ý của giảng viên). **Cập nhật (mục -0.02):**
bạn đã chốt 5/6 điểm dưới đây — chỉ còn điểm #6 (kịch bản SD card cho VCU129) vẫn treo,
ngoài tầm tôi tự quyết vì phụ thuộc thông tin vật lý board bạn cần tự xác nhận.

1. **AHB hay AXI4? → ĐÃ CHỐT: AHB-Lite.** Bus giữa 4 core và phần còn lại của hệ thống
   (đoạn "HIGH-SPEED BUS (AHB)" trong sơ đồ) là AHB-Lite thật — `quad_core_soc_ahb.v` +
   `ahb_lite_l1_adapter.v`/`ahb_lite_l1_slave_adapter.v` (mục -0.25.2) là bản chính
   thức. Đã cập nhật cả 2 script (`build_soc_zu5ev_boot.tcl`,
   `build_soc_4core_trial.tcl`) dùng đúng bản này làm mặc định (mục -0.02.2), và viết
   thêm testbench riêng cho đường AHB-Lite (`tb_coherence_ahb.v`, mục -0.02.3) — lỗ
   hổng "chưa có test riêng" đã nêu trước đây nay đã đóng. `quad_core_soc.v` (bản dây
   nối trực tiếp) vẫn còn trong repo, vẫn hoạt động, coi là bản tham khảo/dự phòng, đứng
   song song không xoá. Lưu ý vẫn còn đúng như trước: trọng tài 8-nguồn BÊN TRONG
   `coherence_manager.v` vẫn là giao thức tự đặt, không phải tín hiệu AHB chuẩn — nếu
   cần AHB chuẩn sâu hơn (trong chính trọng tài), đó vẫn là việc chưa làm (mục -0.5.4).
2. **Coherence: MESI đầy đủ hay đơn giản hơn? → ĐÃ CHỐT (lại lần nữa): MESI đầy đủ.**
   Giữ nguyên `coherence_manager.v`/`l1_dcache.v`/`l2_cache.v` như đã viết.
3. **MMU/virtual memory: có trong phạm vi báo cáo chính thức không? → ĐÃ CHỐT: CÓ.**
   Toàn bộ MMU/TLB/PTW (mục 1), CSR/Trap/Privilege (mục -0.5), `satp`→MMU thật
   (mục -0.25.1) đều nằm trong phạm vi chính thức từ nay.
4. **Kích thước L2: 256KB hay 512KB? → ĐÃ CHỐT: 512KB.** `l2_cache.v`'s `INDEX_BITS`
   đổi 11→12 (mục -0.02.1).
5. **L1: 16KB/2-way dùng chung hay 32KB I$+32KB D$ tách riêng? → ĐÃ CHỐT: 32KB D$ +
   32KB I$ tách riêng.** `l1_icache.v`/`l1_dcache.v`'s `INDEX_BITS` đổi 8→9 mỗi file
   (mục -0.02.1) — đúng nghĩa "tách riêng" sẵn có từ trước (mỗi lõi vốn đã có 1
   `l1_icache` + 1 `l1_dcache` độc lập), giờ mỗi cái đúng 32KB thay vì 16KB.
6. **Kịch bản test SD card/SPI → DRAM (bắt buộc theo giảng viên). VẪN CÒN TREO cho
   VCU129.** Genesys ZU-5EV đã có kiến trúc + RTL/script (PS-mediated, KHÔNG phải SPI
   bit-banging như dự tính ban đầu — SD nối qua PS, không qua PL, xem mục -0.05.1),
   CHƯA chạy qua Vivado thật. VCU129 vẫn treo hoàn toàn — cần bạn xác nhận vật lý
   trước.**

---

## 5. Bảng khoảng cách (gap analysis) — cập nhật theo phiên này

| # | Khối (theo sơ đồ) | Trạng thái | Ghi chú |
|---|---|---|---|
| 1 | CPU core ×4 | **Có** — `quad_core_soc.v` instantiate đúng 4× `core_l1_wrapper`. `RV32IMA_DualCore_Wrapper.v` (2 lõi cũ, đã tổng hợp trên FPGA) **không bị đụng**, vẫn còn nguyên như một nhánh riêng. | Boot address mỗi lõi tham số hoá độc lập (`RESET_ADDR0..3`), không còn giới hạn "cả 2 lõi cùng boot 1 địa chỉ" như `RV32IMA_DualCore_Wrapper.v`. |
| 2 | MMU + TLB (per-core) | RTL xong + **giờ an toàn sau bus có độ trễ thật** (mục 1) + có wrapper AXI4 (`mmu_ip_wrapper.v`, `quad_core_axi_wrapper.v` qua `core_l1_wrapper`) + **`satp`/`Mmu_Enable` CSR giờ thật sự điều khiển MMU** (mục -0.25.1, `MMU_CTRL_FROM_CSR=1`). | Vẫn cần bạn chạy `tb_mmu_core.v` xác nhận (test MMU cô lập, không qua CSR — vẫn hợp lệ, xem mục -0.25.1). |
| 3 | L1 I-Cache / D-Cache | **Có** (`l1_icache.v`, `l1_dcache.v`) — **32KB mỗi cái, ĐÃ CHỐT** (mục -0.02.1, trước đây 16KB). **Chưa mô phỏng.** | Không dùng RTL tham khảo trực tiếp (viết mới, khớp giao diện `mmu_core_wrapper`) — tránh nguyên bug alias địa chỉ đã biết ở `cache_reference`. |
| 4 | AHB shared bus | **ĐÃ CHỐT: AHB-Lite** (`quad_core_soc_ahb.v`, mục 4 điểm 1) — tín hiệu AHB-Lite thật ở biên CORE↔BUS, qua `ahb_lite_l1_adapter.v`+`ahb_lite_l1_slave_adapter.v`, 8 liên kết điểm-nối-điểm. **Giờ có testbench riêng** (`tb_coherence_ahb.v`, mục -0.02.3, chưa chạy qua Vivado). `quad_core_soc.v` (dây nối trực tiếp) vẫn còn, không xoá, coi là tham khảo. Trọng tài bên trong `coherence_manager.v` vẫn là giao thức tự đặt, không phải tín hiệu AHB chuẩn. | `round_robin_arbiter_2core.v` (2 lõi cũ) không bị đụng, vẫn dùng cho nhánh `RV32IMA_DualCore_Wrapper.v`. |
| 5 | Shared L2 Cache | **Có** (`l2_cache.v`) — **512KB/4-way, ĐÃ CHỐT** (mục -0.02.1, trước đây 256KB). **Chưa mô phỏng.** | — |
| 6 | Coherence Management Unit | **Có, mới viết** (`coherence_manager.v`) — MESI đầy đủ, atomic/tuần tự. **Rủi ro cao nhất, chưa mô phỏng** — xem mục 2.2, mục 9. | — |
| 7 | CPU Memory Port / System Bus AXI4 | **Có** — `quad_core_axi_wrapper_ahb.v` (mới, bọc bản AHB-Lite chính thức) bọc AXI4 thật quanh cổng bộ nhớ đơn của `quad_core_soc_ahb.v`; `scripts/build_soc_4core_trial.tcl`/`build_soc_zu5ev_boot.tcl` gắn vào `axi_interconnect` (IP Vivado). | `quad_core_axi_wrapper.v` (bọc bản dây nối trực tiếp) vẫn còn, không xoá. |
| 8 | DMA Controller | **Dùng IP Vivado** (`axi_cdma`) trong cả 2 script — theo đúng yêu cầu "gọi IP có sẵn". | `axi_cdma` (memory-mapped↔memory-mapped) hợp hơn `axi_dma` (cần thiết bị AXI-Stream) cho vai trò trong sơ đồ. |
| 9 | SRAM Controller + SRAM | **Bỏ khỏi phạm vi** theo yêu cầu mới nhất của bạn. `build_soc_mmu_trial.tcl` (bản cũ, 1 lõi) vẫn còn 1 BRAM đóng vai SRAM — không sửa lại (đã có sẵn từ trước yêu cầu bỏ); `build_soc_4core_trial.tcl` (bản mới) không có. | — |
| 10 | Memory Controller (DDR) + DDRAM | **Dùng IP Vivado** (`axi_bram_ctrl` + `blk_mem_gen`, giả lập — chưa phải DDR/MIG/PS7 thật, xem `build_soc_mmu_trial.tcl` header vì sao chưa dùng PS7 ngay). | — |
| 11 | Interrupt Controller | **Bỏ khỏi phạm vi** theo yêu cầu mới nhất. | `build_soc_mmu_trial.tcl` (bản cũ) vẫn còn `axi_intc` — không sửa lại. |
| 12 | Mở rộng 2→4 core | **Xong** — `quad_core_soc.v`. | Không thay thế `RV32IMA_DualCore_Wrapper.v`/`round_robin_arbiter_2core.v` — đứng song song, độc lập. |
| 13 | Trap/exception unit, CSR, privilege mode | **Có, mới viết** (`csr_trap_unit.v`+`sys_decoder.v`, xem mục -0.5) — M/S/U đầy đủ, ECALL/EBREAK/illegal-instruction/page-fault đều trap thật, MRET/SRET, `satp` là CSR thật **và giờ thật sự điều khiển MMU** (mục -0.25.1). **Chưa mô phỏng.** Không có interrupt (đúng như dòng #11). | — |
| 14 | LR/SC đúng đắn khi có MMU | **ĐÃ SỬA (mục -0.02.4)** — `memory_stage.v` giờ so khớp reservation theo địa chỉ VẬT LÝ (`Mem_PhysAddrM`, cổng mới xuyên `RV32IMA.v`), cùng miền với `Snoop_Addr`, không còn phụ thuộc VA→PA của từng core có trùng nhau hay không. **Chưa mô phỏng** (như mọi thứ khác). | 6 chỗ gọi `RV32IMA` đều đã nối cổng mới — 1 chỗ (`mmu_core_wrapper.v`) nối `pa_mem` thật, 5 chỗ còn lại (không MMU) nối vòng `Mem_AddrM`→`Mem_PhysAddrM` (VA=PA identity, giữ nguyên hành vi cũ). |
| 15 | Bootloader SD card → DRAM | **Genesys ZU-5EV: có, mới** — kiến trúc PS-mediated (`boot_ctrl.v` + `quad_core_axi_wrapper_bootable.v` + `build_soc_zu5ev_boot.tcl`), KHÔNG phải SPI bit-banging PL như kế hoạch ban đầu (xem mục -0.05.1 vì sao đổi). **VCU129: còn treo** — cần xác nhận vật lý trước (mục -0.05.8). | Phần mềm loader phía PS (ARM, Vitis/PetaLinux) chỉ mô tả quy trình, không hand-assemble (mục -0.05.5) — khác toolchain hoàn toàn với RISC-V. |
| 16 | Kịch bản đánh giá tự động trên FPGA | **Có, mới** — `scripts/host_eval_uart.py`, đọc PASS/FAIL qua console UART của PS (không qua waveform). | Kết quả PASS/FAIL đi qua `boot_ctrl`'s `REG_RESULT`, không qua `axi_uartlite` PL (mục -0.05.3 — lý do). |

---

## 6. Đánh giá 3 folder tham khảo (không đổi so với phiên trước)

- **`mmu_reference/mmu-main/`** — MMU Sv39 mã nguồn mở BSC, dùng để học cách giải
  quyết vấn đề khó, không copy trực tiếp (scope Sv39/PA 34-bit vượt nhu cầu).
- **`cache_reference/`** — nhánh phát triển song song, core khác hẳn (`core_top.sv`),
  PASS của nó không nói lên gì về `Risc_V_new`. Giá trị thật: danh sách bug đã gặp
  (đáng đọc), cấu trúc L2/coherence tham khảo được (không copy — line size 256-bit
  lệch với 32B của bạn), bug alias địa chỉ D-cache cần tránh lặp lại.
- **`Controller_Cache_2Cores_RV32IA/`** — đồ án nhóm khác, tham khảo MOESI + cách
  trình bày báo cáo; `moesi_controller.v` có dấu hiệu nguồn gốc ngoài, cần tự xác
  minh trước khi trích dẫn.

---

## 7. Lộ trình đề xuất (cập nhật theo phiên này)

- [x] **Phase 0** — Lõi RV32IMA 2 lõi chạy được trên FPGA, MMU 1-lõi viết xong.
- [ ] **Phase 1a** — Bạn chạy `tb_mmu_core.v`, báo PASS/FAIL. *(Đang làm.)*
- [x] **Phase 1c (mới)** — MMU an toàn sau bus có độ trễ thật + wrapper AXI4 thật +
      script dựng-thử SoC 1 lõi. *(Xong RTL/script, chờ bạn chạy Vivado.)*
- [ ] **Phase 1b** — Chốt các quyết định kiến trúc ở mục 4. *(Không thể làm thay —
      vẫn treo, và giờ cấp bách hơn vì RTL cache/coherence đã viết theo 1 lựa chọn
      cụ thể (MESI, 256KB L2, 16+16KB L1) mà bạn có thể muốn đổi.)*
- [x] **Phase 2** — L1 I$/D$ riêng từng lõi. *(Xong RTL, chưa mô phỏng.)*
- [x] **Phase 3** — Nhân bản lên 4 core + bus/arbiter tương ứng. *(Xong RTL —
      `quad_core_soc.v` — chưa mô phỏng.)*
- [x] **Phase 4** — Shared L2 + Coherence Management Unit (MESI). *(Xong RTL —
      `l2_cache.v` + `coherence_manager.v` — CHƯA MÔ PHỎNG, rủi ro cao nhất, xem
      mục 9.)*
- [x] **Phase 4b (quan trọng nhất kế tiếp)** — Testbench cho
      `coherence_manager.v`/`l2_cache.v`/`l1_dcache.v` (`sim/tb_coherence.v`,
      5 bước, nhắm đúng vào bất biến "1 sharer → phải snoop"). *(Đã viết, CHƯA
      CHẠY — bạn cần chạy trong Vivado và báo PASS/FAIL. Chưa phủ eviction/
      writeback — xem mục 2.1.)*
- [x] **Phase 5 (một phần)** — AXI4 system bus + Memory Controller + DMA Controller
      dùng IP Vivado. *(Xong script — `build_soc_4core_trial.tcl` — SRAM Controller
      và Interrupt Controller đã bỏ theo yêu cầu, không làm nữa trừ khi bạn đổi ý.)*
- [ ] **Phase 6** — Bootloader SD/SPI → DRAM + kịch bản đánh giá tự động trên FPGA.
- [x] **Phase 7** — Trap/exception unit + CSR + privilege mode. *(Xong RTL — xem mục
      -0.5 — CHƯA MÔ PHỎNG. Cần testbench riêng, chưa viết trong phiên này do hết
      ngân sách thời gian sau phần coherence + CSR/trap + AHB-Lite + khảo sát board.)*
- [x] **Phase 7b** — `sim/tb_csr_trap.v` đã viết: chương trình tay-assemble
      exercising CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI, EBREAK, ECALL (M-mode), 1 lệnh bất
      hợp lệ (illegal instruction), và MRET quay lại đúng chỗ sau mỗi trap. **CHƯA
      CHẠY — bạn cần chạy trong Vivado.** Chưa phủ (khi viết): delegation sang S-mode
      (`medeleg`), chuyển đổi M/S/U thật (test chỉ ở lại M-mode xuyên suốt), và
      trap-thật-từ-MMU (page fault) — cả 3 đã được làm ở Phase 9 (mục -0.1) ngay dưới
      đây.

  **Bug thật thứ 4 bắt được — lần này TRƯỚC KHI testbench chạy, chỉ bằng cách tự
  trace tay chương trình test**: `CSRRS x31,mepc,x0` rồi dùng `x31` ngay ở lệnh kế
  tiếp (`ADDI x31,x31,4`, đúng mẫu bộ xử lý trap dùng ở `tb_csr_trap.v`) sẽ bị
  forward SAI — đường "forward từ M" sẵn có (`execute_stage.v`'s `forward_a_mux`) chỉ
  biết forward `ALUResultM`, chưa biết `ResultSrcM` giờ còn có thể là giá trị đọc CSR
  (`CsrRDataM`, mã 2'b11). Sửa bằng đúng mẹo đã có sẵn trong `hazard_unit.v` cho
  load-use hazard: thêm `csr_load_use_hazard` (tính ở `RV32IMA.v`, OR vào
  `StallF`/`StallD`/`FlushE` **từ bên ngoài**, không sửa `hazard_unit.v`) — buộc lệnh
  dùng kết quả CSR phải đợi thêm 1 chu kỳ để nhận đúng giá trị qua đường "forward từ
  W" (vốn đã đúng, vì `writeback_stage.v`'s mux đã xử lý đúng mọi `ResultSrcW`).
  **Đây là lỗi có thật, ảnh hưởng bất kỳ chương trình nào dùng CSR rồi dùng ngay kết
  quả ở lệnh kế tiếp** — không phải lỗi riêng của testbench.

- [x] **Phase 8 (Hướng 2, phiên này)** — `satp`/`Mmu_Enable` CSR → điều khiển MMU thật
      (`MMU_CTRL_FROM_CSR`, xem mục -0.25.1) + `ahb_lite_l1_adapter.v` → top-level 4
      lõi qua file mới `ahb_lite_l1_slave_adapter.v` + `quad_core_soc_ahb.v` (xem mục
      -0.25.2). *(Xong RTL, đã tự kiểm tra tĩnh 100% khớp port trên toàn bộ chuỗi ảnh
      hưởng — CHƯA MÔ PHỎNG. Cập nhật (mục -0.02.3): `quad_core_soc_ahb.v` giờ ĐÃ có
      testbench riêng, `sim/tb_coherence_ahb.v`.)*
- [x] **Phase 9 (Hướng 1, phiên này)** — M/S/U thật + `medeleg` delegation: file mới
      `sim/tb_csr_priv.v` (xem mục -0.1.2). Page-fault-từ-MMU-thật-sự-trap: `tb_mmu_core.v`
      đã lỗi thời (page fault không trap khi nó được viết) và đã sửa (mục -0.1.1) thay
      vì viết trùng lặp 1 file mới dựng lại đúng page table đó. *(Xong RTL/testbench,
      đã tự kiểm tra tĩnh (đối chiếu port + cân bằng begin/end) + trace tay + xác minh
      encoding qua assembler/decoder nháp riêng — CHƯA CHẠY QUA VIVADO.)*
- [x] **Phase 10 (Hướng 3, phiên này)** — Bootloader SD card (Genesys ZU-5EV: kiến trúc
      PS-mediated, KHÁC hẳn kế hoạch SPI-bit-banging ban đầu sau khi phát hiện SD nối
      qua PS không qua PL — xem mục -0.05.1), kịch bản đánh giá tự động
      (`scripts/host_eval_uart.py`, đọc PASS/FAIL qua console UART của PS, không xem
      waveform), file `.xdc` (2 file TEMPLATE, chưa điền số chân thật — xem mục -0.05.7
      vì sao). *(Genesys ZU-5EV: xong kiến trúc + RTL (`boot_ctrl.v`,
      `quad_core_axi_wrapper_ahb_bootable.v` — cập nhật mục -0.02.2, dùng bản AHB-Lite
      chính thức) + script (`build_soc_zu5ev_boot.tcl`) — CHƯA CHẠY QUA VIVADO, một số
      bước PS-automation cố ý để cảnh báo "sửa tay nếu lệch" thay vì đoán liều. VCU129:
      còn treo, cần bạn xác nhận vật lý (mục -0.05.8) trước khi đầu tư RTL bootloader
      SD-SPI thật.)*
- [x] **Phase 11 (phiên này)** — Chốt 5/6 quyết định kiến trúc còn treo (AHB-Lite, MESI,
      MMU trong phạm vi chính thức, L2 512KB, L1 32KB D$+32KB I$ — mục -0.02.1/4) + sửa
      bug LR/SC VA-vs-PA đã biết từ nhiều phiên trước (mục -0.02.4) + đóng lỗ hổng
      "AHB-Lite chưa có testbench riêng" (`tb_coherence_ahb.v`, mục -0.02.3) + thêm lớp
      AXI wrapper còn thiếu cho bản AHB-Lite (`quad_core_axi_wrapper_ahb.v` +
      `quad_core_axi_wrapper_ahb_bootable.v`, mục -0.02.2). *(Xong RTL/script, đã tự
      kiểm tra tĩnh (đối chiếu port 100% trên MỌI chỗ gọi `RV32IMA`/L1/L2/AHB-Lite bị
      ảnh hưởng, cân bằng begin/end) — CHƯA MÔ PHỎNG.)*

---

## 8. Cách chạy trong Vivado

### `tb_mmu_core.v` (MMU 1 lõi, mô phỏng thuần)
Cách chạy không đổi: add toàn bộ `rtl/*.v` liên quan + `sim/tb_mmu_core.v`, set làm
simulation top, `run -all`, kỳ vọng `MMU_TB: PASS`. **Nội dung chương trình BÊN TRONG
đã đổi (mục -0.1.1, phiên này)** — nếu bạn từng chạy file này ở phiên trước và nó PASS,
đó là PASS của phiên bản CŨ (page fault không trap) và không còn phản ánh đúng RTL hiện
tại; cần chạy lại. Kỳ vọng mới: vẫn `MMU_TB: PASS`, cộng 1 check mới `x11 (mcause after
not-present load trap)` = 13.

### `sim/tb_csr_priv.v` (M/S/U thật + `medeleg` delegation, mô phỏng thuần — MỚI)
Add làm sim sources: đúng danh sách file như `tb_csr_trap.v` bên dưới (cùng DUT, RV32IMA
thô, không cần MMU/cache/coherence) cộng `sim/tb_csr_priv.v` thay vì `tb_csr_trap.v`.
Set `tb_csr_priv` làm simulation top, `run -all`. Kỳ vọng 8 dòng `[PASS] x1...x8`, dòng
`CurrentPriv ended in U`, dòng `priv_hist_count: 6 transitions`, 6 dòng
`priv_history[0..5]`, và cuối cùng `CSR_PRIV_TB: PASS`. Nếu FAIL ở bất kỳ `x5`/`x7`
(đọc `scause`/`mcause`) — nhiều khả năng priv lúc đó KHÔNG đúng S/M như kỳ vọng (CSR đó
sẽ tự fault illegal-instruction nếu priv sai, xem mục -0.1.2), tức là bug nằm ở chính cơ
chế MRET/SRET/delegation trong `csr_trap_unit.v`, không phải ở testbench.

### `scripts/build_soc_mmu_trial.tcl` (SoC AXI4 1 lõi, dùng IP Vivado)
Mở `Risc_V.xpr`, ở Tcl Console: `source {đường dẫn tới file}`. Xem chi tiết/caveat
trong chính file (đã có từ phiên trước, không đổi lần này).

### `scripts/build_soc_4core_trial.tcl` (SoC AXI4 4 lõi + cache + coherence — MỚI)
Tương tự: mở `Risc_V.xpr`, `source {đường dẫn tới file}`. **Đọc kỹ phần
"CORRECTNESS CAVEAT" ở đầu file trước khi tin bất kỳ kết quả nào** — script này chỉ
chứng minh phần *dây nối* (wiring) khớp và elaborate được; nó **không** chứng minh
giao thức MESI bên trong đúng. `validate_bd_design` sạch ≠ coherence đúng.

### `rtl/quad_core_soc_ahb.v` (biến thể AHB-Lite, giờ là bus chính thức — xem `sim/tb_coherence_ahb.v` bên dưới)
Đã có testbench riêng từ phiên này — xem `sim/tb_coherence_ahb.v` bên dưới (mục -0.02.3),
không cần "elaborate-only" nữa. Cách kiểm tra khả dụng qua elaborate (nếu chỉ muốn xác
nhận wiring, không chạy testbench đầy đủ): add toàn bộ `rtl/*.v` liên quan (mọi file
`quad_core_soc.v` cần, cộng `ahb_lite_l1_adapter.v` + `ahb_lite_l1_slave_adapter.v` +
`quad_core_soc_ahb.v`) vào 1 project/sim fileset rồi để Vivado elaborate — việc này chỉ
xác nhận *dây nối tồn tại và đúng tên*, không thay thế được việc chạy testbench thật.

### `sim/tb_coherence.v` (MESI coherence, mô phỏng thuần — CHẠY CÁI NÀY TRƯỚC TIÊN)
Add làm sim sources: `rtl/l1_dcache.v`, `rtl/l2_cache.v`, `rtl/coherence_manager.v`,
`rtl/load_unit.v`, `rtl/store_unit.v`, cộng `sim/tb_coherence.v`. Set `tb_coherence`
làm simulation top, `run -all`. Kỳ vọng 5 dòng `[PASS] A/B/C/D/E ...` (dòng B là
`[PASS] B: core0's E->M write stayed local` chứ không phải `check_eq32`, xem code)
và cuối cùng `COHERENCE_TB: PASS`. Nếu FAIL — đặc biệt là bước C hoặc E — đó gần như
chắc chắn là bug thật trong logic snoop/directory, không phải lỗi testbench; gửi lại
log đầy đủ (đặc biệt giá trị `got=`/`expected=`) để định vị đúng chỗ trong
`coherence_manager.v`.

### `sim/tb_coherence_ahb.v` (MESI qua cầu AHB-Lite, mô phỏng thuần — MỚI, CHẠY SAU `tb_coherence.v`)
Add làm sim sources: mọi thứ `tb_coherence.v` cần, cộng `rtl/ahb_lite_l1_adapter.v` +
`rtl/ahb_lite_l1_slave_adapter.v`, thay `sim/tb_coherence.v` bằng
`sim/tb_coherence_ahb.v`. Set `tb_coherence_ahb` làm simulation top, `run -all`. Kỳ
vọng đúng 5 dòng `[PASS] A/B/C/D/E` giống hệt `tb_coherence.v` và cuối cùng
`COHERENCE_AHB_TB: PASS`. **Chỉ nên chạy sau khi `tb_coherence.v` (bản gốc) đã PASS** —
nếu bản gốc PASS mà bản AHB-Lite này FAIL đúng ở 1 bước cụ thể, lỗi gần như chắc chắn
nằm ở `ahb_lite_l1_adapter.v`/`ahb_lite_l1_slave_adapter.v`, không phải ở
`coherence_manager.v`/`l1_dcache.v` (không đổi gì ở 2 file đó trong test này). Thời gian
chạy lâu hơn hẳn bản gốc (mỗi giao dịch giờ tốn 8 lần truyền word qua AHB-Lite) — đây là
kỳ vọng đúng, không phải dấu hiệu treo, trừ khi vượt hẳn ngân sách 40000 chu kỳ.

### `sim/tb_csr_trap.v` (CSR/Trap/Privilege, mô phỏng thuần — CHẠY CÁI NÀY THỨ HAI)
Add làm sim sources: **toàn bộ `rtl/*.v`** liên quan tới core (không cần MMU/cache/
coherence cho bài test này — chỉ `RV32IMA.v` và mọi file nó `module`-instantiate:
`ALU.v`, `ALU_Decoder.v`, `Control_Unit.v`, `Main_Decoder.v`, `decode_stage.v`,
`sys_decoder.v`, `Register_File.v`, `Sign_Extend.v`, `execute_stage.v`, `Mux_3_by_1.v`,
`mux.v`, `fetch_stage.v`, `PC_module.v`, `PC_Adder.v`, `hazard_unit.v`,
`if_id_registers.v`, `id_ex_registers.v`, `ex_mem_registers.v`, `mem_wb_registers.v`,
`memory_stage.v`, `writeback_stage.v`, `csr_trap_unit.v`) cộng `sim/tb_csr_trap.v`.
Set `tb_csr_trap` làm simulation top, `run -all`. Kỳ vọng 15 dòng `[PASS] x1...x14,
CurrentPriv...` và cuối cùng `CSR_TRAP_TB: PASS`. Nếu FAIL ở `x10`/`x11`/`x12`
(marker sau EBREAK/ECALL/illegal-instr) — nhiều khả năng là lỗi redirect PC/flush hay
đúng bug forwarding đã ghi ở mục 7 (Phase 7b) nếu bạn thấy giá trị hoàn toàn vô lý
(không phải đơn giản sai 1 bit) ở `x10`/`x11`/`x12`, vì đó là dấu hiệu core đã nhảy
sai địa chỉ (MRET dùng `mepc` bị hỏng do forward sai).

### `scripts/build_soc_zu5ev_boot.tcl` (SD boot Genesys ZU-5EV — MỚI, cần board part)
Mở `Risc_V.xpr` **với board part Genesys ZU-5EV đã chọn trong Project Settings** (bắt
buộc — script dùng board-preset automation cho PS, không set tay từng property DDR/MIO).
Ở Tcl Console: `source {đường dẫn tới file}`. **Đọc kỹ mọi dòng WARNING** — khác 2 script
trước ở chỗ phần PS bring-up (bước [2], [5]) và TOÀN BỘ clock/reset (bước [6]) cố ý để
bạn tự hoàn thiện qua GUI's Run Connection Automation thay vì đoán liều cú pháp Tcl chính
xác cho version Vivado của bạn — xem "Ghi chú trung thực" ở mục -0.05.4. Sau khi
`validate_bd_design` sạch, mở Address Editor ghi lại địa chỉ của `boot_ctrl` (nhìn từ cả
`cpu0/M_AXI` lẫn `ps0`'s GP master) — cần cho bước viết loader phía PS (mục -0.05.5).

### `scripts/host_eval_uart.py` (đánh giá tự động qua UART — MỚI)
Cần `pip install pyserial` trước. Sau khi board đã boot xong (SD → PS loader → ghi GO →
RISC-V chạy → RISC-V ghi `REG_RESULT` → PS đọc lại + in "PASS"/"FAIL" ra console UART của
chính nó — xem mục -0.05.5): `python host_eval_uart.py --port COM5 --baud 115200` (đổi
`COM5` thành cổng COM thật của board). Mã thoát: 0=PASS, 1=FAIL, 2=timeout (kiểm tra lại
board đã boot chưa, GO đã ghi chưa), 3=không mở được cổng.

---

## 9. Sổ rủi ro / việc dễ quên (cập nhật)

**Đã kiểm tra tĩnh (không cần Vivado)**: viết script đối chiếu tự động toàn bộ danh
sách port giữa mỗi module và từng chỗ instantiate nó, cho **mọi** file mới/sửa trong
phiên này (`l1_icache`↔`core_l1_wrapper`, `l1_dcache`↔`core_l1_wrapper`,
`l2_cache`↔`coherence_manager`, `core_l1_wrapper`↔`quad_core_soc`,
`quad_core_soc`↔`quad_core_axi_wrapper`, `coherence_manager`↔`quad_core_soc`,
`l1_dcache`/`coherence_manager`↔`tb_coherence`, `mmu_core_wrapper`↔`mmu_ip_wrapper`/
`tb_mmu_core`, `mmu_top`↔`mmu_core_wrapper`) — **khớp chính xác 100%, không thiếu/dư
port nào**. Đây chỉ xác nhận *dây nối đúng tên*, không xác nhận *logic đúng* — hai
việc khác hẳn nhau, đừng nhầm lẫn khi đọc log này.

**Cập nhật (mục -0.25, phiên này)**: chạy lại đúng script đối chiếu đó cho toàn bộ
chuỗi bị ảnh hưởng bởi việc xoá port `Mmu_Enable`/`Satp_PPN` (`mmu_core_wrapper`↔`dut`
trong cả `mmu_ip_wrapper.v` lẫn `tb_mmu_core.v` — xác nhận 2 chỗ này **không đổi**,
đúng như kỳ vọng của `MMU_CTRL_FROM_CSR` mặc định `0`) + toàn bộ 17 chỗ instantiate mới
trong `quad_core_soc_ahb.v` (1× `coherence_manager`, 16× adapter) — tất cả khớp chính
xác 100%.

**Cập nhật (mục -0.1, phiên này)**: đối chiếu port cho `RV32IMA`↔`dut` trong
`sim/tb_csr_priv.v` (mới) — khớp chính xác 100%, 21/21 port. Ngoài ra, phát hiện +
sửa 1 bug thật trong `sim/tb_mmu_core.v` (đã lỗi thời so với RTL hiện tại — xem mục
-0.1.1) và 2 bug thật trong lúc hand-assemble chương trình cho `tb_csr_priv.v` (đường
sign-extend của ADDI ăn vào đúng bit mstatus.MPP cần dựng — xem mục -0.1.2) — không bug
nào trong số này nằm trong RTL, cả 3 đều nằm trong testbench/chương trình test tự viết.

**Rủi ro cao nhất, đọc trước tiên**: `coherence_manager.v` + `l1_dcache.v` +
`l2_cache.v` hiện thực một giao thức MESI directory viết hoàn toàn mới, **chưa từng
chạy qua bất kỳ simulator nào**. Đã tự review nhiều vòng và bắt được 4 bug logic
thật trong lúc viết (xem mục 2.2) — nhưng số bug đã bắt được **không phải là bằng
chứng đã hết bug**, chỉ là bằng chứng nên nghi ngờ phần này nhiều hơn các phần
khác. Việc bắt buộc trước khi dùng phần này cho bất cứ điều gì quan trọng: viết và
chạy 1 testbench trong Vivado (xem Phase 4b ở mục 7).

1. `mmu_top.v`'s `ptw_mem_valid` giờ đã là input thật (đã sửa mục 1) — không còn là
   rủi ro nữa, nhưng nếu thấy code cũ/bản sao chép nào còn `.mem_valid(1'b1)` gắn
   cứng, đó là bản chưa cập nhật.
2. D-cache alias bug (`cpu_addr[2]` bị bỏ qua) trong thiết kế tham khảo
   `cache_reference` — `l1_dcache.v` mới viết **không** có bug này (dùng
   `cpu_addr[1:0]` đầy đủ qua `load_unit`/`store_unit`/`merge_line`), nhưng nhắc lại
   để không ai vô tình tái tạo nó khi sửa sau này.
3. `tb_top.v` (2 lõi cũ) vẫn để 2 lõi boot cùng địa chỉ — không đổi trong phiên này
   (không đụng file 2-lõi cũ). `quad_core_soc.v` (4 lõi mới) đã tham số hoá đúng,
   không bị hạn chế này.
4. LR/SC qua nhiều lõi: **ĐÃ SỬA (mục -0.02.4)** — `memory_stage.v` giờ so khớp
   reservation theo địa chỉ vật lý (`Mem_PhysAddrM`) thay vì địa chỉ ảo, cùng miền với
   `Snoop_Addr`. Mục này trước đây cảnh báo "chưa fix triệt để", giữ lại số thứ tự để
   không nhầm khi đọc lại lịch sử — đã lỗi thời, xem mục -0.02.4 cho chi tiết đầy đủ.
   Vẫn **chưa mô phỏng** như mọi thứ khác.
5. `moesi_controller.v` (tham khảo, không dùng) — vẫn cần xác minh nguồn gốc nếu
   định trích dẫn.
6. Kích thước L2/L1 **ĐÃ CHỐT chính thức** (mục 4, mục -0.02.1) — **512KB/4-way L2,
   32KB I$ + 32KB D$ mỗi lõi**. Mục này trước đây ghi "256KB/16+16KB, lựa chọn tạm" —
   đã lỗi thời, giữ số thứ tự để không nhầm khi đọc lại lịch sử.
7. **Trọng tài trong `coherence_manager.v` là ưu tiên cố định, không round-robin** —
   đừng nhầm là round-robin khi đọc code; đây là giới hạn công bằng đã biết, ghi rõ
   trong header file, không phải để tự ý "tối ưu" mà chưa hiểu lý do.
8. `l1_icache.v` hard-code `WAYS=2` thật sự (không phải tham số tổng quát dù có khai
   `parameter` khác) — đừng đổi `WAYS` mà không sửa lại phần chọn way/LRU 1-bit bên
   trong.
9. **`csr_trap_unit.v` + toàn bộ đường dây CSR xuyên pipeline — CHƯA MÔ PHỎNG, rủi ro
   cao thứ nhì sau coherence.** Đã tự bắt 3 bug thật lúc viết (mục -0.5.2) — cùng bài
   học như coherence: số bug đã bắt không phải bằng chứng đã hết bug. Việc bắt buộc
   trước khi tin dùng: viết + chạy `sim/tb_csr_trap.v` (xem Phase 7b, mục 7).
10. `satp`/`Mmu_Enable` giờ **đã** điều khiển MMU thật (mục -0.25.1,
    `MMU_CTRL_FROM_CSR=1` trong `core_l1_wrapper.v`) — mục này trước đây cảnh báo
    ngược lại, đã lỗi thời, giữ lại để không ai tưởng nhầm vẫn còn treo. **Nhưng
    CHƯA có testbench nào xác nhận đường vòng lại này chạy đúng** (chỉ trace tay +
    xác nhận không có combinational loop) — vẫn nằm trong nhóm rủi ro "chưa mô
    phỏng", xem mục 9 câu mở đầu.
11. `legacy_2core/RV32IMA_DualCore_Wrapper.v` và `RV32_IP_Wrapper.v` đã bị sửa (tie-off
    2 port mới `1'b0`) — ngoại lệ duy nhất với "không đụng file cũ", có lý do rõ ở mục
    -0.5.3. Không phải sửa nhầm.
12. **Kết quả CSR (`ResultSrc=2'b11`) không được forward đúng từ M-stage** — đã sửa
    (bug #4, xem Phase 7b ở mục 7) bằng `csr_load_use_hazard` ở `RV32IMA.v`. Nếu sau
    này ai đó thêm 1 `ResultSrc` mới nữa (ví dụ cho 1 loại lệnh khác), nhớ kiểm tra lại
    xem có cần forward từ M hay không — `forward_a_mux`/`forward_b_mux` trong
    `execute_stage.v` **chỉ** biết forward `ALUResultM`, không tự động đúng cho mọi
    `ResultSrc` mới.
13. **`Mmu_Enable`/`Satp_PPN0..3` không còn tồn tại** ở `core_l1_wrapper.v`,
    `quad_core_soc.v`, `quad_core_axi_wrapper.v` (mục -0.25.1 — xoá thật, không chỉ
    mặc định `0`). Nếu có ghi chú/slide/báo cáo nào từ phiên trước còn nhắc tới các
    port này ở 3 file đó, chúng đã lỗi thời — cần cập nhật lại thành "satp là CSR nội
    bộ mỗi core, không có chân ngoài". `mmu_core_wrapper.v` (module 1 lõi thấp nhất)
    **vẫn còn** 2 port này — chỉ bị bỏ ở các lớp bọc cao hơn, không xoá tận gốc.
14. **`quad_core_soc_ahb.v` (mục -0.25.2) đổi trạng thái MESI cấp về L1 thành "luôn
    báo S"** — không phải bug, là giới hạn có chủ đích của việc đặt AHB-Lite (chỉ có
    OKAY/ERROR) vào đường trả line-fill. Hệ quả thật: line vốn được cấp Exclusive giờ
    luôn cần 1 vòng RFO thêm ở lần ghi cục bộ đầu tiên nếu dùng `quad_core_soc_ahb.v`
    thay vì `quad_core_soc.v`. Không sai kết quả, chỉ chậm hơn — đừng nhầm là bug khi
    thấy nhiều traffic RFO hơn dự kiến lúc so sánh 2 bản.
15. **`quad_core_soc_ahb.v` + `ahb_lite_l1_slave_adapter.v` giờ ĐÃ có testbench riêng**
    (`sim/tb_coherence_ahb.v`, mục -0.02.3) — mục này trước đây ghi "chưa có", đã lỗi
    thời. Testbench này CHƯA CHẠY qua Vivado — chỉ đối chiếu port tĩnh + trace tay, cùng
    bài học như mọi thứ khác: chưa test không có nghĩa là đúng, chỉ có nghĩa là chưa
    biết.
16. **Bài học chung, đáng nhớ khi sửa/thêm testbench sau này**: nối 2 subsystem đã
    review riêng biệt (ở đây: MMU + CSR/trap) có thể làm MỘT trong 2 testbench cũ trở
    nên sai mà không ai nhận ra cho tới khi thật sự chạy lại — `tb_mmu_core.v` đã âm
    thầm lỗi thời đúng kiểu này (mục -0.1.1). Sau bất kỳ lần nối 2 khối RTL đã có test
    riêng, nên tự hỏi lại: "testbench A còn đúng giả định gì về khối B mà giờ đã đổi?"
    thay vì chỉ tin PASS cũ.
17. **Immediate 12-bit của ADDI/CSRRWI-style bị sign-extend — bẫy dễ gặp lại khi hand-
    assemble thêm chương trình test sau này** (mục -0.1.2): bất kỳ giá trị immediate
    nào có bit 11 = 1 (tức >= 0x800 khi coi là dương) sẽ bị nạp thành số ÂM
    (sign-extend), không phải giá trị dương như "nhìn mặt chữ". Gặp đúng 2 lần trong
    cùng 1 lần viết chương trình (`0x800` để dựng `mstatus.MPP`, marker `0x999`) — cả
    2 đều bắt được bằng trace tay TRƯỚC KHI chạy, không phải bằng simulator. Cách né:
    hoặc giữ mọi immediate trong khoảng an toàn `0x000-0x7FF`, hoặc dựng giá trị qua
    `ADDI` (giá trị nhỏ, an toàn) + `SLLI` (dịch bit trên thanh ghi, không qua đường
    sign-extend của immediate) khi cần bit cao hơn.
18. **`sim/tb_csr_priv.v` (M/S/U + `medeleg`, mục -0.1.2) chưa chạy qua Vivado** — cùng
    trạng thái như mọi testbench khác trong repo: chỉ tự kiểm tra tĩnh + trace tay,
    chưa có xác nhận từ simulator thật.
19. **Kế hoạch bootloader SD/SPI ban đầu (tự bit-bang giao thức SD ở PL) KHÔNG áp dụng
    được cho Genesys ZU-5EV** — SD card nối qua PS, không nối qua PL (mục -0.05.1). Nếu
    có ghi chú/ý tưởng nào từ trước phiên này còn nhắc "dùng `axi_quad_spi` để tự đọc SD
    card từ RISC-V", đó là kế hoạch đã bị thay thế — kiến trúc đúng là PS-mediated (mục
    -0.05.1-.05.2). Kế hoạch SPI-bit-banging ban đầu vẫn còn giá trị, nhưng CHỈ cho
    VCU129 (mục -0.05.8), và CHỈ sau khi xác nhận (1) có khe SD, (2) SD nối tới chân PL.
20. **PASS/FAIL tự động đi qua `boot_ctrl`'s `REG_RESULT` + console UART của PS, KHÔNG
    qua `axi_uartlite` (uart0)** — lý do ở mục -0.05.3 (không chắc `axi_uartlite`'s chân
    vật lý có đường ra ngoài nào không). `uart0` vẫn được nối trong
    `build_soc_zu5ev_boot.tcl` như ngoại vi phụ/debug — đừng nhầm nó là đường PASS/FAIL
    chính khi đọc lại script sau này.
21. **`constraints/*_template.xdc` (2 file, mục -0.05.7) KHÔNG có số chân/PACKAGE_PIN/
    IOSTANDARD thật** — mọi giá trị đều là placeholder `<FILL_ME...>`, cố ý để trống vì
    không trích xuất được PDF schematic/reference-manual thật trong phiên này (lỗi công
    cụ đọc PDF, không phải không tồn tại). **Tuyệt đối không tự điền số chân đoán chừng**
    trước khi build thật — đặc biệt IOSTANDARD/điện áp sai có thể làm hỏng board thật,
    không chỉ đơn giản là không chạy được. Lấy số chân thật từ chính nguồn đã ghi trong
    từng file template (schematic/reference-manual Digilent cho ZU-5EV, UG1318 của AMD
    cho VCU129).
22. **`build_soc_zu5ev_boot.tcl` chưa chạy qua Vivado thật** (không có Vivado trong môi
    trường này) — phần PS bring-up (`apply_bd_automation` cho `zynq_ultra_ps_e`) và toàn
    bộ clock/reset đặc biệt có khả năng cần sửa tay cao hơn 2 script trước, vì cú pháp/
    tên rule/tên pin của PS đã đổi qua nhiều bản Vivado (xem "Ghi chú trung thực" ở mục
    -0.05.4). Đọc kỹ mọi WARNING khi chạy lần đầu, đừng chạy lại mù nếu có lỗi.
23. **`quad_core_axi_wrapper_ahb.v`/`quad_core_axi_wrapper_ahb_bootable.v` (mục -0.02.2)
    là file mới, chưa mô phỏng** — về mặt cấu trúc là bản copy port-for-port của
    `quad_core_axi_wrapper.v`/`quad_core_axi_wrapper_bootable.v` (đã đối chiếu port 100%
    với cả `quad_core_soc_ahb.v` lẫn `boot_ctrl.v`), chỉ đổi module con được instantiate
    — rủi ro sai sót thấp hơn RTL logic mới hoàn toàn, nhưng vẫn chưa có xác nhận từ
    simulator thật, giữ nguyên nguyên tắc "chưa test = chưa biết, không phải đã đúng".
24. **2 script (`build_soc_4core_trial.tcl`, `build_soc_zu5ev_boot.tcl`) giờ mặc định
    dùng bản AHB-Lite (`quad_core_axi_wrapper_ahb[_bootable]`)** — nếu có ghi chú/lệnh
    chạy nào từ phiên trước còn ghi "cpu0 = quad_core_axi_wrapper" (không có `_ahb`),
    đó là hành vi CŨ, đã đổi theo quyết định kiến trúc mới (mục 4, mục -0.02.2). Cả 2
    bản RTL (dây nối trực tiếp và AHB-Lite) vẫn cùng tồn tại trong repo, không xoá —
    chỉ có bản nào được 2 script này INSTANTIATE là đổi.
25. **L1/L2 đã đổi kích thước (32KB I$/D$, 512KB L2) — nếu có sóng mô phỏng/log cũ từ
    trước phiên này**, những con số địa chỉ index/tag suy ra từ đó (8-bit/11-bit index)
    không còn đúng với RTL hiện tại (giờ 9-bit/12-bit) — đừng dùng lại số cũ khi đối
    chiếu waveform mới với ghi chú cũ.
