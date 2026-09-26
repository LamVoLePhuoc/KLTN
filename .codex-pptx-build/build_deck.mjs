import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const workspaceDir = "C:/Users/ADMIN/Documents/GitHub/KLTN";
const buildDir = path.join(workspaceDir, ".codex-pptx-build");
const outDir = path.join(workspaceDir, "output");
const skillDir = "C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.921.10847/skills/presentations";
const runtimePython = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
const finalPath = path.join(outDir, "KLTN_QuadCore_RV32IMA_ToanBoKienTruc_v2.pptx");
const diagramDir = path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture");

const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href);
await fs.mkdir(buildDir, { recursive: true });
await fs.mkdir(outDir, { recursive: true });

const p = Presentation.create({ slideSize: { width: 1280, height: 720 } });
const FONT = "Segoe UI";
const C = { bg: "#F7FAFC", ink: "#102A43", navy: "#173F5F", blue: "#20639B", cyan: "#3CAEA3", orange: "#ED553B", gold: "#F6D55C", pale: "#E8F1F5", white: "#FFFFFF", gray: "#627D98", green: "#16856B", red: "#C43D3D" };

function rect(slide, x, y, w, h, fill, line = fill, radius = "roundRect") {
  return slide.shapes.add({ geometry: radius, position: { left: x, top: y, width: w, height: h }, fill, line: { fill: line, width: 2 } });
}
function txt(slide, x, y, w, h, value, size = 24, color = C.ink, bold = false, align = "left") {
  const s = slide.shapes.add({ geometry: "textbox", position: { left: x, top: y, width: w, height: h }, fill: "none", line: { fill: "none", width: 0 } });
  s.text = value;
  s.text.style = { typeface: FONT, fontSize: size, color, bold, autoFit: "shrink", textAlign: align, verticalAlignment: "middle" };
  return s;
}
function title(slide, value, subtitle = "") {
  txt(slide, 58, 35, 1160, 55, value, 34, C.navy, true);
  if (subtitle) txt(slide, 60, 91, 1150, 34, subtitle, 18, C.gray, false);
  rect(slide, 60, 126, 105, 5, C.orange, C.orange, "rect");
}
function footer(slide, n) {
  txt(slide, 60, 681, 930, 22, "Thiết kế bộ vi xử lý 4 lõi RISC-V RV32IMA", 13, C.gray);
  txt(slide, 1170, 679, 50, 22, String(n).padStart(2, "0"), 14, C.gray, true, "right");
}
function bullets(slide, x, y, w, items, size = 22, color = C.ink, gap = 52) {
  items.forEach((item, i) => {
    rect(slide, x, y + i * gap + 10, 10, 10, i === 0 ? C.orange : C.cyan, i === 0 ? C.orange : C.cyan, "ellipse");
    txt(slide, x + 24, y + i * gap, w - 24, gap, item, size, color, false);
  });
}
async function image(slide, filename, x, y, w, h, alt) {
  const data = await fs.readFile(path.join(diagramDir, filename));
  slide.images.add({ blob: new Uint8Array(data), contentType: "image/png", alt, fit: "contain", position: { left: x, top: y, width: w, height: h } });
}
function notes(slide, text) {
  slide.speakerNotes.textFrame.setText(text);
  slide.speakerNotes.setVisible(true);
}
function newSlide(bg = C.bg) {
  const s = p.slides.add();
  s.background.fill = bg;
  return s;
}

// 1 Cover
{
  const s = newSlide(C.navy);
  rect(s, 0, 0, 1280, 720, C.navy, C.navy, "rect");
  rect(s, 70, 92, 12, 440, C.orange, C.orange, "rect");
  txt(s, 110, 102, 1010, 80, "THIẾT KẾ BỘ VI XỬ LÝ 4 LÕI RISC-V", 42, C.white, true);
  txt(s, 110, 180, 1000, 62, "Dựa trên kiến trúc tập lệnh RV32IMA", 30, "#D9EAF2", false);
  txt(s, 110, 300, 900, 100, "Kiến trúc RTL, MMU/TLB, cache coherence MSI, AHB-Lite, AXI4 và định hướng hiện thực FPGA", 26, C.white, false);
  txt(s, 110, 525, 970, 70, "Vũ Thành Lam - 23520840\nVõ Lê Phước Lâm - 23520838", 22, C.white, true);
  txt(s, 110, 625, 800, 32, "Giảng viên hướng dẫn: TS. Nguyễn Minh Sơn", 19, "#D9EAF2");
  notes(s, "Mở đầu bằng mục tiêu của đề tài: xây dựng một hệ thống xử lý bốn lõi có đầy đủ đường xử lý, quản lý bộ nhớ, cache coherence và giao tiếp hệ thống. Người nghe đã biết logic số, HDL và SoC, vì vậy phần trình bày tập trung vào ranh giới block, luồng dữ liệu và các quyết định thiết kế.\nNguồn: đề cương KLTN và Risc_V_new/README.md.");
}

