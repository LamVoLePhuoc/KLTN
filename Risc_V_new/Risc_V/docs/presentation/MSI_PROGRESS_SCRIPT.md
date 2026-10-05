# Kịch bản trình bày tiến độ cache coherence MSI

Thời lượng mục tiêu: 10–12 phút. Đối tượng: giảng viên hướng dẫn hoặc hội đồng có
kiến thức về kiến trúc máy tính và RTL.

## Slide 1 — Tiến độ cache coherence MSI

**Thời lượng:** 40 giây

> Phần em trình bày hôm nay là tiến độ thiết kế cache coherence MSI cho hệ thống
> RISC-V RV32IMA bốn lõi. Mục tiêu của khối này là bảo đảm bốn D-cache riêng không
> quan sát dữ liệu cũ khi nhiều lõi cùng truy cập một cache line. Ở thời điểm hiện
> tại, chức năng MSI blocking đã hoàn thiện ở mức RTL và toàn bộ regression hiện có
> đạt 26 trên 26 test PASS bằng QuestaSim. Phần chưa hoàn tất chủ yếu nằm ở xác minh
> Vivado, timing và chạy trên FPGA thật.

Điểm cần nhấn mạnh: nói rõ “hoàn thiện ở mức RTL”, không nói “hoàn thiện toàn bộ hệ
thống” vì chưa có synthesis và kết quả trên board.

## Slide 2 — Lý do chọn MSI

**Thời lượng:** 70 giây

> Khi mỗi lõi có D-cache riêng, một địa chỉ có thể tồn tại đồng thời trong nhiều
> cache. Nếu một lõi ghi mà các bản sao khác không bị vô hiệu, các lõi còn lại có
> thể đọc dữ liệu cũ. Vì vậy hệ thống cần một giao thức coherence.
>
> Ban đầu em xem xét MESI, nhưng kiến trúc hiện tại dùng directory tập trung và
> coherence manager tuần tự hóa giao dịch. Em chuyển sang MSI để bỏ trạng thái
> Exclusive và loại bỏ chuyển trạng thái E sang M âm thầm. Trong MSI, mọi lần ghi
> từ Shared lên Modified đều phát RFO, vì vậy coherence manager luôn nhìn thấy thay
> đổi quyền sở hữu và có thể invalidate các sharer còn lại.
>
> Đổi lại, MSI có thể phát thêm RFO đối với dữ liệu chỉ một lõi sử dụng. Đây là
> đánh đổi hiệu năng để lấy FSM đơn giản hơn và dễ chứng minh tính đúng đắn hơn cho
> phạm vi khóa luận.

Nếu bị hỏi “tại sao không giữ MESI?”, trả lời: MESI tối ưu read-private bằng E nhưng
đòi hỏi directory theo dõi và xử lý silent E→M chính xác; bản blocking hiện tại ưu
tiên correctness và khả năng kiểm chứng.

## Slide 3 — Kiến trúc cache/coherence bốn lõi

**Thời lượng:** 70 giây

> Mỗi lõi có I-cache 32 KB và D-cache 32 KB riêng. Chỉ D-cache tham gia MSI. Bốn
> cặp cổng instruction và data tạo thành tám nguồn request đi vào bộ phân xử
> round-robin. Coherence manager quản lý directory sharer theo từng line, phát snoop
> invalidate hoặc downgrade và điều phối một giao dịch nguyên tử tại một thời điểm.
>
> Bên dưới là L2 dùng chung 512 KB, bốn way, cache line 32 byte và inclusive với
> D-cache. Tính inclusive cho phép directory của L2 biết những lõi nào đang giữ
> line. L2 kết nối ra external memory qua đường AXI4 32 bit.
>
> I-cache không tham gia snoop để giảm độ phức tạp. Tính đúng đắn cho mã tự sửa được
> bảo đảm bằng FENCE.I: hệ thống clean D-cache trước rồi mới invalidate I-cache.

## Slide 4 — FSM trạng thái của một D-cache line

**Thời lượng:** 90 giây

