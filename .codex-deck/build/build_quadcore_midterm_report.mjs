import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";
import {
  FileBlob,
  PresentationFile,
} from "file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const workspaceDir = "C:/Users/ADMIN/Documents/GitHub/KLTN";
const skillDir = "C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.1025.11240/skills/presentations";
const runtimePython = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
process.env.RUNTIME_NODE = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe";
process.env.RUNTIME_NODE_MODULES = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules";
process.env.RUNTIME_BIN_DIR = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override";
process.env.RUNTIME_PYTHON = runtimePython;

const templatePath = "C:/Users/ADMIN/Downloads/KTMT_KLTN_Phu luc 6_Mau bao cao bao ve.pptx";
const proposalPath = path.join(workspaceDir, "BaoVeDeCuong_QuadCore_RV32IMA.pptx");
const currentReadmePath = path.join(workspaceDir, "Risc_V_new/README.md");
const hierarchySummaryPath = path.join(workspaceDir, "Risc_V_new/Risc_V/reports/xsim-behavior-hierarchy-20261028-110415/summary.md");
const implementationSummaryPath = path.join(workspaceDir, "Risc_V_new/Risc_V/reports/vivado-mdu-pipeline-20261028-114757/summary.txt");
const utilizationPath = path.join(workspaceDir, "Risc_V_new/Risc_V/reports/vivado-mdu-pipeline-20261028-114757/utilization_route.rpt");
const powerPath = path.join(workspaceDir, "Risc_V_new/Risc_V/reports/vivado-mdu-pipeline-20261028-114757/power_route.rpt");
const architectureSvgPath = path.join(workspaceDir, "Risc_V_new/Risc_V/docs/architecture/system_overview.svg");
const stagingDir = path.join(workspaceDir, ".codex-deck/quadcore-staging");
const previewDir = path.join(workspaceDir, ".codex-deck/quadcore-final-preview");
const finalPath = path.join(workspaceDir, "output/BaoCao_GiuaKy_KLTN_QuadCore_RV32IMA_v3.pptx");

const { makeNativeBulletParagraphs, finalizePresentation } = await import(
  pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href
);

async function saveBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function tableBlock(table, row, column, rowCount, columnCount, options) {
  table.cells.block({ row, column, rowCount, columnCount }).assign(options);
}

function styleTable(table, { rows, columns, fontSize = 17, headerFontSize = 18, rowHeights = [] }) {
  table.borders.assign({ style: "solid", fill: "#8B8B8B", width: 1 });
  tableBlock(table, 0, 0, rows, columns, {
    fill: "#FFFFFF",
    textStyle: { typeface: "Arial", fontSize, color: "#000000" },
    margins: { left: 6, right: 6, top: 3, bottom: 3 },
    anchor: "middle",
  });
  tableBlock(table, 0, 0, 1, columns, {
    fill: "#029676",
    textStyle: {
      typeface: "Arial",
      fontSize: headerFontSize,
      color: "#FFFFFF",
      bold: true,
    },
    anchor: "middle",
  });
  for (let index = 0; index < rowHeights.length; index += 1) {
    if (table.rows[index]) table.rows[index].height = rowHeights[index];
  }
}

await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });

const templateBytes = await fs.readFile(templatePath);
const templateSha256 = crypto.createHash("sha256").update(templateBytes).digest("hex");
const architectureSvg = await fs.readFile(architectureSvgPath, "utf8");

const presentation = await PresentationFile.importPptx(await FileBlob.load(templatePath));
presentation.slides.keep([0, 3, 5, 6, 8, 9, 11]);

const inspection = await presentation.inspect({
  select: "$.slides[*]",
  include: ["id", "index", "elements.id", "elements.name", "elements.kind", "elements.text"],
});
const slideRecords = inspection.records;

function elementRecord(slideIndex, predicate) {
  const hit = slideRecords[slideIndex].elements.find(predicate);
  if (!hit) throw new Error(`Missing expected element on slide ${slideIndex + 1}`);
  return hit;
}

function resolveByName(slideIndex, name) {
  return presentation.resolve(elementRecord(slideIndex, (element) => element.name === name).id);
}

function setBodyTitle(slideIndex, text) {
  const shape = resolveByName(slideIndex, "Title 1");
  shape.text = text;
  shape.text.style = {
    typeface: "Times New Roman",
    fontSize: 58.67,
    color: "#000000",
    bold: true,
    alignment: "left",
    autoFit: "shrinkText",
  };
}