// 2 Motivation
{
  const s = newSlide(); title(s, "Bài toán xử lý đồng thời trong hệ thống nhúng", "Ví dụ định hướng: máy tính bay UAV");
  txt(s, 70, 165, 500, 78, "Một bộ xử lý phải phục vụ nhiều luồng thời gian thực", 30, C.navy, true);
  bullets(s, 78, 260, 500, ["Thu nhận và lọc dữ liệu cảm biến", "Điều khiển bay và ước lượng trạng thái", "Telemetry, logging và giao tiếp ngoại vi", "Tác vụ song song cần chia sẻ dữ liệu đúng"], 22, C.ink, 67);
  rect(s, 660, 165, 500, 410, C.white, C.blue);
  txt(s, 715, 190, 390, 50, "Phân chia tải theo lõi", 27, C.navy, true, "center");
  [["Core 0","Sensor fusion"],["Core 1","Control loop"],["Core 2","Navigation"],["Core 3","Telemetry / logging"]].forEach((a,i)=>{
    rect(s, 710, 270+i*68, 155, 50, i===0?C.orange:C.pale, i===0?C.orange:C.blue);
    txt(s, 710, 270+i*68, 155, 50, a[0], 20, i===0?C.white:C.ink, true, "center");
    txt(s, 890, 270+i*68, 220, 50, a[1], 19, C.ink, false);
  });
  txt(s, 700, 525, 410, 38, "RV32A + coherence bảo vệ dữ liệu dùng chung", 17, C.orange, true, "center");
  footer(s, 2); notes(s, "Điểm chính cần truyền đạt: đa lõi giải quyết khả năng thực thi đồng thời, nhưng đồng thời tạo ra bài toán chia sẻ bộ nhớ. RV32A cung cấp thao tác nguyên tử ở mức ISA. Cache coherence bảo đảm các lõi quan sát dữ liệu nhất quán.\nNguồn: 23520840_23520838_DeCuongKLTN.docx.");
}

// 3 Gap and goals
{
  const s = newSlide(); title(s, "Khoảng trống nghiên cứu và hai mục tiêu chính");
  txt(s, 72, 170, 510, 48, "Khoảng trống", 28, C.orange, true);
  bullets(s, 80, 230, 515, ["Các nền tảng trước chủ yếu dừng ở một hoặc hai lõi", "Cache nhiều cấp, MMU và coherence chưa được tích hợp trong cùng một hệ", "Kịch bản FPGA thường chưa chứng minh luồng nạp chương trình từ storage"], 21, C.ink, 82);
  rect(s, 620, 165, 560, 175, C.white, C.blue);
  txt(s, 650, 182, 500, 45, "Mục tiêu 1", 26, C.navy, true);
  txt(s, 650, 232, 500, 84, "Thiết kế hệ thống 4 lõi RV32IMA có MMU/TLB, L1/L2, MSI, AHB-Lite, AXI4 và DMA", 21, C.ink);
  rect(s, 620, 375, 560, 175, C.white, C.cyan);
  txt(s, 650, 392, 500, 45, "Mục tiêu 2", 26, C.navy, true);
  txt(s, 650, 442, 500, 84, "Mô phỏng RTL tự kiểm, tổng hợp, đánh giá tài nguyên và chạy kịch bản tự động trên FPGA", 21, C.ink);
  footer(s, 3); notes(s, "Không mô tả đề tài như một bản vá cho đề tài cũ. Hãy bắt đầu từ nhu cầu ứng dụng, sau đó dùng các công trình trước để định vị phạm vi đóng góp. Hai mục tiêu này khớp với đề cương đã chỉnh sửa.");
}

