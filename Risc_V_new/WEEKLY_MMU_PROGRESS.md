# Báo cáo tiến độ MMU: tuần trước và tuần này

## 1. Thông điệp chính nên trình bày

Tuần trước, MMU đã chạy được luồng dịch địa chỉ Sv32 cơ bản và các ca quyền truy cập
phổ biến. Tuần này, phần cải thiện không nằm ở việc “thêm một MMU khác”, mà ở việc
đóng các lỗi góc khiến MMU có thể trả kết quả cũ, cập nhật PTE không an toàn hoặc
treo/sai loại exception khi tích hợp với cache và bus đa lõi.

Kết quả hiện tại nên tách thành hai con số:

- **Nhóm MMU trực tiếp: 9/9 test PASS**.
- **Regression rộng của RTL: 21/21 test PASS**. Lỗi cuối ở đường
  CSR privilege/delegation đã được sửa: ECALL/EBREAK không còn bị decode nhầm như
  truy cập CSR bất hợp lệ. Không nên công bố “hệ thống hoàn thiện 100%” cho đến khi
  có kết quả Vivado synthesis/implementation và FPGA.

## 2. So sánh tuần trước – tuần này

| Nội dung | Mốc tuần trước | Kết quả tuần này | Bằng chứng |
|---|---|---|---|
| Sv32 cơ bản | Dịch 4 KiB, TLB hit/miss, page walk | Giữ nguyên và chạy regression lại | `tb_mmu_core`, `tb_mmu_upgrade` |
| Quyền truy cập | Có R/W/X và U/S cơ bản | Bổ sung/khóa SUM, MXR, execute-only, superpage 4 MiB, PTE reserved/misaligned | `tb_mmu_advanced`, `tb_csr_mmu_bits` |
| TLB | Có iTLB/dTLB | 16 entry 4-set × 4-way mỗi phía + 4 entry superpage; flush cả hai loại | `tb_mmu_advanced` |
| `SFENCE.VMA` | Flush ở trạng thái yên | Flush đến giữa PTE read/A-D write được giữ lại; response cũ bị discard và walk lại | `tb_mmu_sfence` |
| Đổi context | Chưa khóa đầy đủ giao dịch đang chạy | Đổi `satp`, enable, privilege, SUM/MXR không cho stale refill/stale fault | `tb_mmu_context` |
| A/D bit | Có cập nhật A/D | Đường cache/coherence dùng `AMOOR.W`, tránh full-word write ghi đè PTE mới từ lõi khác | `tb_mmu_core` |
| Lỗi memory/bus | Chưa phân loại end-to-end | Lỗi đọc/ghi page table thành access fault cause 1/5/7; không refill TLB | `tb_mmu_bus_error`, `tb_csr_access_fault` |
| Debug | Quan sát tín hiệu thủ công | Debug buffer tùy chọn + watchdog sticky; board build có thể loại buffer | `mmu_debug_buffer.v`, `tb_mmu_context` |
| Cache/coherence liên quan | Chưa chứng minh error sideband đầy đủ | Response lỗi không allocate I$/D$/L2; giữ dirty victim để retry | `tb_cache_error_path`, `tb_coherence_error`, `tb_ahb_error_sideband` |

## 3. Script nói 4–5 phút

**Mở đầu (30 giây).**  
“Mục tiêu tuần này của em không chỉ là làm MMU chạy ở trường hợp bình thường, mà
là làm kết quả dịch địa chỉ còn đúng khi có flush, đổi address space và lỗi bus —
đặc biệt trong hệ thống nhiều lõi có cache coherence.”

**Kiến trúc (45 giây).**  
“Mỗi lõi có iTLB và dTLB riêng, mỗi TLB 16 entry tổ chức 4 set × 4 way, cộng thêm
4 entry superpage. Khi hit hợp lệ, VA được đổi trực tiếp sang PA. Khi miss hoặc PTE
thiếu Accessed/Dirty, yêu cầu đi vào PTW Sv32 hai cấp dùng chung cho instruction và
data. PTW kiểm tra U/S, SUM, MXR, R/W/X, page 4 KiB và superpage 4 MiB.”

**FSM (60 giây).**  
“FSM ngoài có ba trạng thái. IDLE lookup TLB và kiểm tra quyền. WALK giữ context
của yêu cầu và cho PTW chiếm bus. GATE phát fault hoặc resume đúng một chu kỳ. Điểm
mới là nếu `SFENCE.VMA` hay `satp`/privilege thay đổi lúc WALK, response cũ không
được refill; nó bị discard rồi địa chỉ được đánh giá lại. FSM PTW đọc PTE cấp 1,
có thể đi xuống cấp 0, và chỉ sang AD_WRITE nếu cần set A/D. TLB chỉ refill sau khi
ghi A/D thành công.”

**Cải thiện quan trọng (75 giây).**  
“Thứ nhất, em đã khóa stale refill khi flush hoặc đổi context giữa page walk. Thứ
hai, cập nhật A/D qua cache được đổi thành atomic OR, giảm nguy cơ hai lõi ghi đè
PTE của nhau. Thứ ba, lỗi AXI/AHB trong lúc fetch, load, store hay page walk được
phân biệt thành access fault cause 1, 5, 7 và không đưa dữ liệu lỗi vào TLB/cache.
Thứ tư, em thêm watchdog và buffer trace tùy chọn để debug; buffer có thể tắt khi
nạp board nên không bắt buộc tiêu tốn tài nguyên bản release.”

