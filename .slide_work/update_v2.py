from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import xml.etree.ElementTree as E
b=Path(__file__).parent
P='http://schemas.openxmlformats.org/presentationml/2006/main'
R='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PK='http://schemas.openxmlformats.org/package/2006/relationships'
CT='http://schemas.openxmlformats.org/package/2006/content-types'
with ZipFile(b/'template_clean.pptx') as z:
 d={n:z.read(n) for n in z.namelist()}
d['ppt/slides/slide8.xml']=d['ppt/slides/slide7.xml']
d['ppt/slides/_rels/slide8.xml.rels']=d['ppt/slides/_rels/slide7.xml.rels']
root=E.fromstring(d['ppt/_rels/presentation.xml.rels'])
rid='rIdAlternateWeek'
E.SubElement(root,'{'+PK+'}Relationship',{'Id':rid,'Type':R+'/slide','Target':'slides/slide8.xml'})
d['ppt/_rels/presentation.xml.rels']=E.tostring(root)
root=E.fromstring(d['ppt/presentation.xml'])
E.SubElement(root.find('{'+P+'}sldIdLst'),'{'+P+'}sldId',{'id':'999','{'+R+'}id':rid})
d['ppt/presentation.xml']=E.tostring(root)
root=E.fromstring(d['[Content_Types].xml'])
E.register_namespace('',CT)
E.SubElement(root,'{'+CT+'}Override',{'PartName':'/ppt/slides/slide8.xml','ContentType':'application/vnd.openxmlformats-officedocument.presentationml.slide+xml'})
d['[Content_Types].xml']=E.tostring(root)
with ZipFile(b/'template_v2.pptx','w',ZIP_DEFLATED) as z:
 for n,v in d.items():z.writestr(n,v)
