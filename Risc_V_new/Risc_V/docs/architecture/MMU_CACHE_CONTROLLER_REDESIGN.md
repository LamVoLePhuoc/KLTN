# Cải tiến MMU theo kiến trúc bộ điều khiển cache dùng chung

## 1. Kết luận sau khi đối chiếu góp ý và mã tham khảo

Khối `KLTN_Reference/KLTN/MMU/MMU.sv` không thực hiện dịch địa chỉ ảo theo
nghĩa MMU chuẩn. Nó ghép một I-cache, một D-cache và các FSM
`IDLE/WRITE_BACK/ALLOCATE/CPU_READ/CPU_WRITE`; vì vậy cách gọi "MMU" trong đồ
án tham khảo gần với **bộ điều khiển phân cấp cache/bộ nhớ** mà thầy mô tả.

Kiến trúc mới giữ hai chức năng riêng biệt:

- `mmu_top.v`: Address Translation Unit theo RISC-V Sv32, đặt theo từng core;
  khối này chứa iTLB, dTLB và PTW, biến VA thành PA và kiểm tra quyền truy cập.
- `cache_controller_mmu.v`: MMU theo cách gọi của thầy, dùng chung cho toàn bộ
  CPU 4 core; khối này điều phối L1, L2, coherence và CPU memory port.

Không loại bỏ Sv32 để thay bằng cache controller, vì hai khối giải quyết hai bài
toán khác nhau. Việc tách tên và ranh giới giúp sơ đồ đúng với lời thầy nhưng RTL
vẫn đúng đặc tả RISC-V.

## 2. Ranh giới RTL mới

```text
4 x (core + Sv32 ATU + private L1 I$/D$)
                  |
       request / response / snoop
                  v
       cache_controller_mmu  <---->  shared l2_cache 512 KiB
                  |
         CPU memory port (word handshake)
                  |
           AXI4 system wrapper
                  |
       memory controller / DDR / DMA / MMIO
```

`cache_controller_mmu` và `l2_cache` là hai instance đồng cấp trong
`quad_core_soc.v` và `quad_core_soc_ahb.v`. Controller phát lệnh lookup/write và
L2 trả về hit/miss, way, tag victim, dirty và sharer bitmap. Mảng tag/data không
nằm trong controller.

## 3. Các cải tiến so với MMU tham khảo

| Nội dung | Mã tham khảo | Kiến trúc đã sửa |
|---|---|---|
| Phạm vi | Một I-cache + một D-cache | 4 core, 4 I-cache và 4 D-cache |
| Phân xử | Không có phân xử đa core | Round-robin 8 nguồn, chống starvation |
| Đơn vị copy | Một line 256 bit nhưng interface/FSM còn đơn giản | Copy block 32 byte bằng 8 giao dịch word có handshake thật |
| L2 | Không có shared L2/directory hoàn chỉnh | L2 512 KiB, 4-way, directory sharer 4 bit |
| Nhất quán | Không có protocol đa core | MSI, snoop invalidate/downgrade, dirty owner forwarding |
| Thay thế | LRU 2-way cục bộ | L1 2-way và L2 4-way với victim per-set |
| Write policy | Write-back/write-allocate cơ bản | Write-back/write-allocate, dirty victim recovery khi memory lỗi |
| MMIO | Đi chung cache | Bypass L1/L2, single-word strongly ordered |
| Lỗi | Tổng hợp `fsm_error` | Error trả đúng requester, sticky memory/protocol/timeout diagnostics |
| Dịch địa chỉ | Không có TLB/PTW | Sv32 riêng theo core, PA mới đi vào cache hierarchy |

Các lỗi đáng chú ý của bản tham khảo không được mang sang gồm tự giữ giá trị
trong combinational block (`data_wdata = data_wdata`), chưa chốt đầy đủ context
request trong lúc miss, và interface ready chưa phân biệt request/response nhiều
chu kỳ.

## 4. Luồng điều khiển chính

1. Controller nhận tối đa tám yêu cầu miss/write-back: D$0..D$3 và I$0..I$3.
2. Round-robin chọn một yêu cầu; toàn bộ transaction được serialize để tránh hai
   giao dịch coherence cùng thay đổi một cache line.
3. Controller yêu cầu L2 lookup.
4. Nếu hit, controller snoop các sharer cần downgrade/invalidate rồi cập nhật
   directory và trả line/state cho L1.
5. Nếu miss, controller xử lý dirty victim (snoop và write-back nếu cần), đọc đủ
   tám word từ memory, fill L2 rồi cấp line cho requester.
6. Địa chỉ `0xC000_0000..0xFFFF_FFFF` đi qua nhánh uncached, không allocate L1/L2.
7. Requester giữ `valid` đến khi nhận response; controller chờ `valid` hạ trước
   khi nhận lại nguồn đó, tránh xử lý trùng một yêu cầu mức.

## 5. Ý nghĩa các nhóm tín hiệu theo lời thầy

- **Control từ L1:** `dreq_type`, `ireq_valid`, `dreq_valid`.
- **Địa chỉ:** `dreq_addr`, `ireq_addr`, `l2_cmd_addr_o`, `mem_addr`.
- **Data:** `dreq_line`, `dresp_line`, `l2_cmd_wdata_o`, `l2_resp_line_i`.
- **Trạng thái trả về:** `dresp_state` (MSI), `l2_resp_hit_i`, dirty/sharer/victim.
- **Điều khiển coherence:** `dsnoop_valid/type/addr` và `dsnoop_ack_*`.

Như vậy RTL có đúng các luồng địa chỉ, data, control và status mà thầy yêu cầu,
thay vì nối cache trực tiếp với RAM như một memory cục bộ.

## 6. DMA và giới hạn hiện tại

DMA nằm ngoài CPU wrapper trên AXI4 system bus. Nó hiện **không coherent** với L1;
phần mềm/boot controller phải chạy quy trình `Cache_Flush -> chờ Done -> kiểm tra
Error -> DMA -> maintenance sau DMA`. Controller không giả vờ DMA coherent.

Thiết kế hiện dùng chung một clock cho core/cache controller/L2. Chênh lệch clock
CPU và system bus mà thầy nêu phải được xử lý ở AXI clock converter/async FIFO của
tích hợp Vivado; không được nối hai miền clock trực tiếp chỉ bằng RTL handshake này.

## 7. Bằng chứng kiểm thử

`tb_coherence.v` dùng trực tiếp topology mới: bốn D-cache thật nối vào
`cache_controller_mmu`, còn `l2_cache` là instance đồng cấp. Test kiểm tra I→S,
S→M, M→S, M→I, bốn sharer, false sharing, dirty eviction L1/L2, full-cache flush,
round-robin đồng thời và AMO. Các test cũ vẫn có thể dùng `coherence_manager` với
L2 nội bộ nhờ chế độ tương thích `EXTERNAL_L2=0`.