function setSlideNumber(slideIndex, number) {
  const record = elementRecord(
    slideIndex,
    (element) => element.name?.startsWith("Slide Number Placeholder"),
  );
  const shape = presentation.resolve(record.id);
  shape.text = String(number);
  shape.text.style = {
    typeface: "Arial",
    fontSize: 16,
    color: "#FFFFFF",
    alignment: "center",
  };
}

function removeBody(slideIndex) {
  const record = elementRecord(slideIndex, (element) => element.name === "Content Placeholder 2");
  presentation.delete(record.id);
}

function setBulletBody(slideIndex, items) {
  const body = resolveByName(slideIndex, "Content Placeholder 2");
  body.text = makeNativeBulletParagraphs(items, {
    marginLeftPoints: 18,
    hangingPoints: 18,
    spaceAfterPoints: 8,
  });
  body.text.style = {
    typeface: "Arial",
    fontSize: 37.33,
    color: "#000000",
    alignment: "left",
    autoFit: "shrinkText",
  };
}

// Slide 1: cover.
const coverTitle = resolveByName(0, "Title 1");
coverTitle.text = "THIẾT KẾ BỘ VI XỬ LÝ 4 LÕI RISC-V\nDỰA TRÊN KIẾN TRÚC TẬP LỆNH RV32IMA";
coverTitle.text.style = {
  typeface: "Times New Roman",
  fontSize: 64,
  color: "#000000",
  bold: true,
  alignment: "center",
  autoFit: "shrinkText",
};
const reportType = resolveByName(0, "Text Placeholder 3");
reportType.text = "BÁO CÁO GIỮA KỲ KHÓA LUẬN TỐT NGHIỆP";
reportType.text.style = {
  typeface: "Arial",
  fontSize: 16,
  color: "#FFFFFF",
  bold: true,
  alignment: "left",
  autoFit: "shrinkText",
};
const authorBlock = resolveByName(0, "TextBox 7");
authorBlock.text.replace("GVHD:", "GVHD: TS. Nguyễn Minh Sơn");
authorBlock.text.replace("Tên Sinh viên 1", "Vũ Thành Lam");
authorBlock.text.replace("MSSV 1", "23520840");
authorBlock.text.replace("Tên Sinh viên 2", "Võ Lê Phước Lâm");
authorBlock.text.replace("MSSV 2", "23520838");
const dateShape = resolveByName(0, "Text Placeholder 2");
dateShape.text = "TP. Hồ Chí Minh, tháng 10 năm 2026";
dateShape.text.style = {
  typeface: "Arial",
  fontSize: 24,
  color: "#000000",
  italic: true,
  alignment: "center",
};
presentation.slides.items[0].speakerNotes.text = `Thông tin đề tài, sinh viên và GVHD: ${proposalPath}`;

// Slide 2: current scope.
setBodyTitle(1, "1. Phạm vi và kiến trúc hiện tại");
setSlideNumber(1, 2);
setBulletBody(1, [
  "Bốn lõi RV32IMA pipeline 5 tầng, tích hợp CSR, trap và các mức đặc quyền M/S/U.",
  "Mỗi lõi có L1 I-cache và D-cache riêng; hệ thống dùng L2 512 KiB và coherence MSI.",
  "AHB-Lite phục vụ miền core/cache; AXI4 kết nối DRAM, DMA và ngoại vi.",
  "Thiết kế hiện hành dùng địa chỉ vật lý; Sv32 chỉ là kiến trúc tham chiếu.",
]);
presentation.slides.items[1].speakerNotes.text = `Nguồn trạng thái và phạm vi active: ${currentReadmePath}`;

// Slide 3: architecture image from the current working tree.
setBodyTitle(2, "2. Kiến trúc SoC 4 lõi RV32IMA");
setSlideNumber(2, 3);
removeBody(2);
presentation.slides.items[2].images.add({
  svg: architectureSvg,
  alt: "Kiến trúc SoC bốn lõi RV32IMA dùng địa chỉ vật lý, L1 riêng, cache controller MSI, L2 dùng chung và miền AXI4",
  fit: "contain",
  position: { left: 218, top: 210, width: 844, height: 430 },
});
presentation.slides.items[2].speakerNotes.text = `Nguồn sơ đồ kiến trúc active: ${architectureSvgPath}`;

