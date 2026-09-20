import path from "node:path";
import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const workspaceDir = "C:/Users/ADMIN/Documents/GitHub/KLTN";
const sourcePath = path.join(workspaceDir, "BaoVeDeCuong_QuadCore_RV32IMA.pptx");
const buildDir = path.join(workspaceDir, ".slide_work/remove_uvm_sd");
const stagingDir = path.join(workspaceDir, ".codex-finalizer");
const finalPath = path.join(workspaceDir, "output/BaoVeDeCuong_QuadCore_RV32IMA_v6_khong_UVM_SD.pptx");
const skillDir = "C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.22227/skills/presentations";
const pythonExecutable = "C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";

await fs.mkdir(buildDir, { recursive: true });
await fs.mkdir(stagingDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });

const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));

const replaceExact = (anchorId, oldText, newText) => {
  const item = presentation.resolve(anchorId);
  const current = item.text?.toString?.() ?? item.text?.text ?? String(item.text ?? "");
  if (!current.includes(oldText)) {
    throw new Error(`Expected text not found in ${anchorId}: ${oldText}`);
  }
  item.text.replace(oldText, newText);
};

// Slide 5: keep DMA in scope, remove the SD/SPI interface from the integration method.
const contentTable = presentation.resolve("tb/4za9kba9");
contentTable.cells.set(
  3,
  1,
  "Ghép 4 lõi, L2, MESI và bus AHB/AXI4. Tích hợp DMA.",
);

// Slide 7: present a storage-neutral FPGA demo flow.
replaceExact("sh/j2tofmx0", "SD/SPI → DMA → DRAM", "Nạp chương trình vào DRAM");
replaceExact("sh/54v6hwf6", "Ghi kết quả về SD", "Kiểm tra kết quả PASS/FAIL");
presentation.resolve("sh/j2tofmx0").name = "Nạp chương trình vào DRAM";
presentation.resolve("sh/54v6hwf6").name = "Kiểm tra kết quả PASS/FAIL";
const demoNotes = presentation.resolve("nt/gnmp4jqx");
demoNotes.setText(
  "Quy trình bên trái: kiểm chứng khối riêng gồm pipeline, MMU/TLB, cache và bus; sau đó tích hợp lõi đơn, cuối cùng hệ 4 lõi. Chỉ chuyển sang mức tiếp theo khi các kiểm tra bắt buộc PASS; FAIL quay lại khối liên quan để sửa và chạy lại. Hai vòng phản hồi trên sơ đồ minh họa quy trình debug, không ngụ ý lỗi nào cũng nằm ở cùng một module. Spike chỉ đối chiếu kết quả thanh ghi/bộ nhớ I/M/A, không đối chiếu toàn bộ CSR/trap, MMU hay hệ đa lõi. Demo bên phải là luồng dự kiến: nạp chương trình vào DRAM, CPU 4 lõi thực thi, sau đó kiểm tra kết quả PASS/FAIL và đo thời gian thực thi. FPGA đích VCU129 theo đề cương.",
);

// Slide 8: remove the SD/SPI work package and assignment.
const monthlyPlan = presentation.resolve("tb/t0ruh0ny");
monthlyPlan.cells.set(
  3,
  0,
  "DMA và tích hợp hệ thống",
);
replaceExact(
  "sh/3mp0ryhw",
  "Lâm: lõi, L1, MMU/TLB, SD/SPI.",
  "Lâm: lõi, L1, MMU/TLB.",
);
presentation.resolve("sh/3mp0ryhw").name = "Phân công nhóm";

// Slide 9: keep the DMA-to-memory milestone without an SD-card dependency.
const weeklyPlan = presentation.resolve("tb/xwjydgrm");
weeklyPlan.cells.set(
  3,
  1,
  "DMA - DRAM PASS trong mô phỏng",
);

const remaining = await presentation.inspect({
  kind: "slide,textbox,shape,table,notes",
  search: "UVM|SD/SPI|SD card|thẻ SD|kết quả về SD|từ SD",
  maxChars: 12000,
});
const forbidden = /UVM|SD\s*\/\s*SPI|SD\s*card|thẻ\s+SD|kết quả\s+về\s+SD|từ\s+SD/i;
const remainingTextHits = remaining.ndjson
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => JSON.parse(line))
  .filter((entry) => forbidden.test(entry.text ?? entry.textPreview ?? ""));
if (remainingTextHits.length) {
  throw new Error(`Out-of-scope visible text remains:\n${JSON.stringify(remainingTextHits, null, 2)}`);
}

const candidatePath = path.join(stagingDir, "BaoVeDeCuong_QuadCore_RV32IMA_v6_candidate.pptx");
await (await PresentationFile.exportPptx(presentation)).save(candidatePath);

const { finalizePresentation } = await import(
  pathToFileURL(path.join(skillDir, "container_tools/artifact_tool_utils.mjs")).href
);
const requirements = {
  explicitTotalSlideCount: 9,
  requiredNativeTableOwnerSlides: [5, 8, 9],
  requiredNativeChartOwnerSlides: [],
};

const result = await finalizePresentation({
  ...requirements,
  workspaceDir,
  candidatePath,
  finalPath,
  pythonExecutable,
  integrityValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(skillDir, "container_tools/inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "18288000,10287000",
    "--validate-bullet-geometry",
    "--validate-heading-fit",
    "--require-native-table-slide", "5",
    "--require-native-table-slide", "8",
    "--require-native-table-slide", "9",
  ],
  requiredNativeTableOwnerSlides: requirements.requiredNativeTableOwnerSlides,
  verifyArtifactToolImport: true,
  receiptPath: path.join(stagingDir, `${path.basename(finalPath)}.validation.json`),
});

console.log(JSON.stringify({ finalPath, candidatePath, result }, null, 2));