> Mỗi line có đúng ba trạng thái. Invalid nghĩa là line không sử dụng được. Shared
> nghĩa là line sạch và có thể tồn tại ở nhiều lõi. Modified nghĩa là lõi này giữ
> bản mới nhất và có thể chưa ghi xuống memory.
>
> Từ Invalid, read miss phát BusRd và fill vào Shared. Write miss phát RFO, lấy
> quyền sở hữu rồi fill thẳng vào Modified. Khi line đang Shared và CPU ghi, cache
> không được đổi trạng thái cục bộ ngay mà phải phát RFO để invalidate các sharer,
> sau đó mới lên Modified.
>
> Khi một lõi khác đọc line đang Modified, owner forward dữ liệu bẩn và hạ từ M
> xuống S. Khi lõi khác xin ghi, owner cung cấp dữ liệu nếu cần rồi line bị
> invalidate. Eviction hoặc cache flush của line Modified phải writeback toàn bộ
> 32 byte trước khi chuyển về Invalid.

## Slide 5 — Remote read khi owner đang Modified

**Thời lượng:** 70 giây

> Ví dụ core 0 đã ghi line A và đang giữ trạng thái Modified. Core 1 phát read miss
> cho cùng line. Coherence manager lookup L2 directory, thấy core 0 là sharer duy
> nhất và gửi snoop downgrade. Core 0 trả về line cùng cờ dirty, đồng thời hạ trạng
> thái M xuống S. Manager cập nhật dữ liệu mới nhất vào L2 và thêm core 1 vào
> sharer bitmap. Sau response, core 0 và core 1 đều ở Shared và cùng quan sát đúng
> dữ liệu mới nhất.
>
> Điểm quan trọng là manager không đọc lại dữ liệu cũ từ DRAM trong trường hợp này.
> Testbench có counter để xác nhận remote read nhận dữ liệu từ owner/L2 mà số lần
> đọc DRAM không tăng.

## Slide 6 — Ghi và chuyển quyền sở hữu bằng RFO

**Thời lượng:** 70 giây

> Khi một core muốn ghi nhưng line chưa ở Modified, nó phát RFO. Coherence manager
> dùng directory để tạo danh sách các sharer khác và gửi invalidate lần lượt. Nếu
> một sharer giữ bản Modified, snoop response mang theo dirty line để manager không
> làm mất dữ liệu mới nhất. Khi mọi invalidate hoàn tất, directory chỉ giữ bit của
> requester, L2 được cập nhật và requester nhận quyền M. Từ thời điểm đó, các lần
> ghi tiếp theo trên cùng line là hit cục bộ cho đến khi có snoop hoặc eviction.
>
> Cơ chế này cũng xử lý false sharing: hai core ghi hai word khác nhau trong cùng
> line vẫn phải chuyển ownership, nhưng dữ liệu của các word không bị ghi đè vì
> toàn bộ line mới nhất luôn được chuyển giao.

## Slide 7 — FSM giao dịch của coherence manager

**Thời lượng:** 80 giây

> Coherence manager là blocking và chỉ có một giao dịch toàn hệ thống tại một thời
> điểm. Từ IDLE, bộ phân xử round-robin chọn một trong tám nguồn. Manager lookup L2,
> sau đó rẽ nhánh tùy hit, miss, RFO hoặc writeback. Nếu line có sharer, manager
> phát snoop và chờ từng acknowledge. Nếu miss cần thay victim, manager snoop các
> sharer của victim và writeback dirty data trước khi fetch line mới từ memory.
> Cuối cùng manager cập nhật L2 cùng directory, trả response và chờ requester hạ
> valid trước khi quay lại IDLE.
>
> Đường lỗi có trạng thái restore riêng. Nếu external writeback lỗi sau khi các bản
> sao L1 đã bị invalidate, manager ghi trả victim authoritative vào L2 ở trạng thái
> dirty thay vì làm mất dữ liệu.

## Slide 8 — Phần đã hoàn thiện

**Thời lượng:** 70 giây

> Phần chức năng đã đóng gồm FSM I/S/M, directory sharer inclusive, owner forwarding,
> dirty eviction và full-line writeback. Arbiter round-robin phục vụ tám nguồn mà
> không starvation trong mô hình blocking.
>
> Các lệnh RV32A cũng đi qua coherence. AMO dùng RFO trước read-modify-write. LR/SC
> theo dõi reservation theo địa chỉ vật lý và snoop invalidate sẽ hủy reservation.
> FENCE.I thực hiện clean D-cache rồi invalidate I-cache. Vùng MMIO đi đường
> uncached và không allocate vào directory. RFO qua AHB được giữ bằng HMASTLOCK.
>
> Ngoài ra hệ thống đã có error sideband, watchdog, cache-maintenance handshake và
> thanh ghi AXI-Lite để PS thực hiện flush trước và sau DMA.