// 4 Scope
{
  const s = newSlide(); title(s, "Phạm vi và quyết định kiến trúc");
  const cols = [80, 455, 830];
  [
    ["ISA và lõi", ["RV32I + M + A", "Pipeline 5 tầng", "CSR, trap, M/S/U", "Không triển khai F, D, C"]],
    ["Bộ nhớ", ["MMU Sv32 theo từng lõi", "TLB 16 entry + superpage", "L1 I/D riêng, L2 dùng chung", "Coherence MSI blocking"]],
    ["Hệ thống", ["AHB-Lite phía core/L2", "AXI4 phía DRAM/DMA", "DMA chưa là coherence master", "FPGA end-to-end còn phải chứng minh"]]
  ].forEach((col,i)=>{
    txt(s, cols[i], 170, 300, 45, col[0], 25, i===1?C.cyan:C.navy, true);
    rect(s, cols[i], 224, 300, 5, i===1?C.cyan:C.orange, i===1?C.cyan:C.orange, "rect");
    bullets(s, cols[i], 250, 310, col[1], 20, C.ink, 68);
  });
  txt(s, 80, 595, 1080, 42, "Ưu tiên correctness và khả năng kiểm chứng trước throughput", 25, C.orange, true, "center");
  footer(s, 4); notes(s, "Nhấn mạnh các giới hạn để tránh người nghe hiểu nhầm đây là một CPU thương mại hoàn chỉnh. Coherence manager hiện tuần tự hóa một transaction toàn hệ thống. Thiết kế chọn độ đơn giản để có thể kiểm chứng trong phạm vi khóa luận.\nNguồn: Risc_V_new/README.md mục -1.7.3.");
}

// 5 System overview
{
  const s = newSlide(); title(s, "Kiến trúc tổng thể hệ thống");
  await image(s, "system_overview.png", 45, 115, 1190, 540, "Kiến trúc tổng thể hệ thống bốn lõi RV32IMA");
  footer(s, 5); notes(s, "Đọc sơ đồ từ trên xuống. Mỗi lõi có pipeline, MMU/TLB và L1 riêng. AHB-Lite tập trung các request. Coherence manager phối hợp snoop và L2. AXI4 nối hệ thống đến DMA, DRAM và ngoại vi. Hình nguồn: docs/architecture/system_overview.svg.");
}

// 6 RTL tree
{
  const s = newSlide(); title(s, "Cấu trúc mã RTL theo block", "Module và interface giữ nguyên; chỉ thay đổi vị trí source");
  await image(s, "rtl_tree.png", 60, 125, 1160, 520, "Cấu trúc thư mục RTL sau khi tổ chức lại");
  footer(s, 6); notes(s, "Cây thư mục giúp người mới tìm đúng block trước khi đọc code. files.f là danh sách source chuẩn. Ba script Vivado đã dùng hàm tìm file đệ quy nên không còn giả định source nằm phẳng ở rtl/. Hình nguồn: docs/architecture/rtl_tree.svg.");
}

// 7 Core pipeline
{
  const s = newSlide(); title(s, "Lõi RV32IMA pipeline 5 tầng");
  await image(s, "core_pipeline.png", 45, 125, 1190, 505, "Kiến trúc pipeline năm tầng RV32IMA");
  txt(s, 80, 626, 1120, 34, "Stall ngoài đóng băng pipeline khi MMU walk, cache miss hoặc maintenance", 19, C.orange, true, "center");
  footer(s, 7); notes(s, "Pipeline gồm IF, ID, EX, MEM và WB. Hazard unit xử lý forwarding, load-use và MDU nhiều chu kỳ. RV32A đi qua memory stage. CSR/trap unit tạo redirect và cung cấp satp, SUM, MXR cho MMU. Hình nguồn: docs/architecture/core_pipeline.svg; RTL: rtl/core/.");
}

// 8 MMU
{
  const s = newSlide(); title(s, "MMU Sv32 theo từng lõi");
  await image(s, "mmu.png", 40, 120, 1200, 510, "Kiến trúc MMU TLB PTW Sv32");
  txt(s, 85, 622, 1110, 36, "TLB hit trả PA trực tiếp; TLB miss khóa lõi, PTW đọc PTE, cập nhật A/D rồi refill", 19, C.orange, true, "center");
  footer(s, 8); notes(s, "Mỗi lõi có iTLB và dTLB 4 set x 4 way, cộng super-TLB cho trang 4 MiB. Hai phía dùng chung PTW hai cấp. Region policy chặn sớm truy cập sai vùng. U/S, SUM, MXR và quyền R/W/X được kiểm tra ở cả hit và refill. Hình nguồn: docs/architecture/mmu.svg; RTL: rtl/mmu/.");
}

