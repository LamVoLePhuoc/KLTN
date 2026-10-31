from pathlib import Path
from docx import Document

workspace = Path(r"C:\Users\ADMIN\Documents\GitHub\KLTN")
source = workspace / "23520840_23520838_ThiếtKếBộViXửLý4lõiRISC-VDựaTrênKiếnTrúcTậpLệnhRV32IMA.docx"
out = workspace / ".codex-deck" / "quadcore-inspect" / "thesis_docx.txt"
out.parent.mkdir(parents=True, exist_ok=True)

doc = Document(source)
lines = []
for index, paragraph in enumerate(doc.paragraphs, start=1):
    text = paragraph.text.strip()
    if text:
        lines.append(f"P{index:04d}\t{paragraph.style.name}\t{text}")

for table_index, table in enumerate(doc.tables, start=1):
    lines.append(f"\nTABLE {table_index}")
    for row in table.rows:
        values = [cell.text.replace("\n", " / ").strip() for cell in row.cells]
        lines.append("\t".join(values))

out.write_text("\n".join(lines), encoding="utf-8")
print(out)
