"""古畫底圖：克里夫蘭美術館開放典藏（CC0）的中國山水手卷，裁成區塊背景。

每個區塊從某一卷取一段（x0 起、y0～y1 這段高度縮成 600），裁好的圖放在 paintings/<區塊>.jpg，
跟程式一起進版控，平常畫圖不用連網。要換段落或重新裁：

  python tools/inkpaint/paintings.py fetch            # 從美術館 CDN 抓原始 TIFF（每卷 55～320 MB），重裁全部
  python tools/inkpaint/paintings.py fetch chunk.sect_gate

出處寫在 art/CREDITS.md。CC0 不強制署名，但我們照樣列出。
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CROPS = HERE / "paintings"
WORK_H = 1400  # 原圖比這高就先縮到這個高度再裁；座標以縮完的圖為準（1970.3 原圖只有 1341 高，不放大）

SCROLLS = {
    "1970.3": "顧天植《仿黃公望山水》1649，紙本手卷",
    "1975.75": "錢杜《夢遊天台圖》1814，紙本手卷",
    "1997.95": "陳汝言、倪瓚（傳）《仙山圖》元，絹本青綠手卷",
    "1954.581": "文伯仁《潯陽送客圖》明，手卷",
}

# 區塊 -> (典藏號, x0, y0, y1)，座標在高 WORK_H 的縮圖上
SOURCES = {
    "chunk.qingyun_road": ("1970.3", 4000, 60, 1290),
    "chunk.qingyun_woods": ("1975.75", 3700, 40, 1370),
    "chunk.forest_clearing_a": ("1970.3", 15300, 60, 1290),
    "chunk.mountain_village": ("1970.3", 8800, 60, 1290),
    "chunk.ruined_shrine": ("1970.3", 18800, 60, 1290),
    "chunk.sect_gate": ("1997.95", 400, 40, 1370),
    "chunk.sect_plaza": ("1997.95", 1450, 40, 1370),
    "chunk.sect_hall": ("1997.95", 2450, 40, 1370),
    "chunk.heifeng_pass": ("1975.75", 3350, 40, 1370),
    "chunk.heifeng_ravine": ("1970.3", 10200, 60, 1290),
    "chunk.illusion_entry": ("1954.581", 10900, 60, 1340),
    "chunk.illusion_qingyun_town": ("1970.3", 6000, 60, 1290),
    "chunk.illusion_arena": ("1954.581", 11600, 60, 1340),
}


def crop(cid, w):
    """裁好的古畫（RGB，w×600），沒有這個區塊就回傳 None。"""
    path = CROPS / f"{cid}.jpg"
    if cid not in SOURCES or not path.exists():
        return None
    img = Image.open(path).convert("RGB")
    return img if img.size == (w, 600) else img.resize((w, 600), Image.LANCZOS)


def grade(img, theme):
    """調色：一般區塊壓低對比、往紙色靠，讓角色看得清楚；黑風嶺偏暗赭；心魔幻境轉成血紅與墨黑雙色。"""
    a = np.asarray(img, np.float32) / 255
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    if theme == "illusion":
        stops = np.array([[0.03, 0.01, 0.02], [0.35, 0.06, 0.08], [0.62, 0.16, 0.16]], np.float32)
        lo, hi = np.percentile(lum, [2, 98])
        t = np.clip((lum - lo) / max(1e-3, hi - lo), 0, 1)[..., None]
        out = np.where(t < 0.5, stops[0] + (stops[1] - stops[0]) * (t / 0.5), stops[1] + (stops[2] - stops[1]) * ((t - 0.5) / 0.5))
    else:
        paper = np.array([0.91, 0.886, 0.81], np.float32)
        out = a * 0.8 + paper * 0.2
        if theme == "mountain":
            out = out * np.array([0.78, 0.74, 0.68], np.float32)
    return Image.fromarray((np.clip(out, 0, 1) * 255).round().astype(np.uint8), "RGB")


def fetch(ids):
    chunks = json.loads((ROOT / "content/chunks.json").read_text(encoding="utf-8"))
    CROPS.mkdir(exist_ok=True)
    Image.MAX_IMAGE_PIXELS = None
    by_scroll = {}
    for cid in ids or SOURCES:
        by_scroll.setdefault(SOURCES[cid][0], []).append(cid)
    for acc, cids in by_scroll.items():
        with tempfile.TemporaryDirectory() as tmp:
            tif = Path(tmp) / "full.tif"
            print("downloading", acc)
            subprocess.run(["curl", "-sSf", "-o", str(tif), f"https://openaccess-cdn.clevelandart.org/{acc}/{acc}_full.tif"], check=True)
            src = Image.open(tif).convert("RGB")
            if src.height > WORK_H:
                src = src.resize((round(src.width * WORK_H / src.height), WORK_H), Image.LANCZOS)
        cut(src, cids, chunks)


def cut(src, cids, chunks):
    for cid in cids:
        _, x0, y0, y1 = SOURCES[cid]
        w = chunks[cid]["width"]
        sw = round(w * (y1 - y0) / 600)
        src.crop((x0, y0, x0 + sw, y1)).resize((w, 600), Image.LANCZOS).save(CROPS / f"{cid}.jpg", quality=88)
        print("cropped", cid)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] != "fetch":
        raise SystemExit(__doc__)
    fetch(sys.argv[2:])
