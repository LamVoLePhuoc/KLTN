import fs from "node:fs/promises";
import path from "node:path";

const outDir = path.dirname(new URL(import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/, m => m.slice(1)));
const W = 1280, H = 720;
const C = { bg: "#F7FAFC", ink: "#102A43", navy: "#173F5F", blue: "#20639B", cyan: "#3CAEA3", gold: "#F6D55C", orange: "#ED553B", pale: "#E8F1F5", white: "#FFFFFF", gray: "#627D98" };

const esc = s => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const text = (x,y,s,size=24,weight=600,anchor="middle",fill=C.ink) => `<text x="${x}" y="${y}" font-family="Segoe UI, Arial, sans-serif" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}" fill="${fill}">${esc(s)}</text>`;
const box = (x,y,w,h,label,fill=C.white,stroke=C.blue,size=23) => {
  const labelColor = fill === C.navy ? C.white : C.ink;
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="${fill}" stroke="${stroke}" stroke-width="3"/>${label.split("\n").map((l,i)=>text(x+w/2,y+h/2+(i-(label.split("\n").length-1)/2)*28+8,l,size,650,"middle",labelColor)).join("")}`;
};
const arrow = (x1,y1,x2,y2,label="",color=C.gray) => `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${color}" stroke-width="4" marker-end="url(#arrow)"/>${label?text((x1+x2)/2,(y1+y2)/2-10,label,18,600,"middle",color):""}`;
const title = s => text(54,58,s,34,750,"start",C.navy);
const svg = body => `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="${C.gray}"/></marker></defs><rect width="${W}" height="${H}" fill="${C.bg}"/>${body}</svg>`;

const diagrams = {
  "system_overview.svg": svg(`${title("Kiến trúc tổng thể hệ thống 4 lõi RV32IMA")}
    ${[0,1,2,3].map(i=>box(50+i*300,100,260,150,`Core ${i}\nRV32IMA + Sv32 ATU/TLB\nL1 I$ + D$`,C.white,C.blue,20)).join("")}
    ${[0,1,2,3].map(i=>arrow(180+i*300,250,180+i*300,320)).join("")}
    ${box(70,320,1140,70,"AHB-Lite domain: 4 cores / 8 instruction-data request sources",C.pale,C.blue,24)}
    ${arrow(640,390,640,440)}
    ${box(260,440,340,100,"Cache controller (MMU)\nround-robin + MSI + snoop",C.white,C.orange,22)}
    ${box(680,440,340,100,"Shared L2 cache\n512 KB, 4-way, 32 B line",C.white,C.cyan,22)}
    ${arrow(600,490,680,490,"directory / line")}
    ${arrow(850,540,850,585)}
    ${box(100,585,1080,70,"AXI4 system domain: DMA / DRAM controller / peripherals",C.navy,C.navy,24)}
    ${box(170,665,210,42,"DMA",C.gold,C.gold,18)}${box(535,665,210,42,"DRAM",C.gold,C.gold,18)}${box(900,665,210,42,"SD / SPI",C.gold,C.gold,18)}`),

  "core_pipeline.svg": svg(`${title("Khối lõi RV32IMA pipeline 5 tầng")}
    ${box(55,165,180,100,"IF\nPC + Fetch",C.white,C.blue)}${arrow(235,215,280,215)}
    ${box(280,165,180,100,"ID\nDecode + RegFile",C.white,C.blue)}${arrow(460,215,505,215)}
    ${box(505,165,180,100,"EX\nALU + MDU",C.white,C.orange)}${arrow(685,215,730,215)}
    ${box(730,165,180,100,"MEM\nLoad Store + AMO",C.white,C.cyan)}${arrow(910,215,955,215)}
    ${box(955,165,180,100,"WB\nWriteback",C.white,C.blue)}
    ${box(160,350,300,95,"Control path\nMain decoder + ALU decoder",C.pale,C.blue,21)}
    ${box(500,350,300,95,"Hazard and forwarding\nload-use + multicycle stall",C.pale,C.blue,21)}
    ${box(840,350,300,95,"CSR / trap / privilege\nM, S, U + redirect",C.pale,C.orange,21)}
    ${arrow(310,350,370,265)}${arrow(650,350,650,265)}${arrow(990,350,865,265)}
    ${box(250,520,320,90,"RV32I + RV32M\nMUL/DIV multicycle",C.white,C.orange,22)}
    ${box(710,520,320,90,"RV32A\nLR/SC + 9 AMO operations",C.white,C.cyan,22)}
    ${arrow(570,565,710,565,"shared memory ordering")}`),

  "mmu.svg": svg(`${title("Khối dịch địa chỉ Sv32 (ATU) cho từng lõi")}
    ${box(45,135,210,90,"Fetch VA",C.white,C.blue)}${box(45,350,210,90,"Data VA",C.white,C.blue)}
    ${arrow(255,180,340,180)}${arrow(255,395,340,395)}
    ${box(340,120,250,120,"iTLB\n16 entries, 4 set x 4 way\n+ 4 superpage entries",C.white,C.cyan,20)}
    ${box(340,335,250,120,"dTLB\n16 entries, 4 set x 4 way\n+ 4 superpage entries",C.white,C.cyan,20)}
    ${arrow(590,180,700,180,"hit: PA")}${arrow(590,395,700,395,"hit: PA")}
    ${box(700,135,220,90,"Instruction PA",C.pale,C.blue)}${box(700,350,220,90,"Data PA",C.pale,C.blue)}
    ${arrow(465,240,640,500,"miss")}${arrow(465,455,640,500,"miss")}
    ${box(520,500,260,110,"Shared PTW\n2-level page walk\nA/D update",C.white,C.orange,22)}
    ${arrow(780,555,930,555,"PTE read/write")}${box(930,500,280,110,"Page tables in memory\nL1 leaf: 4 MiB\nL0 leaf: 4 KiB",C.white,C.gold,21)}
    ${box(65,545,310,85,"Region policy + permission\nU/S, SUM, MXR, R/W/X",C.pale,C.navy,21)}`),

  "mmu_control_fsm.svg": svg(`${title("FSM điều phối MMU (mmu_top)")}
    ${box(70,275,235,115,"IDLE\nTLB lookup + permission",C.white,C.blue,22)}
    ${box(520,110,240,115,"WALK\nPTW owns memory bus",C.white,C.orange,22)}
    ${box(970,275,235,115,"GATE\n1-cycle fault/resume",C.white,C.cyan,22)}
    ${arrow(305,300,520,185,"TLB miss / thiếu A-D")}
    ${arrow(760,185,970,300,"PTW success/fault")}
    ${arrow(970,365,305,365,"pulse result, next request")}
    ${arrow(520,205,305,330,"flush/context changed: discard")}
    ${text(85,455,"Đường nhanh",22,700,"start",C.navy)}
    ${arrow(190,430,190,390,"TLB hit hợp lệ")}
    ${text(490,500,"Các bất biến quan trọng",24,750,"start",C.navy)}
    ${text(490,545,"• Chỉ một PTW request tại một thời điểm",20,600,"start",C.gray)}
    ${text(490,580,"• Không refill khi lỗi hoặc context đã thay đổi",20,600,"start",C.gray)}
    ${text(490,615,"• Fault chỉ pulse tại GATE; core resume đồng bộ",20,600,"start",C.gray)}
    ${text(490,650,"• Data-side được ưu tiên khi I/D cùng miss",20,600,"start",C.gray)}`),

  "mmu_ptw_fsm.svg": svg(`${title("FSM Page Table Walker Sv32 (mmu_ptw)")}
    ${box(55,275,210,105,"PTW_IDLE\nnhận VPN/context",C.white,C.blue,21)}
    ${box(345,110,210,105,"L1_READ\nroot PTE",C.white,C.orange,21)}
    ${box(345,440,210,105,"L0_READ\nleaf 4 KiB",C.white,C.orange,21)}
    ${box(700,275,210,105,"AD_WRITE\nAMOOR A/D",C.white,C.cyan,21)}
    ${box(1010,275,210,105,"RESPONSE\nsuccess / fault",C.pale,C.navy,21)}
    ${arrow(265,300,345,185,"request")}
    ${arrow(450,215,450,440,"pointer")}
    ${arrow(555,165,1010,300,"leaf 4 MiB / fault")}
    ${arrow(555,490,1010,355,"leaf đủ A-D / fault")}
    ${arrow(555,465,700,345,"thiếu A/D")}
    ${arrow(555,190,700,300,"leaf thiếu A/D")}
    ${arrow(910,330,1010,330,"write OK/error")}
    ${arrow(1120,380,160,380,"done")}
    ${text(70,625,"Mọi lỗi đọc L1/L0 hoặc ghi A/D → access fault theo loại truy cập gốc; tuyệt đối không refill TLB.",21,650,"start",C.navy)}`),

  "cache_coherence.svg": svg(`${title("Phân cấp cache và coherence MSI")}
    ${[0,1,2,3].map(i=>box(45+i*300,115,245,100,`Core ${i} private L1\nI$ 32 KB + D$ 32 KB`,C.white,C.blue,20)).join("")}
    ${[0,1,2,3].map(i=>arrow(168+i*300,215,168+i*300,310,"request / snoop")).join("")}
    ${box(100,310,1080,105,"Shared cache controller (MMU)\n8-source round-robin, one atomic transaction, sharer directory, invalidate/downgrade snoops",C.white,C.orange,23)}
    ${arrow(500,415,500,485)}${arrow(780,485,780,415)}
    ${box(315,485,650,105,"Shared inclusive L2\n512 KB, 4-way set associative, writeback/refill",C.white,C.cyan,23)}
    ${arrow(640,590,640,650,"32-bit memory words")}
    ${box(470,650,340,55,"External memory / AXI4",C.navy,C.navy,22)}
    ${text(90,470,"States",20,700,"start",C.navy)}${box(90,495,120,55,"I",C.white,C.gray,22)}${box(90,560,120,55,"S",C.white,C.cyan,22)}${box(90,625,120,55,"M",C.white,C.orange,22)}`),

  "bus_domains.svg": svg(`${title("Hai miền bus và ranh giới giao thức")}
    ${[0,1,2,3].map(i=>box(50+i*290,105,225,80,`Core ${i}\nI$ / D$`,C.white,C.blue,20)).join("")}
    ${[0,1,2,3].map(i=>arrow(162+i*290,185,162+i*290,265)).join("")}
    ${box(80,265,1120,80,"AHB-Lite request adapters: HADDR, HWRITE, HTRANS, HREADY, HRESP",C.pale,C.blue,23)}
    ${arrow(640,345,640,410)}
    ${box(300,410,680,90,"Cache controller (MMU)\nserialized MSI + round-robin + back-pressure",C.white,C.orange,23)}
    ${arrow(640,500,640,560)}
    ${box(405,560,470,75,"Shared L2 / CPU memory port",C.white,C.cyan,23)}
    ${arrow(875,597,1030,597,"bridge")}${box(1030,555,200,85,"AXI4 wrapper\nread/write channels",C.white,C.navy,20)}
    ${box(60,555,230,85,"Protocol checks\ntimeout + sticky error",C.white,C.gold,20)}`),

  "boot_flow.svg": svg(`${title("Luồng boot và kiểm tra phần cứng")}
    ${box(45,260,180,100,"SD card\nprogram + input",C.white,C.gold)}${arrow(225,310,310,310,"SPI")}
    ${box(310,260,190,100,"SD / SPI\ncontroller",C.white,C.blue)}${arrow(500,310,590,310,"AXI4")}
    ${box(590,260,170,100,"DMA",C.white,C.orange)}${arrow(760,310,850,310,"burst")}
    ${box(850,260,190,100,"DRAM",C.white,C.cyan)}${arrow(1040,310,1160,310,"fetch/data")}
    ${box(1080,125,150,100,"Quad-core\nCPU",C.white,C.navy,21)}
    ${arrow(1155,225,1155,260)}
    ${box(430,95,360,90,"Boot controller\nprogram entry, release reset, status",C.pale,C.blue,22)}
    ${arrow(610,185,610,260)}${arrow(790,140,1080,165,"start PC")}
    ${arrow(1155,360,1155,510,"result")}${box(1010,510,220,90,"DMA writeback\noutput to SD",C.white,C.orange,21)}
    ${arrow(1010,555,225,555,"AXI4 + SPI",C.gray)}
    ${text(55,660,"The FPGA demo must prove the complete storage - memory - execution - storage path.",24,650,"start",C.navy)}`),

  "verification.svg": svg(`${title("Chiến lược kiểm chứng không dùng UVM")}
    ${box(45,120,250,95,"Unit testbenches\ncore, MMU, cache, bus",C.white,C.blue,21)}${arrow(295,168,365,168)}
    ${box(365,120,250,95,"Self-checking RTL\nscoreboard + PASS/FAIL",C.white,C.cyan,21)}${arrow(615,168,685,168)}
    ${box(685,120,250,95,"Integration tests\n4 cores + MSI + AHB",C.white,C.orange,21)}${arrow(935,168,1005,168)}
    ${box(1005,120,230,95,"Regression\nlogs and assertions",C.white,C.gold,21)}
    ${arrow(1120,215,1120,330)}
    ${box(885,330,350,100,"Vivado synthesis and implementation\nLUT, FF, BRAM, timing, power",C.white,C.navy,21)}
    ${arrow(885,380,760,380)}
    ${box(440,330,320,100,"FPGA bring-up\nclock, reset, DRAM, SD, UART",C.white,C.blue,21)}
    ${arrow(440,380,315,380)}
    ${box(45,330,270,100,"Automated hardware test\nSD - DMA - DRAM - CPU - SD",C.white,C.cyan,21)}
    ${box(175,535,930,90,"Evidence: waveform diagnosis + automatic PASS/FAIL + implementation reports",C.pale,C.blue,21)}`),

  "rtl_tree.svg": svg(`${title("Cấu trúc thư mục RTL theo block")}
    ${box(55,100,230,72,"rtl/",C.navy,C.navy,28)}
    ${arrow(285,136,355,136)}
    ${box(355,80,250,70,"core/",C.white,C.blue)}${box(355,170,250,70,"mmu/",C.white,C.cyan)}${box(355,260,250,70,"cache/",C.white,C.cyan)}${box(355,350,250,70,"coherence/",C.white,C.orange)}${box(355,440,250,70,"interconnect/ahb/",C.white,C.blue)}${box(355,530,250,70,"soc/",C.white,C.navy)}${box(355,620,250,55,"boot/ + debug/",C.white,C.gold,20)}
    ${box(720,80,500,70,"Pipeline, ISA, CSR, trap, privilege",C.pale,C.blue,20)}
    ${box(720,170,500,70,"Sv32 TLB/PTW + shared cache-controller MMU facade",C.pale,C.cyan,20)}
    ${box(720,260,500,70,"L1 I/D, shared L2, core-L1 wrapper",C.pale,C.cyan,20)}
    ${box(720,350,500,70,"MSI manager, directory, snoop engine",C.pale,C.orange,20)}
    ${box(720,440,500,70,"AHB-Lite master/slave adapters",C.pale,C.blue,20)}
    ${box(720,530,500,70,"Quad-core integration and AXI4 wrappers",C.pale,C.navy,20)}
    ${box(720,620,500,55,"Boot registers and optional trace buffers",C.pale,C.gold,19)}
    ${[115,205,295,385,475,565,647].map(y=>arrow(605,y,720,y)).join("")}`)
};

await fs.mkdir(outDir, { recursive: true });
for (const [name, content] of Object.entries(diagrams)) {
  await fs.writeFile(path.join(outDir, name), content, "utf8");
}
console.log(`Wrote ${Object.keys(diagrams).length} architecture diagrams to ${outDir}`);
