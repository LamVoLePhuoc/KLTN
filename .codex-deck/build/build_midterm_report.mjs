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
const sourcePath = "C:/Users/ADMIN/Downloads/BaoCao_GiuaKy.pptx";
const integrationDiagramPath = path.join(workspaceDir, ".codex-deck/build/source-media/image7.png");
const stagingDir = path.join(workspaceDir, ".codex-deck/staging");
const previewDir = path.join(workspaceDir, ".codex-deck/final-preview");
const finalPath = path.join(workspaceDir, "output/BaoCao_GiuaKy_KLTN_7_slide_v2.pptx");

const { makeNativeBulletParagraphs, finalizePresentation } = await import(
  pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href
);

async function saveBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function tableBlock(table, row, column, rowCount, columnCount, options) {
  table.cells.block({ row, column, rowCount, columnCount }).assign(options);
}

function styleTable(table, { rows, columns, fontSize = 18, headerFontSize = fontSize, rowHeights = [] }) {
  table.borders.assign({ style: "solid", fill: "#8B8B8B", width: 1 });
  tableBlock(table, 0, 0, rows, columns, {
    fill: "#FFFFFF",
    textStyle: {
      typeface: "Arial",
      fontSize,
      color: "#000000",
    },
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

const templateBytes = await fs.readFile(templatePath);
const templateSha256 = crypto.createHash("sha256").update(templateBytes).digest("hex");

await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(templatePath));

// Keep the cover and six existing title/content slides from the official template.
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
  const numberRecord = elementRecord(
    slideIndex,
    (element) => element.name?.startsWith("Slide Number Placeholder"),
  );
  const shape = presentation.resolve(numberRecord.id);
  shape.text = String(number);
  shape.text.style = {
    typeface: "Arial",
    fontSize: 16,
    color: "#FFFFFF",
    alignment: "center",
  };
}

function removeBody(slideIndex) {
  const bodyRecord = elementRecord(slideIndex, (element) => element.name === "Content Placeholder 2");
  presentation.delete(bodyRecord.id);
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

// Slide 1: cover. Replace text in-place to keep the template's mixed formatting.
const coverTitle = resolveByName(0, "Title 1");
coverTitle.text = "HIỆN THỰC HỆ THỐNG SoC TÍCH HỢP KHỐI TĂNG TỐC CNN-LSTM\nỨNG DỤNG TRONG ƯỚC LƯỢNG HUYẾT ÁP TỪ TÍN HIỆU PPG";
coverTitle.text.style = {
  typeface: "Times New Roman",
  fontSize: 64,
  color: "#000000",
  bold: true,
  alignment: "center",
  autoFit: "shrinkText",
};
const authorBlock = resolveByName(0, "TextBox 7");
authorBlock.text.replace("GVHD:", "GVHD: Trần Thị Điểm");
authorBlock.text.replace("Tên Sinh viên 1", "Nguyễn Gia Phúc");
authorBlock.text.replace("MSSV 1", "22521126");
authorBlock.text.replace("Tên Sinh viên 2", "Nguyễn Hải Thành");
authorBlock.text.replace("MSSV 2", "22521356");
const dateShape = resolveByName(0, "Text Placeholder 2");
dateShape.text = "TP. Hồ Chí Minh, năm 2026";
dateShape.text.style = {
  typeface: "Arial",
  fontSize: 24,
  color: "#000000",
  italic: true,
  alignment: "center",
};
presentation.slides.items[0].speakerNotes.text = `Nguồn nội dung: ${sourcePath}`;

// Slide 2: progress table.
setBodyTitle(1, "1. Tổng quan tiến độ thực hiện");
setSlideNumber(1, 2);
removeBody(1);
const progressValues = [
  ["Công việc", "Nội dung thực hiện", "Trạng thái"],
  ["Khảo sát đề tài", "Khảo sát bài toán PPG-BP, mô hình CNN-LSTM và hướng triển khai FPGA/SoC", "Đã hoàn thành"],
  ["Mô hình tham chiếu", "Huấn luyện CNN-LSTM, tạo trọng số và đầu ra tham chiếu", "Đã hoàn thành"],
  ["Hiện thực RTL", "Thiết kế Convolution, Pooling, LSTM, Fully Connected và Controller", "Đã hoàn thành"],
  ["Mô phỏng kiểm chứng", "Kiểm chứng từng lớp và toàn hệ thống", "Đã hoàn thành"],
  ["Tích hợp SoC", "Tích hợp bộ tăng tốc vào SoC KV260 qua giao tiếp AXI", "Đã hoàn thành"],
  ["Đánh giá và tối ưu", "Đánh giá trên KV260, tối ưu timing, latency và tài nguyên", "Đang thực hiện"],
];
const progressTable = presentation.slides.items[1].tables.add({
  rows: progressValues.length,
  columns: 3,
  left: 64,
  top: 214,
  width: 1152,
  height: 420,
  columnTracks: [
    { mode: "fr", value: 1.25 },
    { mode: "fr", value: 2.85 },
    { mode: "fr", value: 1.1 },
  ],
  values: progressValues,
});
styleTable(progressTable, {
  rows: progressValues.length,
  columns: 3,
  fontSize: 17,
  headerFontSize: 19,
  rowHeights: [42, 70, 58, 70, 52, 58, 70],
});
presentation.slides.items[1].speakerNotes.text = `Nguồn: ${sourcePath}, slide “Tổng quan tiến độ công việc của đề tài nghiên cứu”.`;

// Slide 3: reference model architecture.
setBodyTitle(2, "2. Kiến trúc mô hình tham chiếu CNN-LSTM");
setSlideNumber(2, 3);
removeBody(2);
const architectureValues = [
  ["Layer", "Input", "Output", "Params"],
  ["Conv1", "250 × 1", "250 × 16", "128"],
  ["MaxPool1", "250 × 16", "125 × 16", "–"],
  ["Conv2", "125 × 16", "125 × 32", "2,592"],
  ["MaxPool2", "125 × 32", "62 × 32", "–"],
  ["Conv3", "62 × 32", "62 × 64", "6,208"],
  ["LSTM", "62 × 64", "32", "12,416"],
  ["FC1", "32", "64", "2,112"],
  ["FC2", "64", "32", "2,080"],
  ["FC3", "32", "2", "66"],
  ["Total Parameters", "", "", "25,602"],
];
const architectureTable = presentation.slides.items[2].tables.add({
  rows: architectureValues.length,
  columns: 4,
  left: 112,
  top: 214,
  width: 1056,
  height: 420,
  columnTracks: [
    { mode: "fr", value: 1.35 },
    { mode: "fr", value: 1 },
    { mode: "fr", value: 1 },
    { mode: "fr", value: 0.9 },
  ],
  values: architectureValues,
});
styleTable(architectureTable, {
  rows: architectureValues.length,
  columns: 4,
  fontSize: 18,
  headerFontSize: 20,
  rowHeights: [38, 36, 36, 36, 36, 36, 36, 36, 36, 36, 42],
});
tableBlock(architectureTable, architectureValues.length - 1, 0, 1, 4, {
  fill: "#E7F5F1",
  textStyle: { typeface: "Arial", fontSize: 18, bold: true, color: "#000000" },
});
presentation.slides.items[2].speakerNotes.text = `Nguồn: ${sourcePath}, slide “Kiến trúc mô hình tham chiếu CNN-LSTM”.`;

// Slide 4: proposed accelerator solution.
setBodyTitle(3, "3. Giải pháp đề xuất");
setSlideNumber(3, 4);
setBulletBody(3, [
  "Dùng datapath chung cho các lớp Convolution, Fully Connected và LSTM.",
  "Mảng 16 processing element, mỗi PE tích hợp pipeline MAC để tăng thông lượng.",
  "Buffer và FIFO tái sử dụng dữ liệu, giảm số lần truy cập bộ nhớ.",
  "LUT thực hiện hàm sigmoid và tanh, giúp giảm độ phức tạp phần cứng.",
]);
presentation.slides.items[3].speakerNotes.text = `Nguồn: ${sourcePath}, slide “Giải pháp đề xuất”.`;

// Slide 5: SoC integration diagram.
setBodyTitle(4, "4. Tích hợp CNN-LSTM trên SoC");
setSlideNumber(4, 5);
removeBody(4);
const integrationDiagramBytes = await fs.readFile(integrationDiagramPath);
presentation.slides.items[4].images.add({
  blob: integrationDiagramBytes.buffer.slice(
    integrationDiagramBytes.byteOffset,
    integrationDiagramBytes.byteOffset + integrationDiagramBytes.byteLength,
  ),
  contentType: "image/png",
  alt: "Sơ đồ tích hợp IP CNN-LSTM giữa Processing System và Programmable Logic qua AXI",
  fit: "contain",
  position: { left: 148, top: 218, width: 984, height: 385 },
});
const caption = presentation.slides.items[4].shapes.add({
  geometry: "textbox",
  name: "integration-caption",
  position: { left: 118, top: 605, width: 1044, height: 38 },
  fill: "none",
  line: { style: "solid", fill: "none", width: 0 },
});
caption.text = "PS điều phối CPU, DMA và DDR; PL thực thi IP CNN-LSTM; dữ liệu trao đổi qua AXI.";
caption.text.style = {
  typeface: "Arial",
  fontSize: 22,
  color: "#000000",
  alignment: "center",
  autoFit: "shrinkText",
};
presentation.slides.items[4].speakerNotes.text = [
  `Nguồn sơ đồ và nội dung: ${sourcePath}, slide “Tích hợp CNN-LSTM trên SoC”.`,
  "PS gồm CPU, DMA và DDR memory. DMA truyền input, weight và bias vào IP.",
  "PL chứa khối tăng tốc CNN-LSTM; kết quả suy luận ghi về bộ nhớ qua AXI.",
].join("\n");

// Slide 6: measured results.
setBodyTitle(5, "5. Kết quả đánh giá");
setSlideNumber(5, 6);
removeBody(5);
const modelValues = [
  ["Chỉ số", "MAE (mmHg)", "ME (mmHg)", "SD (mmHg)", "AAMI", "BHS"],
  ["SBP", "5.199", "-0.275", "7.869", "PASS", "B"],
  ["DBP", "3.316", "-0.802", "5.016", "PASS", "A"],
];
const modelTable = presentation.slides.items[5].tables.add({
  rows: 3,
  columns: 6,
  left: 64,
  top: 214,
  width: 1152,
  height: 116,
  columnTracks: [
    { mode: "fr", value: 0.8 }, { mode: "fr", value: 1.2 }, { mode: "fr", value: 1.1 },
    { mode: "fr", value: 1.1 }, { mode: "fr", value: 0.8 }, { mode: "fr", value: 0.7 },
  ],
  values: modelValues,
});
styleTable(modelTable, { rows: 3, columns: 6, fontSize: 17, headerFontSize: 18, rowHeights: [42, 37, 37] });

const resourceValues = [
  ["Tài nguyên IP", "Giá trị"],
  ["Clock", "135 MHz"],
  ["LUT", "15,334"],
  ["FF", "42,164"],
  ["BRAM", "5"],
  ["DSP", "17"],
  ["Power", "0.087 W"],
];
const resourceTable = presentation.slides.items[5].tables.add({
  rows: 7,
  columns: 2,
  left: 64,
  top: 350,
  width: 540,
  height: 285,
  columnTracks: [{ mode: "fr", value: 1.3 }, { mode: "fr", value: 1 }],
  values: resourceValues,
});
styleTable(resourceTable, { rows: 7, columns: 2, fontSize: 17, headerFontSize: 18, rowHeights: [39, 41, 41, 41, 41, 41, 41] });

const latencyValues = [
  ["Layer", "Latency (ms)"],
  ["Conv1 + Pool", "0.5624"],
  ["Conv2 + Pool", "0.7338"],
  ["Conv3", "1.2533"],
  ["LSTM", "1.3616"],
  ["FC", "0.0188"],
];
const latencyTable = presentation.slides.items[5].tables.add({
  rows: 6,
  columns: 2,
  left: 628,
  top: 350,
  width: 588,
  height: 285,
  columnTracks: [{ mode: "fr", value: 1.35 }, { mode: "fr", value: 1 }],
  values: latencyValues,
});
styleTable(latencyTable, { rows: 6, columns: 2, fontSize: 17, headerFontSize: 18, rowHeights: [39, 49, 49, 49, 49, 49] });
presentation.slides.items[5].speakerNotes.text = `Nguồn: ${sourcePath}, slide “Kết quả đánh giá”.`;

// Slide 7: conclusion and next steps.
setBodyTitle(6, "6. Kết luận và hướng phát triển");
setSlideNumber(6, 7);
setBulletBody(6, [
  "Đã xây dựng mô hình tham chiếu CNN-LSTM.",
  "Đã hiện thực bộ tăng tốc ở mức RTL và tích hợp vào SoC KV260.",
  "Đã kiểm chứng mô phỏng theo từng lớp và toàn hệ thống.",
  "Đang kiểm chứng kết quả thực tế trên KV260 và tối ưu timing, latency, tài nguyên.",
  "Công việc tiếp theo là hoàn thiện đánh giá và báo cáo khóa luận.",
]);
presentation.slides.items[6].speakerNotes.text = `Nguồn: ${sourcePath}, slide “Kết luận và hướng phát triển”.`;

const requirements = {
  explicitTotalSlideCount: 7,
  requiredNativeTableOwnerSlides: [2, 3, 6],
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
    "--require-native-table-slide", "2",
    "--require-native-table-slide", "3",
    "--require-native-table-slide", "6",
  ],
  requiredNativeTableOwnerSlides: requirements.requiredNativeTableOwnerSlides,
  fontPolicy,
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, "BaoCao_GiuaKy_KLTN_7_slide_v2.validation.json"),
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
