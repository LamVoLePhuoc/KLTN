import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Presentation, PresentationFile } from "file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const workspaceDir = "C:/Users/ADMIN/Documents/GitHub/KLTN";
const skillDir = "C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.1024.11018/skills/presentations";
const buildDir = path.join(workspaceDir, ".codex-build/weekly-progress-deck");
const previewDir = path.join(buildDir, "previews");
const outputDir = path.join(workspaceDir, "deliverables");
const finalPptx = path.join(outputDir, "Bao_cao_tien_do_MMU_Cache_DMA_2026-10-25_ready.pptx");
const pythonExecutable = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";

const W = 1280;
const H = 720;
const FONT = "Arial";
const C = {
  navy: "#071A2B",
  navy2: "#102D44",
  blue: "#1F6FEB",
  cyan: "#19B5C5",
  teal: "#0B8F87",
  orange: "#F28C28",
  green: "#20A56B",
  red: "#D84B4B",
  white: "#FFFFFF",
  ink: "#132231",
  muted: "#586B7C",
  pale: "#EFF5F8",
  paleBlue: "#EAF2FF",
  paleTeal: "#E7F7F5",
  paleOrange: "#FFF3E5",
  line: "#CCD8E1",
};

const sources = {
  overview: path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture/system_overview.png"),
  mmu: path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture/mmu.png"),
  cache: path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture/cache_coherence.png"),
  bus: path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture/bus_domains.png"),
};