// 9 Cache coherence
{
  const s = newSlide(); title(s, "Phân cấp cache và coherence MSI");
  await image(s, "cache_coherence.png", 35, 120, 1210, 520, "Phân cấp cache và coherence MSI");
  footer(s, 9); notes(s, "L1 D-cache lưu ba trạng thái I, S, M. Read miss nhận S. Write hit S phải phát RFO trước khi lên M. BusRd vào owner M buộc owner cung cấp dữ liệu và hạ xuống S. BusRdX invalidate các sharer. Hệ thống tuần tự hóa transaction để giảm race. Hình nguồn: docs/architecture/cache_coherence.svg; RTL: rtl/cache và rtl/coherence.");
}

// 10 MSI walkthrough
{
  const s = newSlide(); title(s, "Ba luồng giao dịch MSI quan trọng");
  const rows = [170, 330, 490];
  const data = [
    ["Read miss", "I", "BusRd", "S", "Nhận line từ owner, L2 hoặc DRAM"],
    ["Write upgrade", "S", "RFO + invalidate", "M", "Chỉ ghi sau khi các sharer đã ack"],
    ["Remote read", "M", "Snoop BusRd", "S", "Owner forward dirty line và cập nhật L2"]
  ];
  data.forEach((r,i)=>{
    txt(s, 70, rows[i], 180, 56, r[0], 23, C.navy, true);
    rect(s, 275, rows[i], 85, 56, C.white, C.gray); txt(s, 275, rows[i], 85, 56, r[1], 24, C.ink, true, "center");
    txt(s, 385, rows[i], 240, 56, r[2], 21, C.orange, true, "center");
    rect(s, 650, rows[i], 85, 56, C.white, i===1?C.orange:C.cyan); txt(s, 650, rows[i], 85, 56, r[3], 24, C.ink, true, "center");
    txt(s, 770, rows[i]-5, 420, 66, r[4], 20, C.ink);
  });
  txt(s, 280, 610, 650, 38, "Directory chỉ lưu sharer bitmap; MSI bảo đảm M có đúng một owner", 20, C.gray, true, "center");
  footer(s, 10); notes(s, "Slide này giải thích hành vi giao thức bằng ba ví dụ thay vì trình bày toàn bộ FSM. Điểm cần nhấn mạnh: MSI bỏ trạng thái Exclusive nên mọi chuyển S sang M đều quan sát được trên bus. Điều đó làm directory đơn giản hơn nhưng tăng một giao dịch upgrade.");
}

// 11 Bus domains
{
  const s = newSlide(); title(s, "AHB-Lite và AXI4 giữ hai vai trò khác nhau");
  await image(s, "bus_domains.png", 45, 125, 1190, 510, "Hai miền bus AHB-Lite và AXI4");
  footer(s, 11); notes(s, "AHB-Lite dùng ở ranh giới request từ L1 đến coherence engine. AXI4 là interface hệ thống cho memory controller và DMA. Hai bus không phải hai lựa chọn thay thế. Hình nguồn: docs/architecture/bus_domains.svg; RTL: rtl/interconnect/ahb và rtl/soc.");
}

// 12 AHB detail
{
  const s = newSlide(); title(s, "Giao dịch AHB-Lite qua cache adapter");
  txt(s, 80, 155, 1060, 50, "Một request cache được tách thành address phase và data/response phase", 26, C.navy, true, "center");
  const stages = [
    ["1  Address", "HADDR, HWRITE, HTRANS, HMASTLOCK", C.blue],
    ["2  Wait", "HREADY giữ low khi coherence manager đang bận", C.orange],
    ["3  Response", "HRDATA hoặc write acknowledgement; HRESP báo lỗi", C.cyan]
  ];
  stages.forEach((a,i)=>{
    rect(s, 120+i*380, 260, 330, 145, C.white, a[2]);
    txt(s, 145+i*380, 275, 280, 45, a[0], 24, a[2], true, "center");
    txt(s, 145+i*380, 330, 280, 55, a[1], 19, C.ink, false, "center");
  });
  txt(s, 110, 490, 1060, 85, "RFO sử dụng HMASTLOCK để không mất ý nghĩa giành quyền ghi. Adapter slave giữ backend valid đến khi coherence manager nhận request.", 22, C.ink, false, "center");
  footer(s, 12); notes(s, "Giải thích back-pressure: cache giữ request, AHB adapter giữ HREADY thấp trong lúc backend chưa sẵn sàng. RFO được phân biệt với read thường bằng HMASTLOCK. Regression AHB đã kiểm tra HREADY, RFO, invalidate, owner forward và full-line writeback.");
}

