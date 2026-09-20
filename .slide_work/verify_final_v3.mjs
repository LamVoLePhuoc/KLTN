import fs from 'node:fs/promises';
import {FileBlob,PresentationFile} from 'file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
const root='C:/Users/ADMIN/Documents/GitHub/KLTN';
const p=await PresentationFile.importPptx(await FileBlob.load(root+'/output/BaoVeDeCuong_QuadCore_RV32IMA_v3_Diagram.pptx'));
for(let i=0;i<8;i++){
 const b=await p.export({slide:p.slides.getItem(i),format:'png',scale:2/3});
 await fs.writeFile(`${root}/.slide_work/final-v3-${i+1}.png`,new Uint8Array(await b.arrayBuffer()));
}
console.log('Final file imported and all 8 slides rendered');