// Slide 4: progress table.
setBodyTitle(3, "3. Tiến độ hiện tại");
setSlideNumber(3, 4);
removeBody(3);
const progressValues = [
  ["Hạng mục", "Trạng thái", "Bằng chứng hiện có"],
  ["Core RV32IMA, CSR/trap", "PASS", "L0 core và privilege test đã chạy"],
  ["L1/L2, MSI, AHB-Lite", "PASS", "Cache/coherence và AHB integration PASS"],
  ["SoC 4 lõi", "PASS mô phỏng", "Hierarchy active 5/5, không có DUT failure"],
  ["Vivado implementation", "Đã hoàn tất", "Route hoàn tất, timing 102.041 MHz đạt"],
  ["DMA, DDR và FPGA", "Đang thực hiện", "Chưa có demo end-to-end trên board thật"],
];
const progressTable = presentation.slides.items[3].tables.add({
  rows: progressValues.length,
  columns: 3,
  left: 64,
  top: 214,
  width: 1152,
  height: 420,
  columnTracks: [
    { mode: "fr", value: 1.35 },
    { mode: "fr", value: 1 },
    { mode: "fr", value: 2.4 },
  ],
  values: progressValues,
});
styleTable(progressTable, {
  rows: progressValues.length,
  columns: 3,
  fontSize: 18,
  headerFontSize: 20,
  rowHeights: [46, 72, 76, 76, 72, 78],
});
tableBlock(progressTable, 1, 1, 4, 1, {
  fill: "#E7F5F1",
  textStyle: { typeface: "Arial", fontSize: 18, bold: true, color: "#006B55" },
});
tableBlock(progressTable, 5, 1, 1, 1, {
  fill: "#FFF4CC",
  textStyle: { typeface: "Arial", fontSize: 18, bold: true, color: "#7A5A00" },
});
presentation.slides.items[3].speakerNotes.text = [
  `Nguồn phạm vi active: ${currentReadmePath}`,
  `Nguồn kiểm chứng hierarchy: ${hierarchySummaryPath}`,
  `Nguồn implementation: ${implementationSummaryPath}`,
].join("\n");

// Slide 5: verification and implementation evidence.
setBodyTitle(4, "4. Kết quả kiểm chứng và hiện thực");
setSlideNumber(4, 5);
removeBody(4);
const verificationValues = [
  ["Mức kiểm chứng", "Kết quả"],
  ["L0: Core RV32IMA", "PASS"],
  ["L1: Core + L1", "PASS"],
  ["L2: Cache + AHB", "PASS"],
  ["L3: SoC 4 lõi", "PASS"],
  ["L4: AXI wrapper", "PASS"],
];
const verificationTable = presentation.slides.items[4].tables.add({
  rows: verificationValues.length,
  columns: 2,
  left: 64,
  top: 214,
  width: 500,
  height: 420,
  columnTracks: [{ mode: "fr", value: 2.2 }, { mode: "fr", value: 1 }],
  values: verificationValues,
});
styleTable(verificationTable, {
  rows: verificationValues.length,
  columns: 2,
  fontSize: 18,
  headerFontSize: 19,
  rowHeights: [48, 74, 74, 74, 74, 76],
});
tableBlock(verificationTable, 1, 1, 5, 1, {
  fill: "#E7F5F1",
  textStyle: { typeface: "Arial", fontSize: 18, bold: true, color: "#006B55" },
});

const implementationValues = [
  ["Chỉ số implementation", "Giá trị"],
  ["Tần số", "102.041 MHz"],
  ["WNS / WHS", "+0.029 / +0.036 ns"],
  ["LUT", "53,415 (67.96%)"],
  ["FF", "38,507 (24.50%)"],
  ["BRAM", "234 / 265 (88.30%)"],
  ["DSP", "16 / 400 (4.00%)"],
  ["Công suất ước tính", "1.286 W"],
];
const implementationTable = presentation.slides.items[4].tables.add({
  rows: implementationValues.length,
  columns: 2,
  left: 592,
  top: 214,
  width: 624,
  height: 420,
  columnTracks: [{ mode: "fr", value: 1.5 }, { mode: "fr", value: 1 }],
  values: implementationValues,
});
styleTable(implementationTable, {
  rows: implementationValues.length,
  columns: 2,
  fontSize: 17,
  headerFontSize: 18,
  rowHeights: [44, 54, 54, 54, 54, 54, 54, 52],
});
presentation.slides.items[4].speakerNotes.text = [
  `Hierarchy 5/5 PASS: ${hierarchySummaryPath}`,
  `Timing post-route: ${implementationSummaryPath}`,
  `Resource post-route: ${utilizationPath}`,
  `Power estimate, confidence Medium: ${powerPath}`,
].join("\n");

