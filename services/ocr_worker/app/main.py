from __future__ import annotations

import hmac
import io
import os
import tempfile
import threading
import zipfile
from pathlib import Path
from typing import Any

import fitz
import numpy as np
from docx import Document
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from openpyxl import load_workbook
from PIL import Image
from starlette.concurrency import run_in_threadpool
import anyio

from app.visual_review import inspect_image

MAX_BYTES = 50 * 1024 * 1024
MAX_PAGES = 200
MAX_PIXELS = 40_000_000
MAX_TEXT_CHARS = 2_000_000
MAX_OFFICE_BYTES = 100 * 1024 * 1024
MAX_OFFICE_ENTRIES = 10_000
MAX_SHEET_CELLS = 1_000_000
ALLOWED_SUFFIXES = {".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".docx", ".xlsx"}

app = FastAPI(title="Donghua OCR Worker", version="1.0.0", docs_url=None, redoc_url=None)
_reader: Any | None = None
_reader_lock = threading.Lock()
_extraction_limiter = anyio.CapacityLimiter(1)


def require_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.getenv("OCR_WORKER_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail="worker authentication is not configured")
    supplied = authorization.removeprefix("Bearer ") if authorization else ""
    if not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=401, detail="invalid worker token")


def ocr_reader() -> Any:
    global _reader
    with _reader_lock:
        if _reader is None:
            import easyocr

            use_gpu = os.getenv("OCR_GPU", "false").lower() in {"1", "true", "yes"}
            worker_root = Path(__file__).resolve().parents[1]
            model_directory = Path(os.getenv("OCR_MODEL_DIR", worker_root / "models")).resolve()
            model_directory.mkdir(parents=True, exist_ok=True)
            _reader = easyocr.Reader(
                ["ch_sim", "en"],
                gpu=use_gpu,
                model_storage_directory=str(model_directory),
                verbose=False,
            )
    return _reader


def ocr_image(image: Image.Image) -> dict[str, Any]:
    if image.width * image.height > MAX_PIXELS:
        raise HTTPException(status_code=413, detail="image pixel limit exceeded")
    rgb = image.convert("RGB")
    lines = ocr_reader().readtext(np.asarray(rgb), detail=1, paragraph=False)
    regions = [{"text": str(text).strip(), "bbox": [min(p[0] for p in box), min(p[1] for p in box),
                                                   max(p[0] for p in box), max(p[1] for p in box)]}
               for box, text, _confidence in lines if str(text).strip()]
    return {"text": "\n".join(region["text"] for region in regions), "visual_review": inspect_image(rgb, regions)}


def extract_pdf(path: Path) -> tuple[str, list[dict[str, Any]], list[str]]:
    pages: list[dict[str, Any]] = []
    warnings: list[str] = []
    with fitz.open(path) as document:
        if document.needs_pass:
            raise HTTPException(status_code=422, detail="encrypted PDF requires an unlocked source")
        if len(document) > MAX_PAGES:
            raise HTTPException(status_code=413, detail="PDF page limit exceeded; split the document explicitly")
        for index, page in enumerate(document):
            native_text = page.get_text("text").strip()
            engine = "pymupdf"
            text = native_text
            if page.rect.width * page.rect.height * 4 > MAX_PIXELS:
                raise HTTPException(status_code=413, detail="PDF render pixel limit exceeded")
            pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
            image = Image.open(io.BytesIO(pixmap.tobytes("png")))
            if len(native_text) < 40:
                result = ocr_image(image)
                text, visual_review = result["text"], result["visual_review"]
                engine = "easyocr"
                if not text:
                    warnings.append(f"第 {index + 1} 页未提取到文本")
            else:
                regions = []
                for block in page.get_text("dict")["blocks"]:
                    for line in block.get("lines", []):
                        for span in line["spans"]:
                            box = fitz.Rect(span["bbox"]) * page.rotation_matrix
                            regions.append({"text": span["text"], "bbox": [box.x0 * 2, box.y0 * 2, box.x1 * 2, box.y1 * 2]})
                visual_review = inspect_image(image, regions)
            pages.append({"page": index + 1, "text": text, "engine": engine, "visual_review": visual_review})
            check_text_size(pages)
    return "\n\n".join(page["text"] for page in pages), pages, warnings


def extract_docx(path: Path) -> tuple[str, list[dict[str, Any]], list[str]]:
    validate_office_archive(path)
    document = Document(path)
    lines = []
    # Keep paragraph/table interleaving: appending all tables at the end changes evidence order.
    for block in document.iter_inner_content():
        if hasattr(block, "rows"):
            for row in block.rows:
                lines.append("\t".join(cell.text.strip() for cell in row.cells))
        elif block.text.strip():
            lines.append(block.text.strip())
    text = "\n".join(lines)
    pages = [{"page": 1, "location_kind": "logical_document", "text": text, "engine": "python-docx"}]
    check_text_size(pages)
    return text, pages, ["DOCX位置为逻辑文档而非排版页码；须查看Word原件核对页码。图片、文本框、页眉页脚不在正文提取范围。"]


def extract_xlsx(path: Path) -> tuple[str, list[dict[str, Any]], list[str]]:
    validate_office_archive(path)
    workbook = load_workbook(path, read_only=True, data_only=False)
    pages: list[dict[str, Any]] = []
    cell_count = 0
    try:
        if len(workbook.worksheets) > MAX_PAGES:
            raise HTTPException(status_code=413, detail="worksheet limit exceeded")
        for index, sheet in enumerate(workbook.worksheets, start=1):
            if (sheet.max_row or 0) * (sheet.max_column or 0) > MAX_SHEET_CELLS:
                raise HTTPException(status_code=413, detail="worksheet cell limit exceeded")
            lines = []
            for row in sheet.iter_rows(values_only=True):
                cell_count += len(row)
                if cell_count > MAX_SHEET_CELLS:
                    raise HTTPException(status_code=413, detail="workbook cell limit exceeded")
                values = [str(value).strip() if value is not None else "" for value in row]
                if any(values):
                    lines.append("\t".join(values))
            pages.append({"page": index, "location_kind": "worksheet", "sheet": sheet.title, "text": "\n".join(lines), "engine": "openpyxl"})
            check_text_size(pages)
        return "\n\n".join(f"工作表：{page['sheet']}\n{page['text']}" for page in pages), pages, ["位置序号表示工作表而非打印页码。公式按表达式保留，未计算结果；图片和图表不在单元格提取范围。"]
    finally:
        workbook.close()


def check_text_size(pages: list[dict[str, Any]]) -> None:
    if sum(len(page["text"]) for page in pages) > MAX_TEXT_CHARS:
        raise HTTPException(status_code=413, detail="extracted text limit exceeded; split the source explicitly")


def validate_office_archive(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) > MAX_OFFICE_ENTRIES or sum(item.file_size for item in entries) > MAX_OFFICE_BYTES:
            raise HTTPException(status_code=413, detail="Office archive expansion limit exceeded")
        if any(item.flag_bits & 1 for item in entries):
            raise HTTPException(status_code=422, detail="encrypted Office archive is not supported")


def extract(path: Path, suffix: str) -> tuple[str, list[dict[str, Any]], list[str], str]:
    if suffix == ".pdf":
        text, pages, warnings = extract_pdf(path)
        return text, pages, warnings, "pymupdf+easyocr"
    if suffix == ".docx":
        text, pages, warnings = extract_docx(path)
        return text, pages, warnings, "python-docx"
    if suffix == ".xlsx":
        text, pages, warnings = extract_xlsx(path)
        return text, pages, warnings, "openpyxl"
    with Image.open(path) as image:
        if getattr(image, "n_frames", 1) > MAX_PAGES:
            raise HTTPException(status_code=413, detail="image frame limit exceeded")
        pages = []
        for index in range(getattr(image, "n_frames", 1)):
            image.seek(index)
            result = ocr_image(image)
            pages.append({"page": index + 1, "engine": "easyocr", **result})
            check_text_size(pages)
    text = "\n\n".join(page["text"] for page in pages)
    warnings = [] if text else ["图片未提取到文本"]
    return text, pages, warnings, "easyocr"


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/ocr", dependencies=[Depends(require_token)])
async def run_ocr(file: UploadFile = File(...)) -> dict[str, Any]:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise HTTPException(status_code=415, detail="unsupported file type")

    total = 0
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temporary:
            temp_path = Path(temporary.name)
            while chunk := await file.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_BYTES:
                    raise HTTPException(status_code=413, detail="file too large")
                temporary.write(chunk)
        if total == 0:
            raise HTTPException(status_code=422, detail="empty document")
        # CPU-bound parsing must not block /health or every other request in the ASGI event loop.
        async with _extraction_limiter:
            text, pages, warnings, engine = await run_in_threadpool(extract, temp_path, suffix)
        return {"text": text, "pages": pages, "warnings": warnings, "engine": engine}
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=422, detail=f"document extraction failed: {type(error).__name__}") from error
    finally:
        await file.close()
        if temp_path and temp_path.exists():
            temp_path.unlink(missing_ok=True)
