"""Local, explainable image candidates, never signature or seal authentication."""
from __future__ import annotations

import re
from typing import Any

import cv2
import numpy as np
from PIL import Image

SIGNATURE_LABEL = re.compile(r"签[字名章]|signature", re.IGNORECASE)
LIMITATION = "仅检查疑似红色印章区域及签字标签右侧墨迹，可能把标志或印刷文字误报；黑白印章、浅色/重叠/任意位置手写可能漏检。未发现不代表不存在，不鉴定真伪或授权效力，须查看原件人工核验。"


def inspect_image(image: Image.Image, regions: list[dict[str, Any]]) -> dict[str, Any]:
    original_width, original_height = image.size
    rgb_image = image.convert("RGB")
    rgb_image.thumbnail((1600, 1600))
    rgb = np.asarray(rgb_image)
    height, width = rgb.shape[:2]
    scale_x, scale_y = width / original_width, height / original_height
    candidates: list[dict[str, Any]] = []

    def add(kind: str, box: tuple[int, int, int, int], basis: str) -> None:
        x, y, w, h = box
        candidates.append({"kind": kind, "bbox": [round(x / width, 4), round(y / height, 4),
                                                  round((x + w) / width, 4), round((y + h) / height, 4)],
                           "basis": basis})

    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    red = (((hsv[:, :, 0] <= 12) | (hsv[:, :, 0] >= 168)) &
           (hsv[:, :, 1] >= 90) & (hsv[:, :, 2] >= 65)).astype(np.uint8) * 255
    closed = cv2.morphologyEx(red, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    count, _, stats, _ = cv2.connectedComponentsWithStats(closed)
    red_boxes = []
    for x, y, w, h, area in sorted(stats[1:count], key=lambda stat: -(int(stat[2]) * int(stat[3]))):
        if min(w, h) >= max(16, min(width, height) * 0.025) and 0.4 <= w / h <= 2.5 and area >= 60:
            if any(x >= a and y >= b and x + w <= a + c and y + h <= b + d for a, b, c, d in red_boxes):
                continue
            red_boxes.append((x, y, w, h))
            add("red_seal_candidate", (int(x), int(y), int(w), int(h)), "红色连通区域及形状规则，非印章鉴真")

    dark = ((cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY) < 145) & (red == 0)).astype(np.uint8) * 255
    labels_examined = 0
    for region in regions:
        if not SIGNATURE_LABEL.search(region["text"]):
            continue
        x0, y0, x1, y1 = region["bbox"]
        x0, x1 = x0 * scale_x, x1 * scale_x
        y0, y1 = y0 * scale_y, y1 * scale_y
        label_height = max(y1 - y0, 10)
        left, right = max(0, int(x1 + 3)), min(width, int(x1 + max(label_height * 6, width * 0.2)))
        top, bottom = max(0, int(y0 - label_height * 0.4)), min(height, int(y1 + label_height * 0.6))
        labels_examined += 1
        if right <= left or bottom <= top:
            continue
        ink = dark[top:bottom, left:right].copy()
        # Remove long table borders and blank signature rules before inspecting pixels.
        horizontal = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((1, max(12, int(label_height * 2))), np.uint8))
        vertical = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((max(12, int(label_height * 1.5)), 1), np.uint8))
        ink[(horizontal > 0) | (vertical > 0)] = 0
        count, _, stats, _ = cv2.connectedComponentsWithStats(ink)
        pieces = [s for s in stats[1:count] if s[4] >= 8 and s[3] >= label_height * 0.25 and s[2] >= 3]
        if not pieces:
            continue
        x = min(s[0] for s in pieces)
        y = min(s[1] for s in pieces)
        w = max(s[0] + s[2] for s in pieces) - x
        h = max(s[1] + s[3] for s in pieces) - y
        if sum(s[4] for s in pieces) >= max(30, label_height * 2) and w >= label_height * 0.6:
            add("signature_ink_candidate", (int(left + x), int(top + y), int(w), int(h)), "签字标签右侧检测到去表格线后的墨迹，可能为印刷字或手写")

    candidates.sort(key=lambda item: (item["bbox"][1], item["bbox"][0], item["kind"]))
    return {"status": "checked", "method": "local-pixel-heuristics-v1", "signature_labels_examined": labels_examined,
            "candidates": candidates[:20], "omitted_candidates": max(0, len(candidates) - 20), "limitation": LIMITATION}
