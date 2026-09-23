import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import fitz
from docx import Document
from fastapi.testclient import TestClient
from openpyxl import Workbook
from PIL import Image, ImageDraw, ImageFont

from app import main


class WorkerAcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {"OCR_WORKER_TOKEN": "synthetic-worker-test-token"})
        self.environment.start()
        self.client_context = TestClient(main.app)
        self.client = self.client_context.__enter__()
        self.headers = {"Authorization": "Bearer synthetic-worker-test-token"}

    def tearDown(self):
        self.client_context.__exit__(None, None, None)
        self.environment.stop()

    def upload(self, filename, content, headers=None):
        return self.client.post("/v1/ocr", headers=self.headers if headers is None else headers,
                                files={"file": (filename, content, "application/octet-stream")})

    def docx_bytes(self):
        output = io.BytesIO()
        document = Document()
        document.add_paragraph("合成债权申报 第一段")
        table = document.add_table(rows=1, cols=2)
        table.cell(0, 0).text = "中间合同表"
        table.cell(0, 1).text = "12345"
        document.add_paragraph("表后结论 仅作功能验收")
        document.save(output)
        return output.getvalue()

    def test_auth_fails_closed_and_health_stays_available(self):
        self.assertEqual(self.client.get("/health").status_code, 200)
        self.assertEqual(self.upload("evidence.docx", self.docx_bytes(), headers={}).status_code, 401)
        self.assertEqual(self.upload("evidence.docx", self.docx_bytes(), headers={"Authorization": "Bearer wrong"}).status_code, 401)
        with patch.dict(os.environ, {"OCR_WORKER_TOKEN": ""}):
            self.assertEqual(self.upload("evidence.docx", self.docx_bytes()).status_code, 503)

    def test_docx_retains_table_order_and_discloses_nonphysical_page_numbers(self):
        response = self.upload("evidence.docx", self.docx_bytes())
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertLess(payload["text"].index("第一段"), payload["text"].index("中间合同表"))
        self.assertLess(payload["text"].index("中间合同表"), payload["text"].index("表后结论"))
        self.assertEqual(payload["pages"][0]["location_kind"], "logical_document")
        self.assertIn("非排版页码", payload["warnings"][0])

    def test_xlsx_retains_sheet_names_and_uncomputed_formula(self):
        output = io.BytesIO()
        workbook = Workbook()
        workbook.active.title = "合成金额"
        workbook.active.append(["本金", 12345, "=SUM(B1:B2)"])
        workbook.create_sheet("附件目录").append(["合成合同"])
        workbook.save(output)
        workbook.close()
        response = self.upload("evidence.xlsx", output.getvalue())
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertEqual([page["sheet"] for page in payload["pages"]], ["合成金额", "附件目录"])
        self.assertIn("=SUM(B1:B2)", payload["text"])
        self.assertIn("未计算结果", payload["warnings"][0])

    def test_native_pdf_has_actual_distinct_pages(self):
        with fitz.open() as document:
            for index in range(2):
                page = document.new_page()
                page.insert_text((40, 80), f"Synthetic evidence page {index + 1}: principal 12345 and supporting contract only for software testing.")
            raw = document.tobytes()
        response = self.upload("evidence.pdf", raw)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual([item["page"] for item in response.json()["pages"]], [1, 2])
        self.assertTrue(all(item["engine"] == "pymupdf" for item in response.json()["pages"]))

    def test_multiframe_tiff_does_not_silently_drop_later_frames(self):
        output = io.BytesIO()
        first = Image.new("RGB", (30, 30), "white")
        second = Image.new("RGB", (30, 30), "black")
        first.save(output, format="TIFF", save_all=True, append_images=[second])
        with patch.object(main, "ocr_image", side_effect=[{"text": "第一页"}, {"text": "第二页"}]):
            response = self.upload("evidence.tiff", output.getvalue())
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(len(response.json()["pages"]), 2)
        self.assertIn("第二页", response.json()["text"])

    def test_invalid_empty_and_disguised_input_never_succeeds(self):
        self.assertEqual(self.upload("evidence.exe", b"not a document").status_code, 415)
        self.assertEqual(self.upload("empty.pdf", b"").status_code, 422)
        response = self.upload("fake.pdf", b"secret-content-that-must-not-be-echoed")
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("secret-content", response.text)

    def test_byte_archive_and_text_limits_fail_without_truncating(self):
        raw = self.docx_bytes()
        with patch.object(main, "MAX_BYTES", 10):
            self.assertEqual(self.upload("evidence.docx", raw).status_code, 413)
        with patch.object(main, "MAX_OFFICE_BYTES", 10):
            self.assertEqual(self.upload("evidence.docx", raw).status_code, 413)
        with patch.object(main, "MAX_TEXT_CHARS", 5):
            self.assertEqual(self.upload("evidence.docx", raw).status_code, 413)

    def test_pdf_page_and_encryption_limits(self):
        with fitz.open() as document:
            document.new_page()
            document.new_page()
            raw = document.tobytes()
            protected = document.tobytes(encryption=fitz.PDF_ENCRYPT_AES_256, owner_pw="synthetic", user_pw="synthetic")
        with patch.object(main, "MAX_PAGES", 1):
            self.assertEqual(self.upload("large.pdf", raw).status_code, 413)
        self.assertEqual(self.upload("encrypted.pdf", protected).status_code, 422)

    def test_image_pixel_limit_is_checked_before_model_loading(self):
        output = io.BytesIO()
        Image.new("RGB", (100, 100), "white").save(output, format="PNG")
        with patch.object(main, "MAX_PIXELS", 99), patch.object(main, "ocr_reader") as reader:
            self.assertEqual(self.upload("large.png", output.getvalue()).status_code, 413)
            reader.assert_not_called()

    def test_temp_files_are_cleaned_on_success_and_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            original = main.tempfile.NamedTemporaryFile
            with patch.object(main.tempfile, "NamedTemporaryFile", side_effect=lambda **kwargs: original(dir=folder, **kwargs)):
                self.assertEqual(self.upload("valid.docx", self.docx_bytes()).status_code, 200)
                self.assertEqual(self.upload("invalid.pdf", b"invalid").status_code, 422)
            self.assertEqual(list(Path(folder).iterdir()), [])

    @unittest.skipUnless(os.getenv("RUN_LIVE_OCR") == "1", "Set RUN_LIVE_OCR=1 for real local model recognition")
    def test_real_chinese_image_and_scanned_pdf(self):
        font_path = os.getenv("OCR_TEST_FONT", "C:/Windows/Fonts/msyh.ttc")
        font = ImageFont.truetype(font_path, 48)
        image = Image.new("RGB", (1200, 420), "white")
        draw = ImageDraw.Draw(image)
        draw.text((50, 60), "合成债权申报书", font=font, fill="black")
        draw.text((50, 150), "申报金额 12345 元", font=font, fill="black")
        output = io.BytesIO()
        image.save(output, format="PNG")
        image_response = self.upload("synthetic.png", output.getvalue())
        self.assertEqual(image_response.status_code, 200, image_response.text)
        self.assertIn("12345", image_response.json()["text"])
        self.assertIn("债权", image_response.json()["text"])
        with fitz.open() as document:
            page = document.new_page(width=600, height=210)
            page.insert_image(page.rect, stream=output.getvalue())
            raw = document.tobytes()
        pdf_response = self.upload("synthetic-scan.pdf", raw)
        self.assertEqual(pdf_response.status_code, 200, pdf_response.text)
        self.assertEqual(pdf_response.json()["pages"][0]["engine"], "easyocr")
        self.assertIn("12345", pdf_response.json()["text"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
