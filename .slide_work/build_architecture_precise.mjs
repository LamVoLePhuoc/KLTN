import fs from 'node:fs/promises';
import path from 'node:path';
import {Presentation,PresentationFile,FileBlob} from 'file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
import {finalizePresentation} from 'file:///C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.22227/skills/presentations/container_tools/artifact_tool_utils.mjs';
process.env.RUNTIME_NODE_MODULES='C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const root='C:/Users/ADMIN/Documents/GitHub/KLTN';
const build=root+'/.slide_work'; const out=root+'/output';
const SKILL='C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.22227/skills/presentations';
const python='C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe';
await fs.mkdir(build,{recursive:true}); await fs.mkdir(out,{recursive:true});
const W=1920,H=1080;
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const rect=(x,y,w,h,fill,stroke='#344746',sw=1.4,rx=0)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}"/>`;
const txt=(s,x,y,size=20,weight=400,anchor='middle',fill='#162727')=>`<text x="${x}" y="${y}" font-family="Arial,sans-serif" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}" fill="${fill}">${esc(s)}</text>`;
const multiline=(lines,x,y,size=18,weight=400,dy=22,fill='#162727')=>`<text x="${x}" y="${y}" font-family="Arial,sans-serif" font-size="${size}" font-weight="${weight}" text-anchor="middle" fill="${fill}">${lines.map((s,i)=>`<tspan x="${x}" dy="${i?dy:0}">${esc(s)}</tspan>`).join('')}</text>`;
const pathEl=(d,stroke='#182827',sw=2,marker='arrowBlack',dash='')=>`<path d="${d}" fill="none" stroke="${stroke}" stroke-width="${sw}" ${dash?`stroke-dasharray="${dash}"`:''} marker-end="url(#${marker})" stroke-linejoin="round" stroke-linecap="round"/>`;
let body='';
body+=txt('4-CORE CPU WRAPPER',32,31,24,700,'start');
body+=`<rect x="18" y="42" width="1884" height="773" fill="none" stroke="#52615E" stroke-width="2" stroke-dasharray="10 8"/>`;
const cores=[35,465,895,1325];
const tracePorts=[650,840,1000,1190];
for(let i=0;i<4;i++){
 const x=cores[i];
 body+=rect(x,58,390,345,'#FFFFFF','#51615E',1.6);
 body+=txt(`CORE ${i}`,x+195,84,20,700);
 body+=rect(x+24,100,138,46,'#FFF4D9','#DBA52F',1.2);
 body+=multiline(['Register File','(32 × XLen)'],x+93,120,14,700,17);
 body+=rect(x+225,100,135,46,'#FFF4D9','#DBA52F',1.2);
 body+=txt('ALU',x+292.5,129,17,700);
 body+=rect(x+24,166,336,66,'#E5F0FF','#3D83D2',1.5);
 body+=multiline(['Pipeline','(IF/ID/EX/MEM/WB)'],x+192,191,17,700,19);
 body+=rect(x+24,252,336,42,'#DDF7F6','#1B9298',1.4);
 body+=txt('MMU + TLB',x+192,279,17,700);
 body+=rect(x+42,309,130,34,'#F2E6FF','#8B2BE2',1.8,2);
 body+=txt('Trace Buffer',x+107,331,15,700);
 body+=rect(x+24,357,135,46,'#EAF5E6','#62AD56',1.3);
 body+=multiline(['L1 D-Cache','32KB'],x+91.5,376,15,700,17);
 body+=rect(x+225,357,135,46,'#EAF5E6','#62AD56',1.3);
 body+=multiline(['L1 I-Cache','32KB'],x+292.5,376,15,700,17);
 body+=`<line x1="${x+93}" y1="146" x2="${x+93}" y2="166" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 body+=`<line x1="${x+292}" y1="146" x2="${x+292}" y2="166" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 body+=`<line x1="${x+110}" y1="232" x2="${x+110}" y2="252" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 body+=`<line x1="${x+292}" y1="232" x2="${x+292}" y2="252" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 body+=pathEl(`M ${x+107} 294 L ${x+107} 309`);
 body+=pathEl(`M ${x+107} 343 L ${x+107} 357`);
 body+=pathEl(`M ${x+292} 294 L ${x+292} 357`);
 body+=`<line x1="${x+92}" y1="403" x2="${x+92}" y2="675" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 body+=`<line x1="${x+292}" y1="403" x2="${x+292}" y2="675" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
 // One-way trace input: source at Trace Buffer, arrow only at its dedicated monitor port.
 const sx=x+172, port=tracePorts[i], yy=(i===1||i===2)?435:420;
 body+=pathEl(`M ${sx} 326 L ${sx} ${yy} L ${port} ${yy} L ${port} 470`,'#6F22C6',3,'arrowPurple');
 body+=txt(`Trace${i}`,sx+10,yy-9,16,700,'start','#6F22C6');
}
// Shared conflict monitor.
body+=rect(520,470,800,180,'#F3E5FF','#7622C5',3,3);
body+=txt('SHARED CONFLICT MONITOR / ERROR HANDLER',920,501,22,700);
body+=txt('Compare valid physical data accesses',810,533,18,600);
body+=txt('Same PA + at least one Write => Conflict',810,560,19,700);
body+=txt('Inputs are observation-only; outputs are per-core control states',810,591,15,400,'middle','#52615E');
// State table.
body+=rect(1075,516,220,112,'#FFFFFF','#7622C5',1.5);
body+=rect(1075,516,220,27,'#E5CFFF','#7622C5',1.2);
body+=txt('CtrlState[1:0]',1185,535,16,700);
const states=[['00','Ignore'],['01','Halt'],['10','Resume'],['11','Reserved']];
states.forEach((r,j)=>{const y=543+j*21.2;body+=`<line x1="1075" y1="${y}" x2="1295" y2="${y}" stroke="#7622C5" stroke-width="0.9"/>`;body+=`<line x1="1125" y1="${y}" x2="1125" y2="${y+21.2}" stroke="#7622C5" stroke-width="0.9"/>`;body+=txt(r[0],1100,y+16,14,700);body+=txt(r[1],1210,y+16,14,500);});
body+=rect(720,441,400,25,'#FFFFFF','none',0);
body+=txt('ReqValid + PA[31:0] + R/W + CoreID[1:0]',920,459,16,700,'middle','#6F22C6');
// Four independent 2-bit one-way control outputs. Dashed paths, arrowheads only at Pipeline receivers.
const controls=[
 {d:'M 520 520 L 440 520 L 440 199 L 395 199',label:'CtrlState0[1:0]',lx:265,ly:157},
 {d:'M 740 470 L 740 405 L 835 405 L 835 199 L 825 199',label:'CtrlState1[1:0]',lx:695,ly:157},
 {d:'M 1100 470 L 1100 400 L 1265 400 L 1265 199 L 1255 199',label:'CtrlState2[1:0]',lx:1125,ly:157},
 {d:'M 1320 520 L 1700 520 L 1700 199 L 1685 199',label:'CtrlState3[1:0]',lx:1550,ly:157}
];
controls.forEach(c=>{body+=pathEl(c.d,'#B000E6',3,'arrowMagenta','9 7');body+=txt(c.label,c.lx,c.ly,17,700,'start','#9400C8');});
// One-way status output.
body+=pathEl('M 1320 588 L 1535 588','#6F22C6',3,'arrowPurple');
body+=txt('Conflict / Core ID / Address',1548,594,16,700,'start','#6F22C6');
// AHB.
body+=`<path d="M 45 675 L 1875 675 L 1848 700 L 1875 725 L 45 725 L 72 700 Z" fill="#9BF59B" stroke="#177A35" stroke-width="1.8"/>`;
body+=txt('HIGH-SPEED BUS (AHB)',960,710,28,700);
// L2 and coherence.
body+=rect(430,750,335,55,'#FFE3E1','#D94A43',1.5); body+=multiline(['SHARED L2 CACHE','512KB'],597.5,773,17,700,19);
body+=rect(900,750,370,55,'#CDEFF3','#238F9B',1.5); body+=txt('COHERENCE MANAGEMENT UNIT',1085,784,18,700);
body+=`<line x1="765" y1="801" x2="900" y2="801" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=`<line x1="598" y1="725" x2="598" y2="750" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=`<line x1="1085" y1="725" x2="1085" y2="750" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=txt('Uncached / MMIO bypass',1550,778,16,500);
body+=`<line x1="1580" y1="725" x2="1580" y2="825" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
// CPU memory port and AXI.
body+=rect(18,825,1884,42,'#FFE8CF','#7A5B3B',1.5); body+=txt('CPU MEMORY PORT',960,853,20,700);
body+=`<line x1="598" y1="805" x2="598" y2="825" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=`<path d="M 28 890 L 1892 890 L 1862 914 L 1892 938 L 28 938 L 58 914 Z" fill="#3B9CF4" stroke="#105C9E" stroke-width="2"/>`;body+=txt('SYSTEM BUS (AXI4)',960,925,29,700,'middle','#061C2D');
body+=`<line x1="960" y1="867" x2="960" y2="890" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=rect(155,965,280,46,'#FFF89C','#77761E',1.4);body+=txt('DMA CONTROLLER',295,995,18,700);
body+=rect(1030,955,325,46,'#E1F0DD','#62A653',1.4);body+=txt('MEMORY CONTROLLER',1192.5,985,18,700);
body+=`<line x1="295" y1="938" x2="295" y2="965" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=`<line x1="1192" y1="938" x2="1192" y2="955" stroke="#182827" stroke-width="2" marker-start="url(#arrowBlackStart)" marker-end="url(#arrowBlack)"/>`;
body+=rect(1080,1020,225,38,'#DCE5EB','#63798B',1.4,5);body+=txt('DDRAM',1192.5,1046,17,700);
body+=pathEl('M 1192 1001 L 1192 1020','#182827',2,'arrowBlack');
body+=txt('One-way 2-bit control per core: 00 Ignore · 01 Halt · 10 Resume · 11 Reserved',505,1072,14,700,'middle','#6F22C6');
body+=txt('Conflict policy remains separate from cache coherence and requires RTL verification.',1500,1072,13,500,'middle','#52615E');
const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs>
<marker id="arrowBlack" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#182827"/></marker>
<marker id="arrowBlackStart" markerWidth="8" markerHeight="8" refX="1" refY="4" orient="auto"><path d="M8,0 L0,4 L8,8 z" fill="#182827"/></marker>
<marker id="arrowPurple" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#6F22C6"/></marker>
<marker id="arrowMagenta" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#B000E6"/></marker>
</defs><rect width="100%" height="100%" fill="#FFFFFF"/>${body}</svg>`;
const svgPath=out+'/Architecture_QuadCore_SharedConflictMonitor_Corrected.svg';await fs.writeFile(svgPath,svg,'utf8');
const p=Presentation.create({slideSize:{width:W,height:H}});const slide=p.slides.add();slide.background.fill='#FFFFFF';
slide.images.add({blob:new TextEncoder().encode(svg),contentType:'image/svg+xml',alt:'Corrected quad-core shared conflict monitor architecture with four independent trace inputs and four one-way two-bit control outputs',fit:'contain',position:{left:0,top:0,width:W,height:H}});
slide.speakerNotes.textFrame.setText('Trace0..3 carry valid physical data access metadata into the shared monitor. CtrlState0..3 are independent one-way 2-bit outputs to each pipeline: 00 Ignore, 01 Halt, 10 Resume, 11 Reserved. A conflict occurs when simultaneous valid requests have the same physical address and at least one request is a write. This monitor is a proposed extension and remains separate from the coherence controller.');
const candidate=build+'/architecture_corrected_candidate.pptx';await (await PresentationFile.exportPptx(p)).save(candidate);
const finalPath=out+'/Architecture_QuadCore_SharedConflictMonitor_Corrected_v2.pptx';
await finalizePresentation({workspaceDir:root,candidatePath:candidate,finalPath,pythonExecutable:python,integrityValidatorPath:SKILL+'/container_tools/inspect_presentation_package_integrity.py',layoutValidatorPath:SKILL+'/container_tools/inspect_presentation_layout_geometry.py',layoutArgs:['--expected-slide-size-emu','18288000,10287000','--validate-heading-fit'],explicitTotalSlideCount:1,requiredNativeTableOwnerSlides:[],fontPolicy:{basis:'design',families:['Arial']},verifyArtifactToolImport:true,receiptPath:build+'/architecture_corrected_v2.validation.json'});
const verified=await PresentationFile.importPptx(await FileBlob.load(finalPath));const png=await verified.export({slide:verified.slides.getItem(0),format:'png',scale:1});await fs.writeFile(out+'/Architecture_QuadCore_SharedConflictMonitor_Corrected_v2.png',new Uint8Array(await png.arrayBuffer()));
const layout=await verified.slides.getItem(0).export({format:'layout'});await fs.writeFile(build+'/architecture_corrected.layout.json',await layout.text());
console.log(JSON.stringify({svgPath,finalPath,pngPath:out+'/Architecture_QuadCore_SharedConflictMonitor_Corrected_v2.png'}));