// 13 Boot
{
  const s = newSlide(); title(s, "Luồng boot, DMA và kiểm tra end-to-end");
  await image(s, "boot_flow.png", 40, 120, 1200, 510, "Luồng SD DMA DRAM CPU và ghi kết quả về SD");
  footer(s, 13); notes(s, "Kịch bản cuối không nạp sẵn chương trình vào BlockRAM để chạy trực tiếp. Dữ liệu đi từ storage vào DRAM, boot controller đặt entry point và thả core, CPU thực thi, kết quả được ghi lại storage. Đường SD cụ thể phụ thuộc board: VCU129 cần xác nhận kết nối vật lý; Genesys ZU-5EV dùng PS-mediated SD. Hình nguồn: docs/architecture/boot_flow.svg.");
}

// 14 CSR trap
{
  const s = newSlide(); title(s, "CSR, trap và chế độ đặc quyền");
  txt(s, 70, 160, 360, 48, "Nguồn sự kiện", 26, C.navy, true);
  bullets(s, 75, 220, 390, ["ECALL, EBREAK, illegal instruction", "Instruction/data page fault", "MRET, SRET và SFENCE.VMA"], 20, C.ink, 72);
  rect(s, 470, 175, 330, 345, C.white, C.orange);
  txt(s, 500, 195, 270, 55, "csr_trap_unit", 27, C.orange, true, "center");
  bullets(s, 505, 255, 260, ["CSR M/S", "CurrentPriv M/S/U", "Delegation", "PC redirect", "satp, SUM, MXR"], 19, C.ink, 45);
  txt(s, 850, 160, 340, 48, "Đầu ra hệ thống", 26, C.navy, true);
  bullets(s, 855, 220, 350, ["Trap vector và cause", "MMU enable / flush", "Quyền truy cập U/S", "Địa chỉ lỗi mtval/stval"], 20, C.ink, 66);
  txt(s, 120, 555, 1040, 42, "Giới hạn còn theo dõi: regression medeleg/ECALL đặc quyền chưa sạch hoàn toàn", 20, C.red, true, "center");
  footer(s, 14); notes(s, "Không tuyên bố privilege hoàn tất tuyệt đối. README ghi rõ tb_csr_priv còn ba check lỗi ở đường medeleg/cause. Các test MMU, CSR_MMU_BITS và CSR_TRAP đã PASS. RTL thuộc rtl/core/csr_trap_unit.v và sys_decoder.v.");
}

// 15 Verification
{
  const s = newSlide(); title(s, "Chiến lược kiểm chứng không dùng UVM");
  await image(s, "verification.png", 35, 120, 1210, 515, "Chiến lược kiểm chứng RTL và FPGA không dùng UVM");
  footer(s, 15); notes(s, "Waveform dùng để chẩn đoán, không phải bằng chứng duy nhất. Mỗi testbench tự kiểm phải phát PASS/FAIL. Sau unit test là integration, regression, synthesis và hardware test. UVM nằm ngoài phạm vi để dành thời gian cho tích hợp toàn hệ thống và FPGA. Hình nguồn: docs/architecture/verification.svg.");
}

// 16 Test evidence
{
  const s = newSlide(); title(s, "Bằng chứng mô phỏng RTL hiện có", "Phân biệt kết quả vừa xác nhận và testbench đang chờ chạy lại");
  const tests = [
    ["MSI_COHERENCE_TB", "PASS", "I/S/M, 4 sharer, eviction, flush, AMO"],
    ["MSI_COHERENCE_AHB_TB", "PASS", "RFO/HMASTLOCK, HREADY, snoop, writeback"],
    ["MMU_ADVANCED / UPGRADE / POLICY", "READY", "Có testbench; cần chạy lại toàn bộ regression"],
    ["CACHE_FENCE_I / AMO / LRSC", "READY", "Có testbench; cần chạy lại toàn bộ regression"],
    ["CSR privilege delegation", "OPEN", "medeleg/cause còn lỗi cần sửa"]
  ];
  tests.forEach((r,i)=>{
    const y = 160+i*88;
    txt(s, 72, y, 360, 58, r[0], 21, C.navy, true);
    rect(s, 450, y+8, 120, 42, r[1]==="PASS"?C.green:C.orange, r[1]==="PASS"?C.green:C.orange);
    txt(s, 450, y+8, 120, 42, r[1], 19, C.white, true, "center");
    txt(s, 610, y, 560, 58, r[2], 19, C.ink);
  });
  footer(s, 16); notes(s, "Hai test coherence được chạy lại trong phiên này sau khi di chuyển source. Cả hai PASS. Các nhóm MMU và cache đã có testbench nhưng chưa được tính là bằng chứng sau tái cấu trúc cho đến khi chạy lại toàn bộ regression. Không gộp lỗi privilege vào kết luận MMU.\nNguồn: Risc_V_new/README.md và log kiểm tra hiện tại.");
}

