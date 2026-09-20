import fs from 'node:fs/promises';
import {FileBlob,PresentationFile} from 'file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
const root='C:/Users/ADMIN/Documents/GitHub/KLTN';
const p=await PresentationFile.importPptx(await FileBlob.load(root+'/output/BaoVeDeCuong_QuadCore_RV32IMA.pptx'));
for(let i=0;i<7;i++){
 const b=await p.export({slide:p.slides.getItem(i),format:'png',scale:2/3});
 await fs.writeFile(`${root}/.slide_work/final-${i+1}.png`,new Uint8Array(await b.arrayBuffer()));
}
console.log('Final file imported and all 7 slides rendered');