const scripts = [
  `Em xin báo cáo tiến độ tuần từ ngày 19 đến 25 tháng 10 năm 2026. Phạm vi tuần này tập trung vào ba phần: làm rõ ranh giới giữa MMU dịch địa chỉ và bộ điều khiển cache, tổng hợp kết quả cache controller, và hoàn thiện DMA ở mức RTL. Kết quả mới nhất là testbench DMA end-to-end đã chạy PASS trên Vivado XSIM.`,
  `Điểm thay đổi quan trọng bắt đầu từ việc xem lại khái niệm MMU. Source tham khảo gọi khối ghép I-cache, D-cache và các FSM miss hoặc write-back là MMU. Khối đó gần với bộ điều khiển cache hơn là MMU theo kiến trúc RISC-V. Vì hai chức năng giải quyết hai bài toán khác nhau, thiết kế mới tách chúng rõ ràng. mmu_top thực hiện Sv32 và tạo địa chỉ vật lý. cache_controller_mmu điều phối L1, L2, coherence và memory port cho bốn core.`,
  `Kiến trúc hiện tại gồm bốn core RV32IMA. Mỗi core có MMU Sv32 và L1 riêng. Các yêu cầu miss đi vào cache controller dùng chung, sau đó tới L2 512 KiB và cổng memory. AHB-Lite nằm trong miền CPU và cache. AXI4 nằm ở ranh giới hệ thống để kết nối memory controller, DDR và các master ngoài như DMA. Cách tách này giúp mỗi khối có trách nhiệm rõ và dễ kiểm chứng độc lập.`,
  `Mỗi core có iTLB và dTLB riêng. TLB trang 4 KiB gồm 16 entry, tổ chức bốn set và bốn way, thay thế bằng tree-PLRU. Mỗi phía còn có bốn entry superpage 4 MiB. Khi miss, PTW Sv32 đọc tối đa hai cấp PTE, kiểm tra quyền và cập nhật Accessed hoặc Dirty nếu cần. Thiết kế kiểm tra U và S, SUM, MXR, quyền R W X trên mỗi hit, không chỉ khi refill. Bộ XSIM dành riêng cho MMU hiện đạt chín trên chín test PASS.`,
  `Cải tiến quan trọng của MMU nằm ở các trường hợp cạnh. Nếu SFENCE, satp hoặc ngữ cảnh đặc quyền thay đổi trong lúc PTW đang chạy, kết quả cũ bị discard và không được refill vào TLB. Lỗi đọc PTE hoặc ghi A D được chuyển thành access fault đúng loại, thay vì page fault. Trên đường cache và coherence, A D được cập nhật bằng AMOOR.W để giảm nguy cơ một core ghi đè thay đổi PTE của core khác. Watchdog chỉ ghi nhận chẩn đoán, không tự tạo completion giả.`,
  `Cache controller nhận tối đa tám nguồn miss hoặc write-back từ bốn I-cache và bốn D-cache. Bộ phân xử round-robin chọn requester, sau đó FSM tuần tự hóa transaction coherence. Controller làm việc với L2 như một khối đồng cấp và dùng directory sharer bốn bit. MSI đã bao phủ các chuyển trạng thái I sang S, S sang M, M sang S và M sang I. Khi một core giữ dirty line ở M, controller yêu cầu owner forward dữ liệu trước khi downgrade hoặc invalidate.`,
  `L2 ban đầu dùng một mảng bất đồng bộ 4.194.304 bit. Vivado không thể xử lý biến lớn như vậy và synthesis kéo dài nhiều giờ. Phiên bản mới chia dữ liệu thành tám bank 32 bit, dùng truy cập đồng bộ và scrub sau reset. Kết quả là full Block Design synthesis sạch. Tài nguyên gần nhất cho thấy LUT khoảng 71,81 phần trăm, register 22,86 phần trăm, BRAM 93,58 phần trăm và DSP 12 phần trăm. BRAM hiện là giới hạn chính. Timing 100 MHz vẫn chưa đạt, với WNS âm 5,308 nano giây.`,
  `AHB-Lite và AXI4 đều đã có, nhưng đảm nhiệm hai ranh giới khác nhau. AHB-Lite phục vụ đường L1 đến cache controller, giữ HREADY, HRESP, HSIZE, HPROT và HMASTLOCK. AXI4 wrapper đưa CPU memory port ra miền hệ thống, giữ VALID và payload qua backpressure, đồng thời bắt tay AW và W độc lập. DMA cũng đã có AXI4 master và AXI4-Lite register file, nhưng chưa được ghép vào AXI interconnect của Block Design.`,
  `DMA mới gồm register file AXI4-Lite, cache coordinator và AXI4 memcpy engine. Phần mềm ghi source, destination, length và start. Coordinator chỉ nhận lệnh khi buffer_quiesced đã lên, chạy pre-maintenance, sau đó cho DMA copy và cuối cùng chạy post-maintenance. Burst không vượt biên 4 KiB. Read error chặn write tương ứng, còn write response error vẫn yêu cầu post-maintenance. Watchdog vừa được sửa để đo thời gian không có tiến triển, thay vì giới hạn tổng thời gian của một lệnh nhiều burst.`,
  `Kết quả hiện tại gồm chín trên chín test MMU chạy PASS trên Vivado XSIM, regression nền hai mươi sáu trên hai mươi sáu PASS, và DMA end-to-end PASS. Full Block Design nền cũng synthesis thành công. Tuy nhiên em chưa tuyên bố DMA đã hoàn thành ở mức SoC hoặc FPGA, vì DMA chưa vào AXI fabric của Block Design và chưa chạy với DDR thật. Bước tiếp theo là tích hợp DMA master và AXI-Lite slave, xác nhận address map và clock domain, chạy synthesis lại, sau đó xử lý timing trước khi tạo bitstream và thử trên board.`,
];

function addRect(slide, x, y, w, h, fill, radius = 0, line = "none") {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    position: { left: x, top: y, width: w, height: h },
    fill,
    line: line === "none" ? { style: "solid", fill: "none", width: 0 } : { style: "solid", fill: line, width: 1 },
    ...(radius ? { borderRadius: radius } : {}),
  });
}

