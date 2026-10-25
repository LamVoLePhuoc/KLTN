# Script báo cáo tiến độ MMU, cache controller và DMA

Thời lượng đề xuất: 8–10 phút. Ngày báo cáo: 25/10/2026.

## Slide 1 — Báo cáo tiến độ tuần

Em xin báo cáo tiến độ tuần từ ngày 19 đến 25 tháng 10 năm 2026. Phạm vi tuần này tập trung vào ba phần: làm rõ ranh giới giữa MMU dịch địa chỉ và bộ điều khiển cache, tổng hợp kết quả cache controller, và hoàn thiện DMA ở mức RTL. Kết quả mới nhất là testbench DMA end-to-end đã chạy PASS trên Vivado XSIM.

## Slide 2 — Hai chức năng từng được gọi chung là MMU

Điểm thay đổi quan trọng bắt đầu từ việc xem lại khái niệm MMU. Source tham khảo gọi khối ghép I-cache, D-cache và các FSM miss hoặc write-back là MMU. Khối đó gần với bộ điều khiển cache hơn là MMU theo kiến trúc RISC-V.

Vì hai chức năng giải quyết hai bài toán khác nhau, thiết kế mới tách chúng rõ ràng. `mmu_top` thực hiện Sv32 và tạo địa chỉ vật lý. `cache_controller_mmu` điều phối L1, L2, coherence và memory port cho bốn core.

## Slide 3 — Kiến trúc SoC hiện tại

Kiến trúc hiện tại gồm bốn core RV32IMA. Mỗi core có MMU Sv32 và L1 riêng. Các yêu cầu miss đi vào cache controller dùng chung, sau đó tới L2 512 KiB và cổng memory.

AHB-Lite nằm trong miền CPU và cache. AXI4 nằm ở ranh giới hệ thống để kết nối memory controller, DDR và các master ngoài như DMA. Cách tách này giúp mỗi khối có trách nhiệm rõ và dễ kiểm chứng độc lập.

## Slide 4 — MMU Sv32 và tổ chức TLB

Mỗi core có iTLB và dTLB riêng. TLB trang 4 KiB gồm 16 entry, tổ chức bốn set và bốn way, thay thế bằng tree-PLRU. Mỗi phía còn có bốn entry superpage 4 MiB.

Khi miss, PTW Sv32 đọc tối đa hai cấp PTE, kiểm tra quyền và cập nhật Accessed hoặc Dirty nếu cần. Thiết kế kiểm tra U/S, SUM, MXR và quyền R/W/X trên mỗi hit, không chỉ khi refill. Bộ XSIM dành riêng cho MMU hiện đạt 9/9 test PASS.

## Slide 5 — Các lỗi góc MMU đã được khóa

Cải tiến quan trọng của MMU nằm ở các trường hợp cạnh. Nếu SFENCE, `satp` hoặc ngữ cảnh đặc quyền thay đổi trong lúc PTW đang chạy, kết quả cũ bị discard và không được refill vào TLB.

Lỗi đọc PTE hoặc ghi A/D được chuyển thành access fault đúng loại, thay vì page fault. Trên đường cache và coherence, A/D được cập nhật bằng AMOOR.W để giảm nguy cơ một core ghi đè thay đổi PTE của core khác. Watchdog chỉ ghi nhận chẩn đoán, không tự tạo completion giả.

## Slide 6 — Cache controller dùng chung và MSI

Cache controller nhận tối đa tám nguồn miss hoặc write-back từ bốn I-cache và bốn D-cache. Bộ phân xử round-robin chọn requester, sau đó FSM tuần tự hóa transaction coherence.

Controller làm việc với L2 như một khối đồng cấp và dùng directory sharer bốn bit. MSI đã bao phủ các chuyển trạng thái I→S, S→M, M→S và M→I. Khi một core giữ dirty line ở M, controller yêu cầu owner forward dữ liệu trước khi downgrade hoặc invalidate.

## Slide 7 — Tối ưu L2 và ranh giới bus

L2 ban đầu dùng một mảng bất đồng bộ 4.194.304 bit. Vivado không thể xử lý biến lớn như vậy và synthesis kéo dài nhiều giờ. Phiên bản mới chia dữ liệu thành tám bank 32 bit, dùng truy cập đồng bộ và scrub sau reset.

