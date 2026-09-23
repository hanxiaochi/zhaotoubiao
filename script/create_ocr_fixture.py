"""Generate explicitly synthetic OCR browser fixtures under project tmp only."""
from pathlib import Path
import fitz
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
destination = root / "tmp" / "ocr_acceptance"
destination.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 48)
image = Image.new("RGB", (1400, 620), "white")
draw = ImageDraw.Draw(image)
for index, text in enumerate(["合成债权申报书", "债权人：合成测试企业", "申报金额：12345 元", "仅供软件验收，不是实际法律文书"]):
    draw.text((50, 40 + index * 125), text, font=font, fill="black")
png = destination / "synthetic-claim.png"
image.save(png)
pdf = destination / "synthetic-claim-scan.pdf"
with fitz.open() as document:
    page = document.new_page(width=700, height=310)
    page.insert_image(page.rect, filename=str(png))
    document.save(pdf)
print(f"SYNTHETIC_PNG={png}")
print(f"SYNTHETIC_PDF={pdf}")

# Artificial scribble and red shape only, not a real person's signature or seal.
marks = Image.new("RGB", (1000, 600), "white")
mark_draw = ImageDraw.Draw(marks)
mark_font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 36)
mark_draw.text((40, 40), "合成图像测试，不是实际签名或印章", font=mark_font, fill="black")
mark_draw.text((165, 198), "签字：", font=mark_font, fill="black")
mark_draw.line([(310, 205), (325, 245), (345, 208), (360, 248), (380, 207), (399, 238), (420, 213)], fill="black", width=5)
mark_draw.ellipse((670, 300, 830, 460), outline="red", width=8)
mark_draw.line((700, 355, 795, 405), fill="red", width=5)
marks_path = destination / "synthetic-signature-regions.png"
marks.save(marks_path)
print(f"SYNTHETIC_MARKS={marks_path}")
