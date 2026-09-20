import fs from 'node:fs/promises';
import {FileBlob,PresentationFile} from 'file:///C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
import {finalizePresentation} from 'file:///C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.22227/skills/presentations/container_tools/artifact_tool_utils.mjs';
const workspaceDir='C:/Users/ADMIN/Documents/GitHub/KLTN';
const build=workspaceDir+'/.slide_work';
const SKILL_DIR='C:/Users/ADMIN/.codex/plugins/cache/openai-primary-runtime/presentations/26.909.22227/skills/presentations';
const python='C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe';
process.env.RUNTIME_NODE_MODULES='C:/Users/ADMIN/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const p=await PresentationFile.importPptx(await FileBlob.load(build+'/template_clean.pptx'));
const C={green:'#007A60',teal:'#079D93',ink:'#172A2A',gray:'#52615E',pale:'#EDF5F1',white:'#FFFFFF'};
const font='Arial';
function text(s,txt,x,y,w,h,size=39,bold=false,color=C.ink,align='left'){
 const sh=s.shapes.add({geometry:'textbox',name:txt.slice(0,70),position:{left:x,top:y,width:w,height:h},fill:'none',line:{fill:'none',width:0}});
 sh.text=txt;
 sh.text.style={typeface:font,fontSize:size,bold,color,alignment:align,verticalAlignment:'top',autoFit:'none',wrap:'square',insets:{left:0,right:0,top:0,bottom:0}};
 return sh;
}
function title(s,t){text(s,t,66,174,1780,76,48,true,C.green);}
function heading(s,t,y,x=100,w=1720){text(s,t,x,y,w,55,40,true,C.green);}
function body(s,t,y,x=100,w=1720,h=105,size=39){return text(s,t,x,y,w,h,size);}
function note(s,t){s.speakerNotes.textFrame.setText(t);}
function page(s,i){text(s,String(i),1800,1010,60,40,26,false,C.gray,'right');}
function table(s,values,x,y,width,height,widths,size=34){
 const tb=s.tables.add({rows:values.length,columns:values[0].length,left:x,top:y,width,height,columnWidths:widths,values});
 tb.styleOptions={headerRow:false,bandedRows:false};
 tb.borders.assign({style:'solid',fill:'#CBDAD4',width:1});
 for(let r=0;r<values.length;r++) for(let c=0;c<values[0].length;c++){
  const cell=tb.getCell(r,c);cell.fill=r===0?C.green:(r%2===1?C.pale:C.white);
  cell.text.style={typeface:font,fontSize:size,bold:r===0,color:r===0?C.white:C.ink,alignment:c===0?'left':'left',verticalAlignment:'middle',autoFit:'none',insets:{left:20,right:18,top:12,bottom:12}};
 }
 return tb;
}
for(let i=0;i<7;i++){
 const s=p.slides.getItem(i);
 for(const sh of s.shapes.items??[]){if(sh.text?.toString?.().includes('FACULTY'))sh.text.style={typeface:font};}
 if(i>0)page(s,i+1);
}
{
const s=p.slides.getItem(0);
text(s,'BẢO VỆ ĐỀ CƯƠNG KHÓA LUẬN TỐT NGHIỆP',215,270,1540,70,48,true,C.teal,'center');
text(s,'THIẾT KẾ BỘ VI XỬ LÝ 4 LÕI RISC-V\nDỰA TRÊN KIẾN TRÚC TẬP LỆNH RV32IMA',180,405,1600,155,54,true,C.green,'center');
text(s,'GVHD: TS. Nguyễn Minh Sơn',230,650,1490,60,42,true,C.green);
text(s,'Vũ Thành Lam',230,742,720,58,40,true);text(s,'23520840',920,742,450,58,40);
text(s,'Võ Lê Phước Lâm',230,822,720,58,40,true);text(s,'23520838',920,822,450,58,40);
text(s,'TP. Hồ Chí Minh, tháng 9 năm 2026',230,968,1490,50,32,false,C.gray,'center');
note(s,'Nhóm trình bày đề cương thiết kế bộ vi xử lý RISC-V 4 lõi RV32IMA. Báo cáo gồm tổng quan đề tài, mục tiêu, nội dung và phương pháp thực hiện, kế hoạch thực hiện.\nNguồn: 23520840_23520838_DeCuongKLTN.docx, tên đề tài và thông tin nhóm.');
}
{
const s=p.slides.getItem(1);title(s,'1. Tổng quan đề tài');
heading(s,'Nhu cầu xử lý nhiều tác vụ đồng thời',292);
body(s,'Các hệ thống nhúng như khối điều khiển bay UAV đặt ra nhu cầu xử lý dữ liệu cảm biến, điều khiển và giao tiếp cùng lúc.',355,100,1720,112,40);
heading(s,'Lựa chọn kiến trúc RISC-V',508);
body(s,'Kiến trúc tập lệnh mở cho phép nhóm chủ động thiết kế và tùy biến bộ xử lý ở mức RTL, phù hợp với mục tiêu nghiên cứu phần cứng.',572,100,1720,112,40);
heading(s,'Bài toán của khóa luận',725);
body(s,'Xây dựng hệ 4 lõi RV32IMA có bộ nhớ đệm và quản lý bộ nhớ, bảo đảm dữ liệu chia sẻ nhất quán và kiểm chứng trên FPGA.',789,100,1720,118,40);
note(s,'Mở đầu bằng nhu cầu ứng dụng thực tế. UAV chỉ là ví dụ tạo động lực, khóa luận không cam kết xây dựng hoặc chứng nhận hệ điều khiển bay. Nền tảng tham khảo trong khoa gồm hệ 2 lõi RV32IMFA và hệ 2 lõi RV32IA có cache/coherence. Đóng góp nhóm hướng tới là tích hợp hệ 4 lõi RV32IMA với L1/L2, coherence và MMU theo từng lõi, rồi đánh giá bằng mô phỏng và FPGA. Tránh khẳng định mọi nghiên cứu quốc tế đều chưa giải quyết cache.\nNguồn: 23520840_23520838_DeCuongKLTN.docx, Tổng quan đề tài và tài liệu [4], [5]. README.md, mục Cấu trúc repo và Các thư mục tham khảo.');
}
{
const s=p.slides.getItem(2);title(s,'2. Mục tiêu đề tài');
heading(s,'Mục tiêu 1  Thiết kế và hiện thực hệ vi xử lý 4 lõi',292);
body(s,'Lõi RV32IMA, cache L1 riêng và L2 dùng chung, cơ chế nhất quán dữ liệu MESI, MMU/TLB cho từng lõi, giao tiếp bus và DMA.',365,100,1720,130,40);
heading(s,'Mục tiêu 2  Kiểm chứng, đánh giá và triển khai trên FPGA',538);
body(s,'Kiểm tra đúng chức năng bằng mô phỏng RTL và demo tự động trên FPGA. Đánh giá hiệu năng, tài nguyên, timing và công suất ước tính.',612,100,1720,130,40);
heading(s,'Phạm vi thực hiện',795);
body(s,'4 lõi, tập lệnh RV32I/M/A. Không mở rộng F/D hoặc C. MMU giới hạn trang 4 KB. UVM cho cache/coherence là phần khuyến khích.',860,100,1720,110,35);
note(s,'RV32I là tập lệnh số nguyên cơ sở, M bổ sung nhân/chia, A bổ sung thao tác nguyên tử phục vụ chia sẻ dữ liệu giữa các lõi. Hai mục tiêu bao quát phần thiết kế và phần chứng minh thiết kế hoạt động. RTL hiện có chủ yếu là Verilog .v, đề cương định hướng Verilog/SystemVerilog và môi trường kiểm chứng. MMU hiện thực theo cấu trúc Sv32 2 cấp nhưng dùng định dạng PTE/PA tùy biến 32 bit, không tuyên bố tuân thủ đầy đủ Sv32. Không có superpage, không tự cập nhật A/D, không áp dụng đầy đủ phân quyền truy cập trang S/U. Các CSR và chuyển chế độ M/S/U mới có RTL và chưa mô phỏng; không cam kết chạy hệ điều hành. Công suất là ước tính từ công cụ, cần dữ liệu hoạt động thích hợp để đánh giá.\nNguồn: 23520840_23520838_DeCuongKLTN.docx, Mục tiêu và Giới hạn. Risc_V_new/Risc_V/rtl/RV32IMA.v, memory_stage.v, mmu_ptw.v, csr_trap_unit.v.');
}
{
const s=p.slides.getItem(3);title(s,'3. Nội dung và phương pháp thực hiện');
table(s,[
['Nội dung chính','Phương pháp thực hiện','Kết quả dự kiến'],
['1. Khảo sát và lựa chọn kiến trúc','Nghiên cứu ISA, đa lõi và tổ chức bộ nhớ. Đối chiếu các thiết kế tham khảo.','Đặc tả và kiến trúc tổng thể'],
['2. Xây dựng lõi đơn','Hiện thực lõi RV32IMA, cache L1 và MMU. Kiểm tra theo từng khối.','Lõi đơn hoạt động đúng chức năng'],
['3. Tích hợp hệ 4 lõi','Ghép 4 lõi, cache L2, MESI và bus AHB-Lite/AXI4. Tích hợp DMA.','Các lõi chia sẻ dữ liệu nhất quán'],
['4. Đánh giá và hoàn thiện','Mô phỏng hệ thống, tổng hợp Vivado, demo FPGA và phân tích số liệu.','Demo, báo cáo và kết quả đánh giá']
],85,300,1750,625,[520,760,470],34);
note(s,'Thiết kế tăng dần độ phức tạp để cô lập lỗi: kiểm tra khối riêng, ghép lõi đơn, tích hợp nhiều lõi, cuối cùng chạy toàn hệ thống. Vai trò các thành phần: L1 giảm truy cập bộ nhớ cho từng lõi, L2 là bộ nhớ đệm dùng chung, MESI quản lý bản sao dữ liệu giữa các cache, MMU dịch địa chỉ. AHB-Lite ở biên L1 và khối coherence, AXI4 nối phía hệ thống. RTL hiện tại có các liên kết AHB-Lite điểm nối điểm và bus snoop riêng, trọng tài nằm trong coherence_manager; không trình bày là một crossbar AHB nhiều master hoàn chỉnh. DMA hiện chọn IP axi_cdma trong Tcl, công việc nhóm là cấu hình, tích hợp và kiểm chứng.\nNguồn: đề cương, Nội dung 1–4. Risc_V_new/README.md, quyết định kiến trúc. rtl/core_l1_wrapper.v, quad_core_soc_ahb.v, coherence_manager.v và scripts/build_soc_4core_trial.tcl.');
}
{
const s=p.slides.getItem(4);title(s,'3. Kiểm chứng và demo dự kiến');
heading(s,'Kiểm chứng theo từng mức',302,100,810);
body(s,'1. Khối riêng và lõi đơn\nTestbench tự kiểm tra. Đối chiếu thực thi I/M/A với Spike.',386,100,820,150,37);
body(s,'2. Hệ nhiều lõi\nKiểm tra dữ liệu chia sẻ theo kịch bản producer/consumer và coherence.',577,100,820,160,37);
body(s,'3. FPGA\nChạy kịch bản tự động, ghi log PASS/FAIL và thu số liệu đánh giá.',780,100,820,145,37);
heading(s,'Luồng demo hệ thống',302,1030,790);
body(s,'1. Nạp chương trình từ thẻ SD\nvào bộ nhớ chính.',386,1030,780,140,38);
body(s,'2. Hệ 4 lõi thực thi chương trình\nvà xử lý dữ liệu trong RAM.',560,1030,780,140,38);
body(s,'3. Ghi kết quả về thẻ SD\nvà đối chiếu với kết quả tham chiếu.',734,1030,780,140,38);
text(s,'FPGA đích theo đề cương: VCU129. Đường SD–DRAM và giao tiếp trên kit cần hoàn thiện.',100,951,1690,57,28,false,C.gray);
note(s,'Hai mức bắt buộc là mô phỏng RTL và phần cứng FPGA. UVM là phần khuyến khích, thực hiện khi phần chức năng bắt buộc đã ổn định. Spike chỉ dùng đối chiếu trong phạm vi thực thi I/M/A, không coi đây là kiểm chứng toàn bộ hệ thống cache/MMU hoặc tuân thủ mọi đặc tả RISC-V. Luồng demo là kết quả dự kiến, chưa hoàn tất trong repo. Trên Genesys ZU-5EV, README đã đề xuất PS hỗ trợ đọc SD và nạp chương trình trước khi nhả reset cho RISC-V; script hiện vẫn dùng BRAM thử nghiệm, phần loader PS và đường DDR thật chưa có. Với VCU129 cần chốt kết nối SD hoặc module ngoài và bộ điều khiển DDR tương ứng. Không xem một lần validate Block Design là bằng chứng demo phần cứng đã chạy.\nNguồn: 23520840_23520838_DeCuongKLTN.docx, Nội dung 4 và Demo dự kiến. Risc_V_new/README.md, mục -0.05 và Bảng khoảng cách. scripts/build_soc_zu5ev_boot.tcl, host_eval_uart.py, rtl/boot_ctrl.v.');
}
{
const s=p.slides.getItem(5);title(s,'3. Tiến độ hiện tại');
table(s,[
['Hạng mục','Trạng thái hiện tại'],
['Nền tảng kế thừa 2 lõi','README ghi nhận đã có bản chạy trên FPGA.'],
['Hệ 4 lõi, cache L1/L2, MESI và MMU','Đã có RTL tích hợp, cần kiểm chứng hành vi.'],
['CSR/trap và giao tiếp AHB-Lite/AXI4','Đã có mã nguồn và testbench cho các phần mới.'],
['Môi trường kiểm thử','Có testbench MMU, CSR và coherence. Nhánh mới chưa có kết quả mô phỏng xác nhận.'],
['Demo với SD và bộ nhớ chính','Có khung điều khiển boot và script đánh giá. Cần hoàn thiện DDR, loader và giao tiếp SD.']
],85,295,1750,610,[680,1070],34);
text(s,'Mốc tiếp theo: xác nhận testbench, tích hợp toàn hệ thống và chạy demo FPGA.',100,947,1700,60,35,true,C.green);
note(s,'Tiến độ phản ánh mã nguồn trên đĩa và tracker Risc_V_new/README.md, không suy ra đã chạy đúng chỉ vì có module hay testbench. Nền tảng 2 lõi từng chạy FPGA là kết quả kế thừa được README ghi nhận; mã nguồn core dùng chung đã thay đổi sau đó, nên cần chạy regression nếu build lại. Hệ mới instantiate 4 core_l1_wrapper, mỗi lõi có MMU và I/D cache riêng. L1 hiện 32 KB I-cache và 32 KB D-cache mỗi lõi, L2 dùng chung 512 KB theo các tham số RTL. Coherence chưa có kết quả mô phỏng xác nhận. Testbench hiện ưu tiên một số chuyển trạng thái dữ liệu và chưa bao phủ hết eviction/writeback, traffic I-cache, atomic và toàn bộ pipeline. Kịch bản boot/DMA/DDR/SD còn cần tích hợp thực tế.\nNguồn: Risc_V_new/README.md, mục 0, mục 4, mục 5 và mục 9. rtl/quad_core_soc_ahb.v, l1_icache.v, l1_dcache.v, l2_cache.v. sim/tb_coherence.v, tb_coherence_ahb.v, tb_csr_trap.v, tb_csr_priv.v, tb_mmu_core.v.');
}
{
const s=p.slides.getItem(6);title(s,'4. Kế hoạch thực hiện');
text(s,'Thời gian theo đề cương: 07/09/2026 đến 27/12/2026',95,278,1730,55,36,true,C.green);
const tb=table(s,[
['Công việc','Tháng 9','Tháng 10','Tháng 11','Tháng 12'],
['Khảo sát và chốt kiến trúc','x','','',''],
['Lõi đơn, cache L1 và MMU','x','x','',''],
['Hệ 4 lõi, bus, L2, MESI và DMA','','x','x',''],
['Kiểm chứng, demo FPGA và báo cáo','','','x','x']
],85,365,1750,450,[830,230,230,230,230],34);
for(let r=0;r<5;r++)for(let c=1;c<5;c++){
 const cell=tb.getCell(r,c);cell.text.style={alignment:'center'};
 if(r>0 && cell.value==='x'){cell.fill='#D0E8DB';cell.text.style={bold:true,color:C.green};}
}
text(s,'Phân công',100,858,1650,50,36,true,C.green);
text(s,'Võ Lê Phước Lâm: lõi RV32IMA, L1, MMU/TLB, SD/SPI.',100,917,1720,44,32);
text(s,'Vũ Thành Lam: bus AHB/AXI4, L2, MESI và DMA. Cả hai: kiểm thử, demo, báo cáo.',100,969,1720,44,32);
note(s,'Bảng giữ mốc và giai đoạn theo đề cương chính thức. Các tháng thể hiện giai đoạn tập trung công việc, không phải xác nhận các hạng mục đã hoàn thành. Phân công theo tên đầy đủ để tránh nhầm Lam và Lâm. Kế hoạch nội bộ KeHoach_20Tuan_NoiBo.txt ghi phạm vi 07/09/2026–25/01/2027, khác hạn 27/12/2026 trong đề cương. Nhóm cần thống nhất mốc với GVHD trước khi cam kết chính thức. Ưu tiên xác nhận các testbench hiện có và dành thời gian cho tích hợp toàn hệ thống, SD–DDR, chạy FPGA. Không hứa mức tăng tốc 4 lần khi chưa đo.\nNguồn: 23520840_23520838_DeCuongKLTN.docx, Kế hoạch thực hiện và phân công. KeHoach_20Tuan_NoiBo.txt để đối chiếu mốc nội bộ.');
}
await fs.mkdir(workspaceDir+'/output',{recursive:true});
const candidatePath=build+'/candidate.pptx';
await (await PresentationFile.exportPptx(p)).save(candidatePath);
for(let i=0;i<7;i++){
 const png=await p.export({slide:p.slides.getItem(i),format:'png',scale:2/3});
 await fs.writeFile(`${build}/slide-${i+1}.png`,new Uint8Array(await png.arrayBuffer()));
 const layout=await p.slides.getItem(i).export({format:'layout'});await fs.writeFile(`${build}/slide-${i+1}.layout.json`,await layout.text());
}
console.log('Draft and 7 previews exported');
const result=await finalizePresentation({workspaceDir,candidatePath,finalPath:workspaceDir+'/output/BaoVeDeCuong_QuadCore_RV32IMA.pptx',pythonExecutable:python,integrityValidatorPath:SKILL_DIR+'/container_tools/inspect_presentation_package_integrity.py',layoutValidatorPath:SKILL_DIR+'/container_tools/inspect_presentation_layout_geometry.py',layoutArgs:['--expected-slide-size-emu','18288000,10287000','--validate-heading-fit','--require-native-table-slide','4','--require-native-table-slide','6','--require-native-table-slide','7'],explicitTotalSlideCount:7,requiredNativeTableOwnerSlides:[4,6,7],fontPolicy:{basis:'design',families:['Arial','Barlow Semi Condensed']},verifyArtifactToolImport:true,receiptPath:build+'/validation.json'});
console.log(JSON.stringify(result));