**Kết quả (45 giây).**  
“Nhóm test trực tiếp cho MMU hiện đạt 9/9 PASS. Nếu tính toàn bộ regression cache,
coherence và CSR liên quan thì đạt 21/21. Lỗi cuối trước đây nằm ở decode SYSTEM:
ECALL/EBREAK bị đưa nhầm qua kiểm tra địa chỉ CSR và thành cause 2. Sau khi chỉ bật
CSR cho `funct3 != 0`, ECALL từ U delegate đúng sang S với cause 8, còn EBREAK không
delegate đi M với cause 3.”

**Kết thúc (30 giây).**  
“Bước tiếp theo là chạy cùng regression trên Vivado XSIM, sau đó
synthesis/implementation để lấy LUT, FF, BRAM, timing và thử fault
injection trên FPGA. Hiện tại em mới khẳng định correctness ở mức RTL simulation,
chưa khẳng định timing closure hoặc board end-to-end.”

## 4. Hình nên đưa lên slide

1. Kiến trúc MMU: `Risc_V/docs/architecture/mmu.svg`.
2. FSM điều phối: `Risc_V/docs/architecture/mmu_control_fsm.svg`.
3. FSM PTW: `Risc_V/docs/architecture/mmu_ptw_fsm.svg`.
4. Nếu cần nói về yêu cầu của thầy “core B đọc dữ liệu core A vừa ghi”, dùng
   `Risc_V/docs/architecture/cache_coherence.svg`, nhưng nói rõ đây là đường
   cache/coherence bao quanh MMU, không phải chức năng của MMU đơn lẻ.

Mỗi slide chỉ nên có một thông điệp. Ở slide kết quả, chụp `summary.md` hoặc console
có dòng `MMU RESULT: 9/9 PASS`, và mở một waveform đại diện cho ca khó
`SFENCE.VMA during PTW`: `flush_pending` lên, response cũ về nhưng không có TLB
refill, sau đó PTW request mới được phát.

## 5. Cách tạo bằng chứng trước buổi báo cáo

Mở **Questa Command Prompt**, rồi chạy:

```powershell
cd C:\Users\ADMIN\Documents\GitHub\KLTN\Risc_V_new\Risc_V
powershell -ExecutionPolicy Bypass -File .\scripts\run_mmu_progress_demo.ps1
```

Script tạo thư mục timestamp dưới `Risc_V/reports/`, gồm:

- `summary.md`: bảng kết quả để chụp hoặc đưa vào phụ lục;
- `summary.csv`: dữ liệu để làm bảng;
- `compile-*.log`, `run-*.log`: bằng chứng chi tiết có thể truy lại.

Để xem waveform của ca đại diện, compile như script rồi chạy GUI:

```tcl
vsim work.tb_mmu_sfence
add wave -r /tb_mmu_sfence/dut/*
run -all
```

Các tín hiệu nên chỉ cho thầy: `state`, `flush`, `flush_pending`, `ptw_req_valid`,
`ptw_resp_valid`, `ptw_resp_fault`, `itlb_refill_en`, `dtlb_refill_en`, `busy` và
`fetch_fault/mem_fault`. Nếu tên nội bộ khác do optimization, chạy `vsim -voptargs=+acc`.

## 6. Điều không nên khẳng định

- Chưa nói “đã chạy trên FPGA” khi chưa có implementation report và log board.
- Phân biệt rõ nhóm MMU trực tiếp 9/9 và regression RTL toàn hệ thống 21/21.
- Không nói watchdog tự recovery bus treo; hiện nó chỉ latch lỗi để debug.
- Không nói AXI trực tiếp đã có atomic A/D; atomic OR hiện được đóng ở đường
  L1 D-cache/coherence.
- Không nói DMA đã coherent; DMA vẫn cần quy trình flush/invalidate.

## 7. Chạy lại bằng Vivado XSIM

Trong Vivado, mở project `Risc_V/Risc_V.xpr`, chọn **Window → Tcl Console** và chạy:

```tcl
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_mmu_progress_xsim.tcl}
```

Script dùng `xvlog`, `xelab` và `xsim -R`, vì vậy mỗi test chạy đến `$finish` thay
vì bị cắt ở `1000 ns`. Nó không đổi simulation top của `sim_1`; kết quả được tạo
trong thư mục `Risc_V/reports/xsim-mmu-<timestamp>/summary.md`.

Kết quả mong đợi là:

```text
=== XSIM MMU RESULT: 9/9 PASS ===
```

Nếu chạy thủ công bằng GUI, cần đặt đúng testbench làm **Simulation Top**, chọn
**Run Behavioral Simulation**, sau đó dùng **Run All**. Riêng `tb_mmu_core` kết thúc
khoảng 20 micro giây nên `run 1000ns` là chưa đủ và không được tính là FAIL.