// Slide 6: remaining work.
setBodyTitle(5, "5. Công việc còn lại");
setSlideNumber(5, 6);
setBulletBody(5, [
  "Tích hợp DMA vào Block Design, hoàn thiện AXI master, AXI-Lite register và cache maintenance.",
  "Bring-up FPGA với clock, reset, DRAM, UART và luồng nạp chương trình từ SD hoặc SPI.",
  "Chạy workload 1/2/4 lõi, đo speedup, cache hit/miss và lưu lượng coherence trên cùng cấu hình.",
  "Hoàn thiện báo cáo, video demo và phân biệt rõ kiến trúc active với baseline Sv32 legacy.",
]);
presentation.slides.items[5].speakerNotes.text = `Nguồn công việc còn lại: ${currentReadmePath}`;

// Slide 7: midterm conclusion.
setBodyTitle(6, "6. Kết luận giữa kỳ");
setSlideNumber(6, 7);
setBulletBody(6, [
  "Hierarchy 4 lõi hiện hành đã PASS 5/5 mức kiểm chứng, không ghi nhận DUT failure.",
  "Vivado implementation đã route hoàn tất và đạt timing 102.041 MHz với WNS dương.",
  "BRAM sử dụng 88.30%, vì vậy phần DMA và tích hợp board cần kiểm soát chặt tài nguyên.",
  "Mốc tiếp theo là demo CPU tạo dữ liệu, DMA sao chép qua DDR và CPU kiểm tra dữ liệu đích trên FPGA.",
]);
presentation.slides.items[6].speakerNotes.text = [
  `Nguồn kiểm chứng: ${hierarchySummaryPath}`,
  `Nguồn timing và tài nguyên: ${implementationSummaryPath}; ${utilizationPath}`,
  `Nguồn kế hoạch: ${currentReadmePath}`,
].join("\n");

const requirements = {
  explicitTotalSlideCount: 7,
  requiredNativeTableOwnerSlides: [4, 5],
  requiredNativeChartOwnerSlides: [],
};
const fontPolicy = {
  basis: "reference",
  families: ["Times New Roman", "Arial"],
  referencePath: templatePath,
  referenceSha256: templateSha256,
};

const candidatePath = path.join(stagingDir, "candidate.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);
const result = await finalizePresentation({
  ...requirements,
  workspaceDir,
  candidatePath,
  finalPath,
  pythonExecutable: runtimePython,
  integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "12192000,6858000",
    "--validate-bullet-geometry",
    "--validate-heading-fit",
    "--require-native-table-slide", "4",
    "--require-native-table-slide", "5",
  ],
  requiredNativeTableOwnerSlides: requirements.requiredNativeTableOwnerSlides,
  fontPolicy,
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "BaoCao_GiuaKy_KLTN_QuadCore_RV32IMA_v3.validation.json"),
});

const finalPresentation = await PresentationFile.importPptx(await FileBlob.load(finalPath));
for (let index = 0; index < finalPresentation.slides.items.length; index += 1) {
  const slide = finalPresentation.slides.items[index];
  const stem = `slide-${String(index + 1).padStart(2, "0")}`;
  await saveBlob(path.join(previewDir, `${stem}.png`), await finalPresentation.export({ slide, format: "png", scale: 1 }));
  const layout = await slide.export({ format: "layout", detail: "full" });
  await fs.writeFile(path.join(previewDir, `${stem}.layout.json`), await layout.text(), "utf8");
}
await saveBlob(
  path.join(previewDir, "montage.webp"),
  await finalPresentation.export({ format: "webp", montage: true, scale: 1 }),
);
const finalInspect = await finalPresentation.inspect({
  select: "$.slides[*]",
  include: ["id", "index", "title", "elements.id", "elements.name", "elements.kind", "elements.text", "elements.position", "elements.style"],
});
await fs.writeFile(path.join(previewDir, "content.ndjson"), finalInspect.ndjson, "utf8");

console.log(JSON.stringify({ finalPath, result }, null, 2));
