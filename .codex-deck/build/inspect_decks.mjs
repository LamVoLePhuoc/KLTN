import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, PresentationFile } from "file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const sources = [
  {
    key: "midterm",
    file: "C:/Users/ADMIN/Downloads/BaoCao_GiuaKy.pptx",
  },
  {
    key: "template",
    file: "C:/Users/ADMIN/Downloads/KTMT_KLTN_Phu luc 6_Mau bao cao bao ve.pptx",
  },
];

async function saveBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

for (const source of sources) {
  const outDir = path.resolve(`.codex-deck/build/${source.key}`);
  await fs.mkdir(outDir, { recursive: true });
  const presentation = await PresentationFile.importPptx(
    await FileBlob.load(source.file),
  );
  const content = await presentation.inspect({
    select: "$.slides[*]",
    include: [
      "id",
      "index",
      "layout",
      "title",
      "elements.id",
      "elements.name",
      "elements.kind",
      "elements.text",
      "elements.alt",
      "elements.position",
      "elements.style",
      "elements.paragraphs",
      "notes.text",
    ],
  });
  await fs.writeFile(
    path.join(outDir, "content.ndjson"),
    content.ndjson,
    "utf8",
  );
  const structural = {
    slideSize: presentation.slideSize,
    slideCount: presentation.slides.items.length,
    masters: presentation.masters.items.map((m) => ({
      id: m.id,
      name: m.name,
    })),
    layouts: presentation.layouts.items.map((l) => ({
      id: l.id,
      name: l.name,
      placeholders: l.placeholders.summary(),
    })),
  };
  await fs.writeFile(
    path.join(outDir, "structure.json"),
    JSON.stringify(structural, null, 2),
    "utf8",
  );
  for (let index = 0; index < presentation.slides.items.length; index += 1) {
    const slide = presentation.slides.items[index];
    const stem = `slide-${String(index + 1).padStart(2, "0")}`;
    await saveBlob(
      path.join(outDir, `${stem}.png`),
      await presentation.export({ slide, format: "png", scale: 1 }),
    );
    const layout = await slide.export({ format: "layout", detail: "full" });
    await fs.writeFile(path.join(outDir, `${stem}.layout.json`), await layout.text(), "utf8");
  }
  await saveBlob(
    path.join(outDir, "montage.webp"),
    await presentation.export({ format: "webp", montage: true, scale: 1 }),
  );
  console.log(`${source.key}: ${structural.slideCount} slides`);
}
