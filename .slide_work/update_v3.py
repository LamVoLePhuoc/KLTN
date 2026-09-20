from pathlib import Path
b=Path(__file__).parent
s=(b/'build_deck_v2.mjs').read_text(encoding='utf8')
a=s.index("const s=p.slides.getItem(4);title")
z=s.index('\n}\n{\nconst s=p.slides.getItem(5)',a)
s=s[:a]+'''const s=p.slides.getItem(4);title(s,'3. Kiểm chứng và demo hệ thống');
function box(label,x,y,w,h,fill=C.pale,size=37,bold=false){
 const sh=s.shapes.add({geometry:'rect',name:label||'Khung sơ đồ',position:{left:x,top:y,width:w,height:h},fill,line:{fill:'#244E50',width:1.2}});
 if(label){sh.text=label;sh.text.style={typeface:font,fontSize:size,bold,color:C.ink,alignment:'center',verticalAlignment:'middle',autoFit:'none',insets:{left:16,right:16,top:12,bottom:12}};}
 return sh;
}
function arrow(a,b,fromSide='bottom',toSide='top',head=true){return s.shapes.connect(a,b,{kind:'straight',fromSide,toSide,line:{fill:'#244E50',width:1.7},head:{type:head?'triangle':'none',width:'sm',length:'sm'}});}
function anchor(x,y){return s.shapes.add({geometry:'rect',name:'Điểm nối nhánh kiểm tra lại',position:{left:x,top:y,width:0.1,height:0.1},fill:'none',line:{fill:'none',width:0}});}
box('',85,290,790,635,'none');box('',1015,290,790,635,'none');
text(s,'Quy trình kiểm chứng',110,314,740,60,42,true,C.ink,'center');
text(s,'Demo dự kiến trên VCU129',1040,314,740,60,42,true,C.ink,'center');
const module=box('Khối riêng',250,405,460,120);
const core=box('Lõi đơn',250,595,460,120);
const system=box('Hệ 4 lõi',250,785,460,120);
arrow(module,core);arrow(core,system);
text(s,'PASS',510,545,130,42,29,false,C.green);text(s,'PASS',510,735,130,42,29,false,C.green);
const l1=anchor(155,655),l2=anchor(155,465);
arrow(core,l1,'left','right',false);arrow(l1,l2,'top','bottom',false);arrow(l2,module,'right','left');
text(s,'FAIL',105,548,125,42,29,false,C.gray);
const r1=anchor(810,845),r2=anchor(810,465);
arrow(system,r1,'right','left',false);arrow(r1,r2,'top','bottom',false);arrow(r2,module,'left','right');
text(s,'FAIL',735,646,120,42,29,false,C.gray);
const load=box('SD/SPI → DMA → DRAM',1180,405,460,120,C.pale,35);
const run=box('CPU 4 lõi thực thi',1180,595,460,120);
const output=box('Ghi kết quả về SD',1180,785,460,120);
arrow(load,run);arrow(run,output);
text(s,'Testbench tự kiểm tra • UVM cho cache/coherence • Spike đối chiếu thực thi I/M/A',85,955,1740,55,29,false,C.gray);
note(s,'Quy trình bên trái: kiểm chứng khối riêng gồm pipeline, MMU/TLB, cache và bus; sau đó tích hợp lõi đơn, cuối cùng hệ 4 lõi. Chỉ chuyển sang mức tiếp theo khi các kiểm tra bắt buộc PASS; FAIL quay lại khối liên quan để sửa và chạy lại. Hai vòng phản hồi trên sơ đồ minh họa quy trình debug, không ngụ ý lỗi nào cũng nằm ở cùng một module. UVM dùng cho cache/coherence trọng yếu, bổ sung testbench RTL; Spike chỉ đối chiếu kết quả thanh ghi/bộ nhớ I/M/A, không đối chiếu toàn bộ CSR/trap, MMU hay hệ đa lõi. Demo bên phải là luồng dự kiến theo DOCX: đọc chương trình từ SD qua SPI, DMA nạp vào DRAM, CPU thực thi từ DRAM và ghi kết quả về SD; có kiểm tra tự động PASS/FAIL và đo thời gian thực thi. FPGA đích VCU129 theo đề cương. Đường SD/SPI, DMA, DRAM và bring-up FPGA chưa hoàn tất trong repo; cần chốt phần cứng SD ngoài và tích hợp bộ điều khiển DDR. Không sử dụng nội dung CNN–LSTM hoặc KV260 từ ảnh tham khảo vì thuộc đề tài khác. Nguồn: 23520840_23520838_DeCuongKLTN.docx, Nội dung 2–4 và Demo dự kiến; Risc_V_new/README.md.');
''' +s[z:]
s=s.replace('candidate_v2','candidate_v3').replace('RV32IMA_v2.pptx','RV32IMA_v3.pptx').replace('/v2-${i+1}', '/v3-${i+1}').replace('validation_v2','validation_v3')
(b/'build_deck_v3.mjs').write_text(s,encoding='utf8')
