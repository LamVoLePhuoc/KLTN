from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET
import json, re

ROOT=Path(r'C:\Users\ADMIN\Documents\GitHub\KLTN')
OUT=ROOT/'.slide_work'
OUT.mkdir(exist_ok=True)
ns={'a':'http://schemas.openxmlformats.org/drawingml/2006/main','p':'http://schemas.openxmlformats.org/presentationml/2006/main','w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
doc=ROOT/'23520840_23520838_DeCuongKLTN.docx'
with ZipFile(doc) as z:
    tree=ET.fromstring(z.read('word/document.xml'))
    text=[''.join(p.itertext()) for p in []]
    text=[''.join(t.text or '' for t in p.findall('.//w:t',ns)) for p in tree.findall('.//w:p',ns)]
    (OUT/'proposal.txt').write_text('\n'.join(text),encoding='utf-8')
decks=[]
for name in ['BaoCao_BaoVeDeCuong.pptx','DeCuongKTLN_report.pptx','22520469_22520980_Chaining.pptx']:
    path=Path(r'C:\Users\ADMIN\Downloads')/name
    with ZipFile(path) as z:
        pres=ET.fromstring(z.read('ppt/presentation.xml'))
        info={'name':name,'size':pres.find('p:sldSz',ns).attrib,'slides':[]}
        files=sorted([n for n in z.namelist() if re.fullmatch(r'ppt/slides/slide\d+\.xml',n)],key=lambda n:int(re.search(r'slide(\d+)',n).group(1)))
        for f in files:
            t=ET.fromstring(z.read(f))
            texts=[''.join(e.text or '' for e in p.findall('.//a:t',ns)) for p in t.findall('.//a:p',ns)]
            fonts=[e.attrib for e in t.findall('.//a:rPr',ns)]
            info['slides'].append({'file':f,'text':texts,'runs':fonts})
        decks.append(info)
(OUT/'references.json').write_text(json.dumps(decks,ensure_ascii=False,indent=2),encoding='utf-8')
print((OUT/'proposal.txt').read_text(encoding='utf-8'))
for d in decks:
    print('\nREFERENCE',d['name'],d['size'],len(d['slides']))
    for i,s in enumerate(d['slides']): print(i+1,' / '.join(s['text']))
