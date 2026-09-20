import { FileBlob, PresentationFile } from "@oai/artifact-tool";

const sourcePath = "C:/Users/ADMIN/Documents/GitHub/KLTN/BaoVeDeCuong_QuadCore_RV32IMA.pptx";
const presentation = await PresentationFile.importPptx(await FileBlob.load(sourcePath));

for (const term of ["SD/SPI", "Ghi kết quả về SD", "DMA, SD/SPI", "SD/SPI - DMA - DRAM", "UVM"]) {
  const result = await presentation.inspect({
    kind: "slide,textbox,shape,table,notes,layout",
    search: term,
    maxChars: 12000,
  });
  console.log(`\n=== ${term} ===\n${result.ndjson}`);
}

const all = await presentation.inspect({
  kind: "slide,textbox,shape,table,notes,layout",
  maxChars: 50000,
});
console.log(`\n=== ALL ===\n${all.ndjson}`);