function addText(slide, text, x, y, w, h, size = 24, color = C.ink, bold = false, align = "left") {
  const s = slide.shapes.add({
    geometry: "textbox",
    position: { left: x, top: y, width: w, height: h },
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  s.text = text;
  s.text.style = { typeface: FONT, fontSize: size, color, bold, alignment: align, verticalAlignment: "middle", autoFit: "shrinkText" };
  s.text.insets = 0;
  return s;
}

function addSlideBase(presentation, number, title, section) {
  const slide = presentation.slides.add();
  slide.background.fill = C.white;
  addRect(slide, 0, 0, W, 14, C.cyan);
  addText(slide, section.toUpperCase(), 68, 38, 360, 24, 13, C.teal, true);
  addText(slide, title, 68, 70, 1120, 52, 34, C.navy, true);
  addRect(slide, 68, 128, 92, 5, C.orange);
  addText(slide, String(number).padStart(2, "0"), 1170, 668, 42, 22, 12, C.muted, true, "right");
  return slide;
}

function addNotes(slide, text, sourceList = []) {
  const sourceText = sourceList.length ? `\n\nNguồn nội bộ:\n${sourceList.map(s => `- ${s}`).join("\n")}` : "";
  slide.speakerNotes.text = text + sourceText;
  slide.speakerNotes.setVisible(true);
}

function addBulletBlock(slide, items, x, y, w, h, size = 22, color = C.ink) {
  const lineH = h / items.length;
  items.forEach((item, i) => {
    addRect(slide, x, y + i * lineH + 9, 8, 8, i === 0 ? C.orange : C.cyan, 4);
    addText(slide, item, x + 22, y + i * lineH, w - 22, lineH, size, color, false);
  });
}

function styleTable(table, rows, cols, header = true) {
  table.borders.assign({ style: "solid", fill: C.line, width: 1 });
  table.cells.block({ row: 0, column: 0, rowCount: rows, columnCount: cols }).assign({
    textStyle: { typeface: FONT, fontSize: 17, color: C.ink },
    margins: { left: 10, right: 10, top: 6, bottom: 6 },
    anchor: "middle",
  });
  if (header) {
    table.cells.block({ row: 0, column: 0, rowCount: 1, columnCount: cols }).assign({
      fill: C.navy2,
      textStyle: { typeface: FONT, fontSize: 17, color: C.white, bold: true },
    });
  }
  for (let r = 1; r < rows; r++) {
    if (r % 2 === 0) table.cells.block({ row: r, column: 0, rowCount: 1, columnCount: cols }).fill = C.pale;
  }
}

async function main() {
  await fs.mkdir(previewDir, { recursive: true });
  await fs.mkdir(outputDir, { recursive: true });
  const images = {
    overview: new Uint8Array(await fs.readFile(sources.overview)),
    mmu: new Uint8Array(await fs.readFile(sources.mmu)),
    cache: new Uint8Array(await fs.readFile(sources.cache)),
  };

  const p = Presentation.create({ slideSize: { width: W, height: H } });

  // 1. Cover
  {
    const s = p.slides.add();
    s.background.fill = C.navy;
    addRect(s, 0, 0, 18, H, C.cyan);
    addRect(s, 830, 0, 450, H, C.navy2);
    s.images.add({ blob: images.overview, contentType: "image/png", alt: "Sơ đồ tổng quan SoC bốn lõi RV32IMA", fit: "contain", position: { left: 784, top: 130, width: 458, height: 430 } });
    addText(s, "BÁO CÁO TIẾN ĐỘ TUẦN", 74, 86, 620, 34, 16, "#72E2E8", true);
    addText(s, "MMU/TLB, cache controller và DMA", 74, 155, 660, 150, 48, C.white, true);
    addText(s, "SoC 4 lõi RISC-V RV32IMA", 74, 330, 580, 48, 25, "#C7D8E6", false);
    addRect(s, 74, 420, 160, 6, C.orange);
    addText(s, "Tuần 19–25/10/2026", 74, 452, 360, 34, 19, C.white, true);
    addText(s, "Phạm vi: kiến trúc MMU mới, MSI cache controller, DMA AXI4", 74, 500, 610, 60, 20, "#AFC4D4", false);
    addText(s, "01", 1170, 668, 42, 22, 12, "#AFC4D4", true, "right");
    addNotes(s, scripts[0], ["Risc_V_new/README.md", "Risc_V_new/Risc_V/docs/architecture/ARCHITECTURE.md"]);
  }

  // 2. Concept split
  {
    const s = addSlideBase(p, 2, "Hai chức năng từng được gọi chung là MMU", "Thay đổi kiến trúc");
    addText(s, "Mã tham khảo", 78, 162, 430, 32, 20, C.red, true);
    addRect(s, 78, 208, 430, 260, C.paleOrange, 18, "#F4CAA0");
    addText(s, "CPU", 110, 247, 90, 50, 22, C.navy, true, "center");
    addText(s, "I-cache + D-cache\nFSM miss / write-back", 246, 225, 220, 95, 22, C.ink, true, "center");
    addText(s, "Memory", 246, 365, 220, 48, 22, C.navy, true, "center");
    addText(s, "Tên gọi MMU nhưng không có Sv32, TLB hoặc PTW", 106, 490, 380, 54, 18, C.muted, false, "center");
    addText(s, "Kiến trúc hiện tại", 590, 162, 540, 32, 20, C.teal, true);
    addRect(s, 590, 208, 610, 336, C.paleTeal, 18, "#A9DBD5");
    const a = addRect(s, 624, 248, 142, 64, C.white, 14, C.line); a.text = "Core VA"; a.text.style = { typeface: FONT, fontSize: 22, bold: true, color: C.navy, alignment: "center", verticalAlignment: "middle" };
    const b = addRect(s, 826, 232, 310, 96, C.white, 14, C.cyan); b.text = "mmu_top\nSv32 + iTLB/dTLB + PTW"; b.text.style = { typeface: FONT, fontSize: 21, bold: true, color: C.navy, alignment: "center", verticalAlignment: "middle" };
    const c = addRect(s, 624, 400, 512, 88, C.white, 14, C.teal); c.text = "cache_controller_mmu\nL1 ↔ L2 ↔ coherence ↔ memory"; c.text.style = { typeface: FONT, fontSize: 21, bold: true, color: C.navy, alignment: "center", verticalAlignment: "middle" };
    s.shapes.connect(a, b, { kind: "straight", fromSide: "right", toSide: "left", line: { style: "solid", fill: C.blue, width: 3 }, head: { type: "triangle", width: "sm", length: "sm" } });
    s.shapes.connect(b, c, { kind: "elbow", fromSide: "bottom", toSide: "top", line: { style: "solid", fill: C.blue, width: 3 }, head: { type: "triangle", width: "sm", length: "sm" } });
    addText(s, "Kết quả: giữ MMU RISC-V thật và đưa ý tưởng của thầy vào một cache controller dùng chung", 120, 590, 1040, 54, 24, C.navy, true, "center");
    addNotes(s, scripts[1], ["Risc_V_new/Risc_V/docs/architecture/MMU_CACHE_CONTROLLER_REDESIGN.md", "KLTN_reference/KLTN/MMU/MMU.sv"]);
  }

  // 3. Current architecture
  {
    const s = addSlideBase(p, 3, "Kiến trúc SoC hiện tại", "Tổng quan");
    s.images.add({ blob: images.overview, contentType: "image/png", alt: "Kiến trúc hiện tại của SoC bốn lõi", fit: "contain", position: { left: 62, top: 154, width: 820, height: 472 } });
    addRect(s, 920, 170, 292, 420, C.paleBlue, 18, "#BDD2EF");
    addText(s, "Ranh giới chính", 946, 194, 240, 32, 22, C.navy, true);
    addBulletBlock(s, [
      "Mỗi core có Sv32 và L1 riêng",
      "Tám nguồn L1 dùng chung controller",
      "L2 512 KiB là khối đồng cấp",
      "AHB trong miền cache",
      "AXI4 ở ranh giới hệ thống",
    ], 946, 246, 236, 275, 18);
    addText(s, "DMA sẽ trở thành AXI master thứ hai sau bước tích hợp Block Design", 946, 532, 232, 58, 17, C.orange, true);
    addNotes(s, scripts[2], ["Risc_V_new/Risc_V/docs/architecture/system_overview.png", "Risc_V_new/Risc_V/docs/architecture/ARCHITECTURE.md"]);
  }

  // 4. MMU/TLB
  {
    const s = addSlideBase(p, 4, "MMU Sv32 và tổ chức TLB", "MMU/TLB");
    s.images.add({ blob: images.mmu, contentType: "image/png", alt: "Sơ đồ MMU Sv32 gồm iTLB, dTLB và PTW", fit: "contain", position: { left: 54, top: 152, width: 700, height: 488 } });
    addRect(s, 790, 160, 420, 442, C.pale, 18, C.line);
    addText(s, "Cấu hình hiện tại", 820, 186, 340, 32, 23, C.navy, true);
    addText(s, "16", 820, 246, 90, 55, 38, C.blue, true);
    addText(s, "entry cho mỗi iTLB/dTLB", 916, 250, 248, 46, 19, C.ink, false);
    addText(s, "4 × 4", 820, 318, 120, 55, 34, C.teal, true);
    addText(s, "set × way, tree-PLRU", 946, 322, 220, 46, 19, C.ink, false);
    addText(s, "4", 820, 390, 90, 55, 38, C.orange, true);
    addText(s, "entry superpage 4 MiB mỗi phía", 916, 394, 248, 50, 19, C.ink, false);
    addText(s, "PTW hai cấp", 820, 468, 340, 36, 22, C.navy, true);
    addText(s, "Quyền U/S, SUM, MXR, R/W/X\nCập nhật Accessed/Dirty\nKiểm tra quyền trên mỗi hit", 820, 510, 340, 82, 18, C.muted, false);
    addRect(s, 790, 618, 420, 42, C.green, 16);
    addText(s, "Vivado XSIM: MMU 9/9 PASS", 812, 623, 376, 30, 20, C.white, true, "center");
    addNotes(s, scripts[3], ["Risc_V_new/Risc_V/rtl/mmu/mmu_top.v", "Risc_V_new/Risc_V/rtl/mmu/mmu_tlb.v", "Risc_V_new/Risc_V/reports/xsim-mmu-20260927-162006/summary.md"]);
  }

  // 5. MMU edge cases
  {
    const s = addSlideBase(p, 5, "Các lỗi góc MMU đã được khóa", "MMU/TLB");
    const items = [
      ["SFENCE giữa PTW", "Giữ flush pending, discard response cũ và walk lại"],
      ["Đổi satp hoặc privilege", "Không stale-refill và không phát fault theo context cũ"],
      ["Lỗi page-table memory", "Tạo access fault cause 1/5/7, không refill TLB"],
      ["Cập nhật A/D", "Dùng AMOOR.W trên đường cache/coherence"],
      ["Watchdog", "Chỉ latch diagnostic, không tạo completion giả"],
    ];
    items.forEach((it, i) => {
      const y = 166 + i * 92;
      addText(s, String(i + 1).padStart(2, "0"), 78, y + 8, 48, 44, 20, i < 2 ? C.orange : C.cyan, true, "center");
      addText(s, it[0], 148, y, 300, 38, 21, C.navy, true);
      addText(s, it[1], 148, y + 38, 610, 42, 18, C.muted, false);
    });
    addRect(s, 820, 184, 350, 354, C.navy, 22);
    addText(s, "Nguyên tắc an toàn", 852, 218, 286, 34, 23, C.white, true, "center");
    addText(s, "Kết quả thuộc context cũ\nkhông được phép đi vào TLB", 850, 292, 290, 88, 27, "#8DE7EC", true, "center");
    addRect(s, 874, 410, 242, 5, C.orange);
    addText(s, "Fault bus và page fault\nđược phân loại riêng", 850, 446, 290, 66, 21, C.white, false, "center");
    addText(s, "Bằng chứng: tb_mmu_sfence, tb_mmu_context, tb_mmu_bus_error", 816, 568, 360, 60, 17, C.muted, false, "center");
    addNotes(s, scripts[4], ["Risc_V_new/WEEKLY_MMU_PROGRESS.md", "Risc_V_new/Risc_V/sim/tb_mmu_sfence.v", "Risc_V_new/Risc_V/sim/tb_mmu_context.v", "Risc_V_new/Risc_V/sim/tb_mmu_bus_error.v"]);
  }

  // 6. Cache controller
  {
    const s = addSlideBase(p, 6, "Cache controller dùng chung và MSI", "Cache/coherence");
    s.images.add({ blob: images.cache, contentType: "image/png", alt: "Sơ đồ cache coherence MSI của hệ thống bốn lõi", fit: "contain", position: { left: 54, top: 152, width: 720, height: 470 } });
    const values = [
      ["Nội dung", "Bản cũ", "Hiện tại"],
      ["Phạm vi", "1 I$ + 1 D$", "4 I$ + 4 D$"],
      ["Phân xử", "Không đa core", "Round-robin 8 nguồn"],
      ["Coherence", "Invalidate đơn giản", "MSI + owner forwarding"],
      ["L2", "Chưa có directory", "512 KiB, 4-way, 4 sharer"],
      ["Lỗi", "fsm_error chung", "Đúng requester + sticky diagnostics"],
      ["MMIO", "Đi chung cache", "Bypass L1/L2"],
    ];
    const t = s.tables.add({ rows: values.length, columns: 3, left: 790, top: 166, width: 428, height: 390, columnWidths: [112, 142, 174], values });
    styleTable(t, values.length, 3, true);
    addNotes(s, scripts[5], ["Risc_V_new/Risc_V/rtl/mmu/cache_controller_mmu.v", "Risc_V_new/Risc_V/docs/architecture/cache_coherence.png", "Risc_V_new/Risc_V/reports/full-regression-mmu-controller-final/summary.md"]);
  }

  // 7. L2 optimization and buses
  {
    const s = addSlideBase(p, 7, "Tối ưu L2 và ranh giới bus", "Vivado + interconnect");
    addText(s, "Lỗi synthesis trước đây", 78, 166, 430, 32, 21, C.red, true);
    addRect(s, 78, 210, 430, 132, C.paleOrange, 18, "#F4CAA0");
    addText(s, "4.194.304 bit", 108, 232, 370, 52, 36, C.red, true, "center");
    addText(s, "mảng data bất đồng bộ vượt giới hạn Vivado", 108, 286, 370, 34, 18, C.ink, false, "center");
    addText(s, "Cấu trúc mới", 78, 376, 430, 32, 21, C.teal, true);
    addBulletBlock(s, ["8 bank × 32 bit", "Truy cập đồng bộ", "Scrub sau reset", "Suy diễn RAMB36/XPM"], 96, 424, 390, 188, 20);
    addText(s, "AHB-Lite", 586, 166, 248, 32, 22, C.navy, true, "center");
    addRect(s, 566, 210, 288, 172, C.paleTeal, 18, "#A9DBD5");
    addText(s, "Miền CPU/cache", 592, 230, 236, 34, 20, C.teal, true, "center");
    addText(s, "HREADY / HRESP\nHSIZE / HPROT\nHMASTLOCK cho RFO", 592, 278, 236, 82, 18, C.ink, false, "center");
    addText(s, "AXI4", 934, 166, 248, 32, 22, C.navy, true, "center");
    addRect(s, 914, 210, 288, 172, C.paleBlue, 18, "#BDD2EF");
    addText(s, "Ranh giới hệ thống", 940, 230, 236, 34, 20, C.blue, true, "center");
    addText(s, "AR/R + AW/W/B\nBackpressure an toàn\nCPU và DMA master", 940, 278, 236, 82, 18, C.ink, false, "center");
    addRect(s, 566, 424, 636, 178, C.navy, 18);
    addText(s, "Full Block Design synthesis PASS", 598, 446, 572, 38, 24, C.white, true, "center");
    addText(s, "LUT 71,81%     FF 22,86%     BRAM 93,58%     DSP 12%", 598, 500, 572, 34, 20, "#8DE7EC", true, "center");
    addText(s, "Timing 100 MHz chưa đạt: WNS = −5,308 ns", 598, 552, 572, 30, 19, "#FFC273", true, "center");
    addNotes(s, scripts[6] + "\n\n" + scripts[7], ["Risc_V_new/README.md", "Risc_V_new/Risc_V/rtl/cache/l2_cache.v", "Risc_V_new/Risc_V/docs/architecture/bus_domains.png"]);
  }

  // 8. DMA design
  {
    const s = addSlideBase(p, 8, "DMA AXI4 và trình tự cache maintenance", "DMA");
    const xs = [86, 350, 640, 930];
    const labels = [
      ["AXI4-Lite regs", "SRC / DST / LENGTH / START"],
      ["Cache coordinator", "quiesce + pre/post maintenance"],
      ["AXI memcpy", "bounded burst + 4 KiB split"],
      ["System AXI4", "memory controller / DDR"],
    ];
    const nodes = labels.map((l, i) => {
      const r = addRect(s, xs[i], 220, 220, 126, i === 1 ? C.paleTeal : C.paleBlue, 18, i === 1 ? C.teal : C.blue);
      addText(s, l[0], xs[i] + 16, 238, 188, 34, 21, C.navy, true, "center");
      addText(s, l[1], xs[i] + 18, 282, 184, 46, 16, C.muted, false, "center");
      return r;
    });
    for (let i = 0; i < nodes.length - 1; i++)
      addText(s, "›", xs[i] + 224, 248, 38, 50, 38, C.cyan, true, "center");
    addText(s, "Trình tự bảo đảm tính nhất quán", 150, 410, 980, 36, 24, C.navy, true, "center");
    const seq = ["Buffer quiesced", "Pre-flush", "DMA copy", "Post-flush", "DONE / ERROR"];
    seq.forEach((v, i) => {
      addRect(s, 72 + i * 238, 472, 190, 66, i === 4 ? C.green : C.navy2, 16);
      addText(s, v, 84 + i * 238, 482, 166, 44, 18, C.white, true, "center");
      if (i < seq.length - 1) addText(s, "›", 264 + i * 238, 482, 42, 44, 34, C.orange, true, "center");
    });
    addText(s, "DMA không phải MSI snoop master. Phần mềm vẫn phải quản lý quyền sở hữu buffer.", 132, 588, 1016, 44, 19, C.red, true, "center");
    addNotes(s, scripts[8], ["Risc_V_new/Risc_V/rtl/dma/README.md", "Risc_V_new/Risc_V/rtl/dma/soc_dma_controller.v", "Risc_V_new/Risc_V/docs/BOOT_DMA_PROTOCOL.md"]);
  }

  // 9. Verification
  {
    const s = addSlideBase(p, 9, "Bằng chứng kiểm chứng hiện có", "Kết quả");
    const values = [
      ["Nhóm", "Kết quả", "Phạm vi chứng minh"],
      ["MMU trên Vivado XSIM", "9/9 PASS", "Sv32, TLB/PTW, context, bus fault"],
      ["Regression nền", "26/26 PASS", "MMU, CSR, cache, coherence, bus"],
      ["DMA end-to-end", "PASS", "AXI-Lite, burst copy, flush, error, watchdog"],
      ["Full Block Design", "Synthesis PASS", "0 error, 0 critical warning"],
      ["Timing 100 MHz", "CHƯA ĐẠT", "WNS −5,308 ns"],
      ["FPGA end-to-end", "CHƯA CHẠY", "DMA chưa tích hợp với DDR thật"],
    ];
    const t = s.tables.add({ rows: values.length, columns: 3, left: 76, top: 174, width: 1128, height: 402, columnWidths: [290, 220, 618], values });
    styleTable(t, values.length, 3, true);
    t.getCell(1, 1).fill = C.paleTeal; t.getCell(2, 1).fill = C.paleTeal; t.getCell(3, 1).fill = C.paleTeal; t.getCell(4, 1).fill = C.paleTeal;
    t.getCell(5, 1).fill = C.paleOrange; t.getCell(6, 1).fill = "#FDECEC";
    t.cells.block({ row: 1, column: 1, rowCount: 4, columnCount: 1 }).textStyle.bold = true;
    t.cells.block({ row: 5, column: 1, rowCount: 2, columnCount: 1 }).textStyle.bold = true;
    addText(s, "Không cộng các nhóm test thành một con số duy nhất vì chúng thuộc các mốc source khác nhau.", 118, 606, 1044, 42, 18, C.muted, false, "center");
    addNotes(s, scripts[9], ["Risc_V_new/Risc_V/reports/xsim-mmu-20260927-162006/summary.md", "Risc_V_new/Risc_V/reports/full-regression-latest/summary.md", "Risc_V_new/Risc_V/sim/tb_dma_end_to_end.v", "Risc_V_new/README.md"]);
  }

  // 10. Next steps
  {
    const s = addSlideBase(p, 10, "Mốc tiếp theo để hoàn tất ở mức hệ thống", "Kế hoạch");
    const steps = [
      ["01", "Tích hợp DMA", "Thêm AXI master và AXI-Lite slave vào Block Design"],
      ["02", "Hoàn thiện kết nối", "Address map, cache handshake và clock domain"],
      ["03", "Synthesis lại", "Kiểm tra BRAM sau khi thêm DMA"],
      ["04", "Đóng timing", "Tìm critical path và đạt tần số mục tiêu"],
      ["05", "Board test", "Bitstream, DDR thật và workload CPU–DMA"],
    ];
    steps.forEach((st, i) => {
      const y = 166 + i * 86;
      addText(s, st[0], 86, y, 68, 58, 25, i < 2 ? C.orange : C.cyan, true, "center");
      addText(s, st[1], 176, y, 270, 34, 22, C.navy, true);
      addText(s, st[2], 176, y + 34, 660, 32, 18, C.muted, false);
      addRect(s, 858, y + 26, 310, 4, i === 4 ? C.green : C.line);
    });
    addRect(s, 850, 190, 332, 304, C.navy, 22);
    addText(s, "Mốc hoàn tất mong muốn", 878, 220, 276, 32, 21, C.white, true, "center");
    addText(s, "CPU tạo dữ liệu nguồn\nDMA copy qua DDR\nCPU kiểm tra dữ liệu đích", 878, 286, 276, 110, 24, "#8DE7EC", true, "center");
    addText(s, "Có log PASS và báo cáo timing sau implementation", 878, 424, 276, 48, 17, "#FFC273", true, "center");
    addText(s, "Kết luận tuần này: chức năng DMA đã PASS độc lập; công việc còn lại tập trung vào tích hợp và timing.", 122, 620, 1036, 42, 21, C.navy, true, "center");
    addNotes(s, `Bước tiếp theo của em gồm năm mốc. Đầu tiên em tích hợp DMA vào AXI interconnect và cấp vùng địa chỉ AXI4-Lite. Sau đó em xác nhận cache handshake và clock domain. Em sẽ chạy synthesis lại vì BRAM đã dùng hơn chín mươi ba phần trăm. Tiếp theo là xử lý critical path để đạt timing. Mốc cuối là bitstream và workload CPU tạo dữ liệu nguồn, DMA copy qua DDR, rồi CPU kiểm tra dữ liệu đích. Trong tuần này em chỉ kết luận DMA đã PASS độc lập ở RTL, chưa kết luận toàn SoC đã hoàn thành.`, ["Risc_V_new/README.md", "Risc_V_new/Risc_V/docs/BOOT_DMA_PROTOCOL.md"]);
  }

  // Render drafts for visual review.
  for (const [i, slide] of p.slides.items.entries()) {
    const png = await p.export({ slide, format: "png", scale: 1 });
    await fs.writeFile(path.join(previewDir, `slide-${String(i + 1).padStart(2, "0")}.png`), new Uint8Array(await png.arrayBuffer()));
  }
  const montage = await p.export({ format: "webp", montage: true });
  await fs.writeFile(path.join(previewDir, "montage.webp"), new Uint8Array(await montage.arrayBuffer()));

  const { finalizePresentation } = await import(pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href);
  const stagingDir = path.join(buildDir, ".finalizer");
  await fs.mkdir(stagingDir, { recursive: true });
  const candidatePath = path.join(stagingDir, "candidate.pptx");
  await (await PresentationFile.exportPptx(p)).save(candidatePath);
  await finalizePresentation({
    explicitTotalSlideCount: 10,
    requiredNativeTableOwnerSlides: [6, 9],
    requiredNativeChartOwnerSlides: [],
    workspaceDir,
    candidatePath,
    finalPath: finalPptx,
    pythonExecutable,
    integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
    layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
    layoutArgs: ["--expected-slide-size-emu", "12192000,6858000", "--validate-bullet-geometry", "--validate-heading-fit", "--require-native-table-slide", "6", "--require-native-table-slide", "9"],
    fontPolicy: { basis: "design", families: [FONT] },
    verifyArtifactToolImport: true,
    receiptPath: path.join(stagingDir, "validation_ready.json"),
  });

  console.log(JSON.stringify({ finalPptx, previewDir, slideCount: p.slides.items.length }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