Kết quả là full Block Design synthesis sạch. Tài nguyên gần nhất cho thấy LUT khoảng 71,81%, register 22,86%, BRAM 93,58% và DSP 12%. BRAM hiện là giới hạn chính. Timing 100 MHz vẫn chưa đạt, với WNS âm 5,308 ns.

AHB-Lite và AXI4 đều đã có nhưng đảm nhiệm hai ranh giới khác nhau. AHB phục vụ đường L1 đến cache controller. AXI4 wrapper đưa CPU memory port ra miền hệ thống. DMA có AXI4 master và AXI4-Lite register file, nhưng chưa được ghép vào AXI interconnect của Block Design.

## Slide 8 — DMA AXI4 và cache maintenance

DMA mới gồm register file AXI4-Lite, cache coordinator và AXI4 memcpy engine. Phần mềm ghi source, destination, length và start. Coordinator chỉ nhận lệnh khi `buffer_quiesced` đã lên, chạy pre-maintenance, cho DMA copy, rồi chạy post-maintenance.

Burst không vượt biên 4 KiB. Read error chặn write tương ứng. Write response error vẫn yêu cầu post-maintenance vì một phần dữ liệu có thể đã xuống memory. Watchdog vừa được sửa để đo thời gian không có tiến triển, thay vì giới hạn tổng thời gian của lệnh nhiều burst.

DMA không phải MSI snoop master. Phần mềm vẫn phải bảo đảm không core nào sử dụng buffer trong lúc DMA hoạt động.

## Slide 9 — Bằng chứng kiểm chứng hiện có

Kết quả hiện tại gồm 9/9 test MMU chạy PASS trên Vivado XSIM, regression nền 26/26 PASS, và DMA end-to-end PASS. Full Block Design nền cũng synthesis thành công.

Em không cộng các kết quả này thành một con số duy nhất vì chúng thuộc các mốc source khác nhau. Em cũng chưa tuyên bố DMA đã hoàn thành ở mức SoC hoặc FPGA, vì DMA chưa vào AXI fabric của Block Design và chưa chạy với DDR thật.

## Slide 10 — Mốc tiếp theo

Bước tiếp theo gồm năm mốc. Đầu tiên em tích hợp DMA vào AXI interconnect và cấp vùng địa chỉ AXI4-Lite. Sau đó em xác nhận cache handshake và clock domain. Em sẽ chạy synthesis lại vì BRAM đã dùng hơn 93%.

Tiếp theo là xử lý critical path để đạt timing. Mốc cuối là bitstream và workload CPU tạo dữ liệu nguồn, DMA copy qua DDR, rồi CPU kiểm tra dữ liệu đích.

Trong tuần này, kết luận an toàn là DMA đã PASS độc lập ở RTL. Công việc còn lại tập trung vào tích hợp toàn SoC, timing closure và kiểm thử board.

## Câu hỏi có thể được hỏi

### Tại sao không dùng MMU cũ?

MMU tham khảo chủ yếu là cache wrapper/controller, không có Sv32, TLB và PTW. Thiết kế mới giữ ý tưởng điều khiển cache nhưng đặt nó trong `cache_controller_mmu`, đồng thời giữ MMU Sv32 riêng để đúng kiến trúc RISC-V.

### DMA có coherent với bốn core không?

Không. DMA là non-coherent AXI master. Tính nhất quán được bảo đảm bằng quyền sở hữu buffer và cache maintenance trước/sau DMA.

### Tại sao write error vẫn cần post-flush?

AXI write error không chứng minh rằng toàn bộ write đều chưa xảy ra. Một phần destination có thể đã thay đổi, nên CPU phải loại bỏ các cache line cũ trước khi đọc lại.

### Watchdog có tự hủy giao dịch không?

Không. Khi chưa có cancel/drain protocol, tự trả done có thể để lại response muộn và làm hỏng lệnh tiếp theo. Watchdog chỉ ghi nhận lỗi và chờ giao dịch thực sự kết thúc.

### AHB và AXI đã có chưa?

AHB-Lite đã nằm trong miền CPU/cache và có test tích hợp. AXI4 wrapper của CPU đã nằm ở ranh giới hệ thống. DMA AXI4 đã PASS độc lập nhưng chưa được thêm vào AXI interconnect của Block Design.
