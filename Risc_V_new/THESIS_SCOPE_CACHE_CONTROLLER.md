# Phạm vi khóa luận sau khi bỏ dịch địa chỉ

## Kết luận

Khóa luận tập trung vào bộ xử lý RV32IMA bốn lõi và hệ thống cache nhất quán.
Tên “MMU” trong sơ đồ chỉ khối **Cache/Memory Management Unit** dùng chung, gồm
phân xử request, điều khiển cache, coherence MSI và giao tiếp memory. Khóa luận
không còn tuyên bố hỗ trợ virtual memory, TLB hoặc Page Table Walker.

## Nội dung giữ lại

- Bốn core RV32IMA pipeline năm tầng.
- Mỗi core có L1 I-cache 32 KiB và L1 D-cache 32 KiB.
- AHB-Lite trong miền CPU/cache.
- Cache Controller (MMU) nhận tám nguồn I$/D$.
- Shared L2 512 KiB, 4-way và directory bốn core.
- MSI, dirty forwarding, invalidate/downgrade, write-back/write-allocate.
- CPU memory port sang AXI4, memory controller và DDR.
- DMA non-coherent với cache maintenance trước/sau transfer.
- Error handling, watchdog, trace buffer và performance counters.

## Nội dung bỏ khỏi hierarchy active

- `satp` làm nguồn điều khiển dịch địa chỉ.
- iTLB/dTLB và superpage TLB.
- Page Table Walker và cập nhật PTE A/D.
- page fault, `SFENCE.VMA`, SUM/MXR trong đường memory active.
- khái niệm VA/PA trong datapath. Mọi địa chỉ active là physical address 32 bit.

Source cũ không bị xóa để bảo toàn lịch sử nghiên cứu, nhưng không nằm trong
`rtl/files.f`, Vivado project hoặc regression mặc định.

## Đề cương cần sửa

Đề cương tháng 9 ghi “MMU/TLB” tại mục tiêu, nội dung tích hợp, phân công và kế
hoạch. Khi cập nhật slide/báo cáo, thay cụm này bằng:

> Cache/Memory Management Unit dùng chung, điều phối L1/L2 và bảo đảm nhất quán
> dữ liệu giữa bốn lõi bằng MSI.

Mục tiêu kỹ thuật nên đo bằng cache hit/miss, latency, snoop traffic, fairness,
memory traffic, speedup 1/2/4 core, LUT/FF/BRAM/DSP, Fmax và power.

## Trạng thái theo từng khối trong sơ đồ

| Khối | Hiện có | Nâng cấp còn cần |
|---|---|---|
| 4 core RV32IMA | Pipeline, CSR/trap, RV32M/A và wrapper cache | Chạy lại test active và workload 1/2/4 core |
| L1 I/D | Hit/miss, AMO, LR/SC, FENCE.I, maintenance | Đo hit rate/latency và kiểm tra sau implementation |
| Cache controller (MMU) | RR 8 nguồn, FSM blocking, MSI, dirty forward, watchdog/counters | Đóng regression active; cân nhắc queue một entry sau khi có số đo |
| Shared L2 | 512 KiB, 4-way, directory, dirty/refill/writeback | Pipeline đường đọc dài và chạy lại timing/resource |
| CMU | Chức năng coherence đang nằm trong `cache_controller_mmu` | Chỉ tách module vật lý nếu cần khớp hình, không đổi protocol |
| AHB/AXI4 | Adapter và wrapper RTL đã có | Regenerate block design, implementation và kiểm tra backpressure/error |
| DMA | Controller/testbench nguồn đã có, maintenance non-coherent | Ghép vào AXI fabric/DDR thật và chạy pre/post-flush end-to-end |
| DDR/SD/board | Script và boot-control skeleton | Thay BRAM stand-in bằng DDR, tạo bitstream và demo SD–DDR–CPU–SD |
| Debug | Trace buffer/counter có generate option | Bật khi mô phỏng/ILA, tắt buffer khỏi netlist board cuối |

## Thứ tự hoàn thiện

### Bắt buộc trước bảo vệ

1. Active RTL regression trên Questa và Vivado XSIM.
2. Chạy lại và lưu log test `tb_coherence.v` mục MSI C: A-write/B-read,
   đúng một dirty-owner forward, không đọc DRAM, L2 được cập nhật dirty và
   directory chuyển thành hai sharer.
3. Tích hợp DMA vào AXI fabric và xác nhận maintenance handshake.
4. Timing closure, ưu tiên pipeline L2 và đường snoop/controller dài.
5. Implementation/bitstream và workload trên board.
6. Bảng so sánh 1, 2 và 4 core trên cùng clock, chương trình và dữ liệu.

### Nên làm nếu còn thời gian

- Tách `coherence_management_unit` thành module riêng để khớp sơ đồ vật lý.
- Bật skid queue một entry và đo throughput trước/sau.
- Memory-map performance counters cho phần mềm đọc.
- Fault injection cho AXI/AHB, dirty eviction và DMA timeout.

### Không nên mở rộng ở giai đoạn này

- Khôi phục Sv32/TLB/PTW.
- Đổi MSI sang MESI/MOESI.
- DMA coherent phần cứng hoàn chỉnh.
- Non-blocking cache nhiều outstanding transaction.

Các mục này tăng mạnh phạm vi và rủi ro timing, trong khi chưa giải quyết các mốc
bắt buộc là tích hợp DDR/DMA, timing closure và demo FPGA.