s=(b/'build_deck.mjs').read_text(encoding='utf8').replace('template_clean.pptx','template_v2.pptx').replace('i<7','i<8')
s=s.replace('MMU giới hạn trang 4 KB. UVM cho cache/coherence là phần khuyến khích.','MMU giới hạn trang 4 KB. Kiểm chứng UVM cho cache/coherence; CSR/trap ngoài phạm vi đề cương.')
s=s.replace('UVM là phần khuyến khích, thực hiện khi phần chức năng bắt buộc đã ổn định.','DOCX mới yêu cầu triển khai UVM cho các IP cache/coherence trọng yếu, song song giai đoạn thiết kế 4 lõi; UVM bổ sung cho RTL và FPGA.')
s=s.replace('Ghép 4 lõi, cache L2, MESI và bus AHB-Lite/AXI4. Tích hợp DMA.','Ghép 4 lõi, L2, MESI và bus AHB/AXI4. Tích hợp DMA, giao tiếp SD/SPI.')
s=s.replace('Mô phỏng hệ thống, tổng hợp Vivado, demo FPGA và phân tích số liệu.','RTL và UVM cho cache/coherence; tổng hợp Vivado, demo FPGA và đo hiệu năng.')
s=s.replace('Testbench tự kiểm tra. Đối chiếu thực thi I/M/A với Spike.','Testbench tự kiểm tra; Spike đối chiếu thanh ghi/bộ nhớ I/M/A.')
s=s.replace('Kiểm tra dữ liệu chia sẻ theo kịch bản producer/consumer và coherence.','Producer/consumer và coherence. UVM cho cache L1/L2 và coherence manager.')
s=s.replace('1. Nạp chương trình từ thẻ SD\\nvào bộ nhớ chính.','1. Đọc chương trình từ SD/SPI,\\nnạp vào DRAM qua DMA.')
s=s.replace("['CSR/trap và giao tiếp AHB-Lite/AXI4','Đã có mã nguồn và testbench cho các phần mới.']","['Giao tiếp AHB/AXI4 và CSR/trap','Đã có RTL/testbench; CSR/trap hiện ngoài phạm vi DOCX, chưa xác nhận mô phỏng.']")
start=s.index("const s=p.slides.getItem(6);title")
end=s.index("\n}\nawait fs.mkdir",start)
s=s[:start]+'''const s=p.slides.getItem(6);title(s,'4. Kế hoạch thực hiện theo tháng');
text(s,'Quy đổi từ bảng 20 tuần trong DOCX mới: 09/2026–01/2027',95,278,1730,55,34,true,C.green);
const tb=table(s,[
['Công việc','T9','T10','T11','T12','T1/27'],
['Kiến trúc, lõi đơn, L1 và MMU','x','x','','',''],
['4 lõi, AHB/AXI4, L2, MESI và UVM','','x','x','',''],
['DMA, SD/SPI và tích hợp hệ thống','x','x','x','x',''],
['RTL toàn hệ thống, tổng hợp và FPGA','','','','x','x'],
['Đo hiệu năng, dự phòng và báo cáo','','','','','x']
],85,355,1750,500,[750,200,200,200,200,200],31);
for(let r=0;r<6;r++)for(let c=1;c<6;c++){
 const cell=tb.getCell(r,c);cell.text.style={alignment:'center'};
 if(r>0 && cell.value==='x'){cell.fill='#D0E8DB';cell.text.style={bold:true,color:C.green};}
}
text(s,'Lâm: lõi, L1, MMU/TLB, SD/SPI. Lam: bus, L2, MESI, DMA. Cả hai: kiểm chứng, demo, báo cáo.',100,883,1710,80,30);
text(s,'Cần thống nhất mốc: đầu DOCX ghi 27/12/2026; bảng tuần kết thúc, nộp 25/01/2027.',100,978,1720,44,27,false,C.gray);
note(s,'Bản theo tháng được quy đổi từ chính bảng 20 tuần của DOCX mới để so sánh với slide 8 trên cùng một kế hoạch. Tuần 5 hoàn tất lõi đơn, tuần 10 coherence PASS, tuần 12 đường SD–DMA–DRAM mô phỏng, tuần 14 toàn hệ thống RTL PASS, tuần 18 FPGA PASS, tuần 19 dự phòng và tuần 20 báo cáo. Đây là kế hoạch dự kiến, không phải kết quả đã đạt. DOCX có mâu thuẫn giữa hạn 27/12/2026 ở đầu và bảng tuần nộp 25/01/2027; cần GVHD xác nhận. Các giai đoạn chồng lấn do hai thành viên triển khai song song.');
}
{
const s=p.slides.getItem(7);title(s,'4. Tiêu chí đánh giá và kế hoạch theo tuần');
heading(s,'Tiêu chí đánh giá',290,85,680);
heading(s,'Kế hoạch thực hiện',290,850,970);
const criteria=table(s,[
['Tiêu chí','Cách đánh giá'],
['Chức năng','PASS/FAIL; I/M/A, MMU, dữ liệu chia sẻ'],
['Tài nguyên','LUT, FF, BRAM, DSP'],
['Timing','Fmax, WNS'],
['Hiệu năng','Chu kỳ / thời gian chạy; so sánh 1 và 4 lõi'],
['Công suất','Ước tính từ Vivado']
],85,370,685,565,[265,420],30);
const phases=table(s,[
['Tuần','Công việc và mốc chính'],
['1–5','Chốt kiến trúc; lõi đơn, L1, MMU; DMA v1'],
['6–10','4 lõi, L2, MESI, interconnect; UVM và coherence PASS'],
['11–12','SD/SPI–DMA–DRAM PASS trong mô phỏng'],
['13–15','Tích hợp, RTL toàn hệ thống PASS; tổng hợp Vivado'],
['16–18','Bring-up, debug FPGA; demo tự động và đo hiệu năng'],
['19–20','Dự phòng; báo cáo, slide và video; nộp 25/01/2027']
],850,370,985,565,[165,820],30);
text(s,'Tuần 1 bắt đầu 07/09/2026. Cần thống nhất hạn 27/12/2026 ở đầu DOCX với bảng 20 tuần.',85,978,1750,44,27,false,C.gray);
note(s,'Slide bổ sung theo bố cục ảnh tham khảo: tiêu chí đánh giá bên trái, kế hoạch theo tuần bên phải. Các nhóm tuần được gộp từ bảng tuần chính trong DOCX mới, không dùng nội dung huấn luyện mô hình của ảnh mẫu. Tiêu chí PASS/FAIL là đúng chức năng; không dùng MAE/ME/SD vì đề tài là bộ xử lý. Timing và phép so sánh 1–4 lõi là cách đánh giá đề xuất, chưa có ngưỡng hoặc kết quả cam kết; đo cùng workload, thuật toán, dữ liệu và điều kiện clock, tách thời gian I/O SD khỏi thời gian tính toán. Vivado cung cấp ước tính công suất, không phải đo năng lượng thực tế. Tuần 19 được giữ dự phòng. Khi chốt báo cáo chỉ giữ một trong hai slide 7 và 8.');
''' +s[end:]
s=s.replace('candidate.pptx','candidate_v2.pptx').replace('/slide-${i+1}', '/v2-${i+1}').replace('Draft and 7','Draft and 8').replace('BaoVeDeCuong_QuadCore_RV32IMA.pptx','BaoVeDeCuong_QuadCore_RV32IMA_v2.pptx').replace('explicitTotalSlideCount:7','explicitTotalSlideCount:8').replace('requiredNativeTableOwnerSlides:[4,6,7]','requiredNativeTableOwnerSlides:[4,6,7,8]').replace("'--require-native-table-slide','7']","'--require-native-table-slide','7','--require-native-table-slide','8']").replace('validation.json','validation_v2.json')
(b/'build_deck_v2.mjs').write_text(s,encoding='utf8')