## Slide 9 — Bằng chứng kiểm chứng

**Thời lượng:** 80 giây

> Regression hiện tại có 26 testbench tự kiểm và tất cả đều PASS bằng QuestaSim.
> Riêng cache/coherence đã kiểm tra read miss, S lên M, owner forwarding, nhiều
> sharer, false sharing, eviction L1/L2, AMO, LR/SC, FENCE.I, AHB, uncached và các
> đường lỗi.
>
> Test MSI còn chạy một chuỗi pseudo-random tái lập gồm 160 giao dịch đọc, ghi và
> chuyển ownership trên bốn lõi, xen kẽ flush. Sau chuỗi này, test đọc lại 64 word
> từ các core khác nhau và so sánh với scoreboard độc lập. Các cờ protocol error,
> timeout và memory error đều phải sạch ở đường bình thường.
>
> Kết quả này chứng minh tính đúng đắn trong phạm vi RTL simulation đã kiểm tra,
> nhưng chưa thay thế formal verification, synthesis hoặc thử nghiệm FPGA.

## Slide 10 — Giới hạn và kế hoạch tiếp theo

**Thời lượng:** 70 giây

> Giới hạn lớn nhất hiện nay là coherence manager blocking nên throughput sẽ giảm
> khi contention cao. DMA chưa phải MSI master theo từng line; hệ thống hiện dùng
> protocol coarse-grain: quiesce buffer, cache maintenance, DMA, rồi maintenance
> lần nữa trước khi CPU đọc. I-cache không snoop và phụ thuộc vào FENCE.I.
>
> Công việc tiếp theo theo thứ tự ưu tiên là chạy XSIM để đối chiếu simulator, sau
> đó synthesis và implementation để lấy LUT, FF, BRAM và timing. Khi có board,
> cần chứng minh luồng SD–DRAM–CPU–SD và fault injection trên memory bus. Formal
> properties và non-blocking MSI là phần mở rộng sau khi bản blocking đã được khóa
> trên phần cứng.

## Slide 11 — Kết luận và câu hỏi phản biện

**Thời lượng:** 50 giây

> Em chốt lại ba ý. Thứ nhất, MSI blocking đã hoàn thiện về chức năng ở mức RTL và
> regression đạt 26 trên 26 PASS. Thứ hai, chuyển từ MESI sang MSI là quyết định có
> chủ đích để mọi thay đổi ownership đều hiện ra dưới dạng RFO, giúp directory và
> kiểm chứng rõ ràng hơn. Thứ ba, phần còn lại tập trung vào bằng chứng phần cứng và
> hiệu năng, không phải các luồng coherence cơ bản.

### Câu hỏi thường gặp

**Vì sao read fill luôn là S dù chỉ có một core giữ line?**  
MSI không có E. Cách này loại bỏ silent E→M và buộc lần ghi sau đi qua RFO.

**Làm sao biết M owner không làm mất dirty data?**  
Snoop response trả cả cờ dirty và toàn bộ line. Manager cập nhật L2 trước khi grant
hoặc thay victim; test remote read và dirty eviction đối chiếu dữ liệu cuối.

**Nếu hai core cùng xin ghi thì sao?**  
Round-robin chọn một request. Giao dịch được tuần tự hóa, requester đầu tiên hoàn
tất invalidate và nhận M; request còn lại xử lý sau và phải chuyển ownership lại.

**26/26 PASS có nghĩa là hoàn thành chưa?**  
Hoàn thành chức năng RTL trong phạm vi test hiện tại. Chưa thể tuyên bố hoàn thành
toàn hệ thống trước khi có synthesis, timing và demo FPGA.

**Tại sao chưa làm non-blocking?**  
Non-blocking cần nhiều transaction ID, MSHR và xử lý race phức tạp. Bản blocking
phù hợp mục tiêu khóa luận là chứng minh correctness trước, rồi mới tối ưu throughput.

## Cách trình bày

- Không đọc toàn bộ chữ trên slide. Mỗi slide chỉ nhìn tiêu đề, chỉ vào luồng dữ
  liệu hoặc FSM rồi nói theo phần script.
- Khi nói “PASS”, luôn nêu môi trường: QuestaSim RTL simulation.
- Khi nói “hoàn thiện”, thêm phạm vi: chức năng MSI blocking ở mức RTL.
- Khi bị hỏi ngoài phạm vi, phân biệt rõ “đã có RTL”, “đã mô phỏng” và “đã xác minh
  trên FPGA”.
