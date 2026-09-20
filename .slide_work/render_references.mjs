import fs from 'node:fs/promises';
import {FileBlob,PresentationFile} from 'file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
const out='C:/Users/ADMIN/Documents/GitHub/KLTN/.slide_work';
const refs=[['BaoCao_BaoVeDeCuong.pptx',[0,1,2,6]],['DeCuongKTLN_report.pptx',[0,1,7,9,15]],['22520469_22520980_Chaining.pptx',[0,1,5,6,7]]];
for(let k=0;k<refs.length;k++){
 const [name,indices]=refs[k];
 const p=await PresentationFile.importPptx(await FileBlob.load('C:/Users/ADMIN/Downloads/'+name));
 await fs.writeFile(`${out}/ref${k+1}.inspect.txt`,(await p.inspect({kind:'layout,slide,textbox,image',maxChars:15000})).ndjson);
 for(const i of indices){
  try {const b=await p.export({slide:p.slides.getItem(i),format:'png',scale:0.65});await fs.writeFile(`${out}/ref${k+1}-${i+1}.png`,new Uint8Array(await b.arrayBuffer()));console.log('Rendered',k+1,i+1);}
  catch(e){console.log('ERROR',k+1,i+1,e.message);}
 }
}