// 17 FPGA evaluation
{
  const s = newSlide(); title(s, "Kịch bản đánh giá trên FPGA");
  txt(s, 80, 155, 430, 52, "Workload đề xuất", 27, C.navy, true);
  bullets(s, 85, 220, 460, ["Compute-bound: vùng dữ liệu độc lập", "Memory-bound: duyệt mảng lớn", "Producer-consumer: dữ liệu dùng chung", "Contention và false sharing", "FIR hoặc PID fixed-point định hướng UAV"], 20, C.ink, 65);
  txt(s, 650, 155, 430, 52, "Chỉ số cần thu", 27, C.navy, true);
  bullets(s, 655, 220, 480, ["PASS/FAIL và dữ liệu đầu ra", "Cycle, thời gian, speedup 1/2/4 lõi", "L1/L2 hit-miss và coherence traffic", "LUT, FF, BRAM, Fmax và timing", "Power và năng lượng mỗi tác vụ nếu đo được"], 20, C.ink, 65);
  rect(s, 120, 585, 1040, 48, C.pale, C.blue);
  txt(s, 140, 585, 1000, 48, "Mọi cấu hình phải dùng cùng board, clock, compiler flags, workload và input", 20, C.navy, true, "center");
  footer(s, 17); notes(s, "Không so hiệu năng giữa các board hoặc workload khác nhau rồi kết luận hơn kém. Baseline hữu ích nhất là 1 lõi, 2 lõi và 4 lõi trên cùng thiết kế. Performance counter trong coherence manager đã hỗ trợ đếm request, hit/miss, snoop, word DRAM và busy cycle.");
}

// 18 Current status
{
  const s = newSlide(); title(s, "Trạng thái hiện tại của khóa luận");
  const groups = [
    ["Đã có RTL; coherence PASS", C.green, ["RV32IMA pipeline", "MMU/TLB/PTW", "L1/L2 + MSI", "AHB-Lite adapters", "AXI4 wrappers + boot control"]],
    ["Còn phải chứng minh", C.orange, ["Vivado synthesis/implementation", "Timing và power", "DRAM/SD trên board thật", "DMA-coherence handshake", "Workload 4 lõi end-to-end"]]
  ];
  groups.forEach((g,i)=>{
    const x = i===0?80:670;
    rect(s, x, 170, 520, 390, C.white, g[1]);
    txt(s, x+30, 190, 460, 50, g[0], 27, g[1], true, "center");
    bullets(s, x+38, 260, 445, g[2], 21, C.ink, 58);
  });
  txt(s, 130, 596, 1020, 38, "Không dùng số dòng RTL làm thước đo hoàn thành; bằng chứng cuối là regression, report và demo phần cứng", 19, C.navy, true, "center");
  footer(s, 18); notes(s, "Slide này giúp trình bày trung thực. RTL đã bao phủ các block chính và hai regression coherence vừa được xác nhận PASS, nhưng chưa có bitstream và demo phần cứng. Không nên nói hệ thống gần hoàn thành nếu chưa có full regression, synthesis, timing và workload trên board.");
}

