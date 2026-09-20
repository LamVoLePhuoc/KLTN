from zipfile import ZipFile, ZIP_DEFLATED
import xml.etree.ElementTree as E
from pathlib import Path
import re
ns={'p':'http://schemas.openxmlformats.org/presentationml/2006/main','a':'http://schemas.openxmlformats.org/drawingml/2006/main'}
source=Path(r'C:\Users\ADMIN\Downloads\BaoCao_BaoVeDeCuong.pptx')
dest=Path(__file__).parent/'template_clean.pptx'
with ZipFile(source) as zi, ZipFile(dest,'w',ZIP_DEFLATED) as zo:
 for item in zi.infolist():
  data=zi.read(item.filename)
  m=re.fullmatch(r'ppt/slides/slide(\d+)\.xml',item.filename)
  if m:
   i=int(m.group(1)); root=E.fromstring(data); tree=root.find('p:cSld/p:spTree',ns)
   allowed={88,89,92,94,95,96,97} if i==1 else {220,221,222,225,226,227,228}
   for child in list(tree):
    if child.tag.split('}')[-1] in ['nvGrpSpPr','grpSpPr']: continue
    nv=child.find('.//p:cNvPr',ns)
    if nv is None or int(nv.get('id')) not in allowed: tree.remove(child)
   data=E.tostring(root,encoding='utf-8',xml_declaration=True)
  zo.writestr(item,data)
print(dest)
