"""地標場景物件：山門牌坊、殿宇、廟、村屋不再畫在區塊底圖上，而是獨立放進遊戲世界（跟地面一起走），
分前後兩張圖：

  <id>_back.png   角色後面（台基、牆、門窗、屋頂、石階）
  <id>_front.png  角色前面（柱子下段）：人走過門洞時，柱子擋住人，看起來是穿過去的

兩張同尺寸，地面線在圖的最底下、物件中心在圖的水平中心。遊戲照 content/landmarks.json 擺放
（區塊內的 x、圖檔、可以站的屋簷平台）。

用法：python -m tools.inkpaint.landmarks   → art/landmarks/*.png、content/landmarks.json
"""
import json
import math
from pathlib import Path

import numpy as np

from . import scenery as S
from .ink import INK, Canvas, seed_of

ROOT = Path(__file__).resolve().parents[2]
PAD = 60          # 圖左右多留的寬度（飛簷翹出去）


def _canvas(lid, w, h):
    return Canvas(int(w + PAD * 2), int(h), seed_of("landmark." + lid))


def _split(cv, front_rects):
    """front_rects：[(x0, y0, x1, y1)]（畫布座標）。回傳 (back, front) 兩張圖。"""
    img = np.asarray(cv.image()).copy()
    mask = np.zeros(img.shape[:2], bool)
    for x0, y0, x1, y1 in front_rects:
        mask[max(0, int(y0)):int(math.ceil(y1)), max(0, int(x0)):int(math.ceil(x1))] = True
    front = img.copy()
    front[~mask, 3] = 0
    back = img.copy()
    back[mask, 3] = 0
    from PIL import Image
    return Image.fromarray(back, "RGBA"), Image.fromarray(front, "RGBA")


def paifang(lid, text, w=300, h=340):
    """山門牌樓（S.paifang 的同一套幾何）：四根柱子下段在角色前面；前面一道石階在後面。主簷可以站。"""
    cv = _canvas(lid, w, h + 40)
    gy, cx = cv.h, cv.w / 2
    for k in range(10):
        y = gy - k * 14
        cv.paint(cv.rect(cx - 90 + k * 6, y - 14, cx + 90 - k * 6, y, blur=0.5), (170, 168, 160), 0.9)
        cv.stroke([(cx - 90 + k * 6, y - 14), (cx + 90 - k * 6, y - 14)], 1.5, INK, 0.5, smooth=0)
    S.paifang(cv, cx, gy, w, h, text)
    cols = [cx - w * 0.5, cx - w * 0.2, cx + w * 0.2, cx + w * 0.5]
    front = [(x - 15, gy - h * 0.45 + 8, x + 15, gy) for x in cols]
    roof_y = h * 0.78 + 5                    # 主簷簷口上緣：從旁邊 h180 的平台跳得上去
    platforms = [{"dx": round(-w * 0.22), "h": round(roof_y), "w": round(w * 0.44)}]
    return cv, front, platforms


def hall(lid, text, w=520, h=420, wall=(196, 184, 160), pillar=(120, 40, 30), roof_c=(56, 68, 80), stand=True):
    """殿堂：一排簷柱在角色前面（走進殿裡像穿過迴廊），其餘在後面。屋頂中段可以站。"""
    cv = _canvas(lid, w * 1.1, h + 10)
    gy, cx = cv.h, cv.w / 2
    S.hall(cv, cx, gy, w, h, wall=wall, pillar=pillar, roof_c=roof_c, text=text)
    base_h, top = h * 0.1, gy - h * 0.62
    front = []
    pw = max(6.0, w * 0.013)               # 簷柱加粗（S.hall 的柱子只有 8px，穿過時看不出被擋）
    for k in range(7):
        px = cx - w * 0.4 + w * 0.8 * k / 6
        cv.paint(cv.rect(px - pw, top + 4, px + pw, gy - base_h), pillar, 0.95)
        cv.stroke([(px - pw, top + 4), (px - pw, gy - base_h)], 1.6, INK, 0.6, smooth=0)
        cv.stroke([(px + pw, top + 4), (px + pw, gy - base_h)], 1.2, INK, 0.35, smooth=0)
        cv.paint(cv.rect(px - pw - 4, gy - base_h - 10, px + pw + 4, gy - base_h), (140, 132, 120), 0.95)
        front.append((px - pw - 5, top + h * 0.12, px + pw + 5, gy - base_h))
    # 屋面下段（簷口上方一點）：從殿裡 h200 的平台跳得上去
    platforms = [{"dx": round(-w * 0.26), "h": round(h * 0.62 + h * 0.32 * 0.3), "w": round(w * 0.52)}] if stand else []
    return cv, front, platforms


def house(lid, w, h, lantern=False):
    """村屋：整棟在角色後面（人從門前走過）。"""
    cv = _canvas(lid, w * 1.2, h + 10)
    S.house(cv, cv.w / 2, cv.h, w, h, lantern=lantern)
    return cv, [], []


# 區塊 -> [(地標 id, 區塊內 x, 畫法)]；區塊底圖（chunks.py）不再畫這些
LANDMARKS = {
    "chunk.sect_gate": [("sect_gate.paifang", 560, lambda lid: paifang(lid, "青雲"))],
    "chunk.sect_hall": [("sect_hall.hall", 450, lambda lid: hall(lid, "傳功殿"))],
    # 山神廟正好壓在原本 h220 的平台下面：廟脊就是那塊平台，不另加
    "chunk.ruined_shrine": [("ruined_shrine.hall", 500, lambda lid: hall(lid, "山神", 280, 240, wall=(170, 160, 140), pillar=(110, 70, 50),
                                                                       roof_c=(60, 58, 52), stand=False))],
    "chunk.mountain_village": [("mountain_village.house_a", 240, lambda lid: house(lid, 170, 153)),
                               ("mountain_village.house_b", 520, lambda lid: house(lid, 140, 126, lantern=True)),
                               ("mountain_village.house_c", 850, lambda lid: house(lid, 180, 162))],
}


def main():
    out = ROOT / "art/landmarks"
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"_comment": "地標場景物件（tools/inkpaint/landmarks.py 產生）：區塊內 x 是物件中心，platforms 的 dx 是平台左緣相對中心、h 是離地高"}
    for cid, items in LANDMARKS.items():
        manifest[cid] = []
        for lid, x, fn in items:
            cv, front, platforms = fn(lid)
            back_img, front_img = _split(cv, front)
            back_img.save(out / f"{lid}_back.png", optimize=True)
            entry = {"id": lid, "x": x, "back": f"res://art/landmarks/{lid}_back.png", "platforms": platforms}
            if front:
                front_img.save(out / f"{lid}_front.png", optimize=True)
                entry["front"] = f"res://art/landmarks/{lid}_front.png"
            manifest[cid].append(entry)
    (ROOT / "content/landmarks.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("landmarks ->", out)


if __name__ == "__main__":
    main()
