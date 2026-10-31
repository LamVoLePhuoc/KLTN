import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, PresentationFile } from "file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const workspace = "C:/Users/ADMIN/Documents/GitHub/KLTN";
const sources = [
  ["proposal", path.join(workspace, "BaoVeDeCuong_QuadCore_RV32IMA.pptx")],
  ["quadcore", path.join(workspace, "QuadCore_RV32IMA.pptx")],
  ["architecture", path.join(workspace, "output/KLTN_QuadCore_RV32IMA_ToanBoKienTruc_v2.pptx")],
  ["progress", path.join(workspace, "deliverables/Bao_cao_tien_do_MMU_Cache_DMA_2026-10-25_ready.pptx")],
];

async function saveBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

for (const [key, file] of sources) {
  const outDir = path.join(workspace, ".codex-deck/quadcore-inspect", key);
  await fs.mkdir(outDir, { recursive: true });
  const presentation = await PresentationFile.importPptx(await FileBlob.load(file));
  const content = await presentation.inspect({
    select: "$.slides[*]",
    include: [
      "id", "index", "layout", "title",
      "elements.id", "elements.name", "elements.kind", "elements.text",
      "elements.alt", "elements.position", "elements.style", "notes.text",
    ],
  });
  await fs.writeFile(path.join(outDir, "content.ndjson"), content.ndjson, "utf8");
  await saveBlob(
    path.join(outDir, "montage.webp"),
    await presentation.export({ format: "webp", montage: true, scale: 1 }),
  );
  for (let index = 0; index < presentation.slides.items.length; index += 1) {
    const slide = presentation.slides.items[index];
    const stem = `slide-${String(index + 1).padStart(2, "0")}`;
    await saveBlob(
      path.join(outDir, `${stem}.png`),
      await presentation.export({ slide, format: "png", scale: 1 }),
    );
  }
  console.log(`${key}: ${presentation.slides.items.length} slides`);
}