// 19 Risks
{
  const s = newSlide(); title(s, "Rủi ro kỹ thuật và giới hạn");
  const risks = [
    ["MMIO", "Memory port chưa có byte strobe và uncached bypass hoàn chỉnh"],
    ["DMA", "Chưa là coherence master; cần flush trước và sau transfer"],
    ["Error path", "HRESP/AXI error chưa đi ngược thành architectural access fault"],
    ["Throughput", "Coherence manager blocking, một transaction toàn hệ thống"],
    ["Board", "Đường SD khác nhau theo board; phải xác nhận kết nối vật lý"],
    ["Privilege", "medeleg/cause còn regression chưa sạch"]
  ];
  risks.forEach((r,i)=>{
    const y=155+i*78;
    txt(s, 80, y, 180, 52, r[0], 22, i<3?C.orange:C.navy, true);
    txt(s, 275, y, 875, 52, r[1], 20, C.ink);
    rect(s, 80, y+60, 1070, 2, "#D6E1E8", "#D6E1E8", "rect");
  });
  footer(s, 19); notes(s, "Đây là các giới hạn được ghi trực tiếp trong README, không phải giả định. Khi trình bày, nối mỗi rủi ro với một bước xử lý tiếp theo: uncached path, DMA flush protocol, error propagation, performance optimization, board verification và sửa privilege delegation.");
}

// 20 Roadmap
{
  const s = newSlide(); title(s, "Lộ trình hoàn thiện");
  const steps = [
    ["1", "Khóa regression", "Core, MMU, MSI, AHB-Lite"],
    ["2", "Tổng hợp Vivado", "Resource, timing, power"],
    ["3", "Bring-up board", "Clock, reset, DRAM, UART"],
    ["4", "Boot và DMA", "SD - DRAM - CPU - SD"],
    ["5", "Đánh giá", "1/2/4 lõi và workload"]
  ];
  steps.forEach((a,i)=>{
    const x=55+i*245;
    rect(s,x,220,190,190,C.white,i===3?C.orange:C.blue);
    txt(s,x+60,245,70,55,a[0],32,i===3?C.orange:C.blue,true,"center");
    txt(s,x+20,310,150,45,a[1],21,C.navy,true,"center");
    txt(s,x+15,360,160,55,a[2],17,C.ink,false,"center");
  });
  txt(s, 115, 520, 1050, 62, "Ưu tiên tháng 9-10: MMU/TLB, AHB-Lite và AXI4 ổn định trước khi mở rộng phần còn lại", 23, C.orange, true, "center");
  footer(s, 20); notes(s, "Lộ trình phản ánh đề cương đã chỉnh: các block nền tảng MMU/TLB và hai miền bus phải ổn định sớm. Sau đó mới tập trung coherence nâng cao, DMA, boot và FPGA. Mỗi bước cần một tiêu chí PASS cụ thể.");
}

// 21 Conclusion
{
  const s = newSlide(C.navy);
  txt(s, 75, 65, 1120, 60, "Kết luận", 38, C.white, true);
  txt(s, 95, 165, 1050, 80, "Thiết kế đã hình thành một kiến trúc 4 lõi có đầy đủ đường xử lý và phân cấp bộ nhớ", 30, C.white, true, "center");
  bullets(s, 145, 290, 980, ["RV32IMA pipeline, CSR và chế độ đặc quyền", "MMU/TLB/PTW Sv32 theo từng lõi", "L1/L2 và coherence MSI đã có regression PASS", "AHB-Lite và AXI4 tách theo hai miền chức năng", "Giá trị còn lại nằm ở synthesis và demo FPGA end-to-end"], 22, C.white, 60);
  txt(s, 250, 625, 780, 42, "Câu hỏi và thảo luận", 25, "#D9EAF2", true, "center");
  notes(s, "Kết luận bằng trạng thái thực tế: nền tảng RTL đã có cấu trúc rõ, coherence và bus regression đã PASS, nhưng mục tiêu khóa luận chỉ hoàn tất khi có báo cáo Vivado và demo phần cứng end-to-end.");
}

const staging = path.join(buildDir, "finalizer");
await fs.mkdir(staging, { recursive: true });
const candidatePath = path.join(staging, "candidate.pptx");
await (await PresentationFile.exportPptx(p)).save(candidatePath);

const result = await finalizePresentation({
  workspaceDir,
  candidatePath,
  finalPath,
  pythonExecutable: runtimePython,
  integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: ["--expected-slide-size-emu", "12192000,6858000", "--validate-heading-fit"],
  explicitTotalSlideCount: 21,
  requiredNativeTableOwnerSlides: [],
  requiredNativeChartOwnerSlides: [],
  fontPolicy: { basis: "design", families: [FONT] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(staging, "validation.json")
});
console.log(JSON.stringify({ finalPath, result }, null, 2));
