import io
import os
import unittest

import fitz
from PIL import Image, ImageDraw, ImageFont

from app.visual_review import inspect_image
from tests import test_worker


def synthetic_image(ink=False, seal=False, line=False):
    image = Image.new("RGB", (1000, 600), "white")
    draw = ImageDraw.Draw(image)
    if seal:
        draw.ellipse((670, 300, 830, 460), outline="red", width=8)
        draw.line((700, 355, 795, 405), fill="red", width=5)
    if ink:
        draw.line([(310, 205), (325, 245), (345, 208), (360, 248), (380, 207), (399, 238), (420, 213)], fill="black", width=5)
    if line:
        draw.line((280, 250, 540, 250), fill="black", width=2)
    return image


LABEL = {"text": "签字：", "bbox": [180, 205, 275, 245]}


class VisualReviewTest(unittest.TestCase):
    def test_blank_and_label_only_are_not_signatures(self):
        self.assertEqual(inspect_image(synthetic_image(), [])['candidates'], [])
        image = synthetic_image()
        ImageDraw.Draw(image).rectangle((180, 205, 270, 245), fill="black")
        result = inspect_image(image, [LABEL])
        self.assertEqual(result["signature_labels_examined"], 1)
        self.assertEqual(result["candidates"], [])

    def test_straight_blank_signature_line_is_removed(self):
        self.assertEqual(inspect_image(synthetic_image(line=True), [LABEL])["candidates"], [])

    def test_actual_ink_near_label_has_normalized_position_but_no_authenticity(self):
        result = inspect_image(synthetic_image(ink=True, line=True), [LABEL])
        candidate = result["candidates"][0]
        self.assertEqual(candidate["kind"], "signature_ink_candidate")
        self.assertTrue(0.30 <= candidate["bbox"][0] <= 0.32)
        self.assertIn("可能为印刷字或手写", candidate["basis"])
        self.assertIn("不鉴定真伪", result["limitation"])
        self.assertNotIn("confidence", candidate)

    def test_ink_without_signature_label_is_not_called_signature(self):
        self.assertEqual(inspect_image(synthetic_image(ink=True), [])["candidates"], [])

    def test_red_region_is_located_without_ocr_seal_keyword(self):
        candidates = inspect_image(synthetic_image(seal=True), [])["candidates"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["kind"], "red_seal_candidate")
        self.assertAlmostEqual(candidates[0]["bbox"][0], 0.67, places=2)
        self.assertAlmostEqual(candidates[0]["bbox"][1], 0.5, places=2)

    def test_scaled_and_out_of_page_labels_are_safe(self):
        image = synthetic_image(ink=True, seal=True).resize((2000, 1200))
        label = {"text": LABEL["text"], "bbox": [n * 2 for n in LABEL["bbox"]]}
        result = inspect_image(image, [label, {"text": "签名", "bbox": [2100, 1300, 2200, 1400]}])
        self.assertEqual({c["kind"] for c in result["candidates"]}, {"signature_ink_candidate", "red_seal_candidate"})
        self.assertTrue(all(0 <= n <= 1 for c in result["candidates"] for n in c["bbox"]))


class VisualWorkerTest(unittest.TestCase):
    setUp = test_worker.WorkerAcceptanceTest.setUp
    tearDown = test_worker.WorkerAcceptanceTest.tearDown
    upload = test_worker.WorkerAcceptanceTest.upload

    def test_native_pdf_visual_region_even_when_text_is_long(self):
        with fitz.open() as document:
            page = document.new_page(width=500, height=300)
            page.insert_text((30, 40), "Synthetic image test only. This text exceeds forty characters.")
            page.draw_circle((375, 190), 40, color=(1, 0, 0), width=3)
            raw = document.tobytes()
        response = self.upload("synthetic-native.pdf", raw)
        self.assertEqual(response.status_code, 200, response.text)
        result = response.json()["pages"][0]
        self.assertEqual(result["engine"], "pymupdf")
        self.assertEqual(result["visual_review"]["candidates"][0]["kind"], "red_seal_candidate")

    @unittest.skipUnless(os.getenv("RUN_LIVE_OCR") == "1", "Enable real local OCR explicitly")
    def test_live_signature_label_and_visual_ink_on_image_and_scan(self):
        image = synthetic_image(ink=True, seal=True)
        font = ImageFont.truetype(os.getenv("OCR_TEST_FONT", "C:/Windows/Fonts/msyh.ttc"), 36)
        ImageDraw.Draw(image).text((165, 198), "签字：", font=font, fill="black")
        output = io.BytesIO()
        image.save(output, format="PNG")
        with fitz.open() as document:
            page = document.new_page(width=500, height=300)
            page.insert_image(page.rect, stream=output.getvalue())
            pdf = document.tobytes()
        for filename, raw in [("synthetic-marks.png", output.getvalue()), ("synthetic-marks.pdf", pdf)]:
            response = self.upload(filename, raw)
            self.assertEqual(response.status_code, 200, response.text)
            page = response.json()["pages"][0]
            self.assertIn("签字", page["text"])
            kinds = {c["kind"] for c in page["visual_review"]["candidates"]}
            self.assertEqual(kinds, {"signature_ink_candidate", "red_seal_candidate"}, page)


if __name__ == "__main__":
    unittest.main(verbosity=2)
