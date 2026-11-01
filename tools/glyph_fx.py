"""字訣特效的「筆順貼圖」：把授權字型的字形畫出來，每個像素記下它在第幾筆、筆畫的哪一段被寫到。
遊戲的 shader 依時間逐筆顯示（寫字），命中後散成墨點（scripts/ink_fx.gd 的 GLYPH）。

輸出 art/fx/<名稱>.png：R = 字形不透明度，G = 寫到的時間（0–1），B = 第幾筆（給散墨分批用）。
字形取自霞鶩文楷 TC Bold（OFL），筆順是照標準筆順手標的中軸折線（下面 STROKES，座標是 256×256 的格子），
不是 AI 生字。新增一個字：在 GLYPHS 加一組筆畫，跑
  python tools/glyph_fx.py LXGWWenKaiTC-Bold.ttf
（完整字型下載方式見 tools/inkpaint/fonts/README.md）
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SIZE = 256
REACH = 11.0   # 筆畫半寬（256 格）

GLYPHS = {
    # 斬：左「車」七筆（橫、豎、橫折、橫、橫、提、豎），右「斤」四筆（撇、撇、橫、豎）
    "zhan": ("斬", [
        [(35, 62), (125, 62)],
        [(50, 78), (52, 158)],
        [(50, 78), (122, 78), (120, 158)],
        [(58, 118), (118, 118)],
        [(58, 155), (118, 155)],
        [(25, 178), (128, 168)],
        [(80, 30), (80, 222)],
        [(204, 32), (150, 62)],
        [(150, 62), (148, 150), (112, 218)],
        [(150, 112), (230, 100)],
        [(192, 108), (193, 225)],
    ]),
    # 以下照字形格子目測標的筆順中軸（2026-11-01，兵器與功法的字訣）
    # 破：石（橫、撇、豎、橫折、橫）＋皮（橫鉤、撇、豎、橫撇、捺）
    "po": ("破", [
        [(30, 72), (108, 70)],
        [(70, 74), (28, 165)],
        [(55, 118), (55, 195)],
        [(55, 118), (100, 115), (98, 190)],
        [(58, 190), (98, 190)],
        [(128, 72), (205, 72), (200, 95)],
        [(130, 72), (124, 140), (100, 218)],
        [(165, 40), (165, 110)],
        [(132, 112), (205, 112), (165, 170)],
        [(140, 150), (222, 215)],
    ]),
    # 刺：朿（橫、豎、橫折、橫、豎、撇、點）＋刂（豎、豎鉤）
    "ci": ("刺", [
        [(40, 72), (140, 68)],
        [(55, 95), (55, 140)],
        [(55, 95), (125, 95), (122, 140)],
        [(58, 138), (120, 138)],
        [(88, 40), (88, 228)],
        [(85, 145), (35, 195)],
        [(95, 145), (140, 185)],
        [(175, 80), (175, 170)],
        [(222, 40), (222, 220), (205, 205)],
    ]),
    # 拳：點、撇、橫、橫、撇、捺＋手（撇、橫、橫、豎鉤）
    "quan": ("拳", [
        [(48, 50), (68, 80)],
        [(140, 52), (118, 85)],
        [(40, 100), (220, 95)],
        [(55, 128), (200, 125)],
        [(125, 40), (115, 110), (50, 175)],
        [(130, 120), (235, 170)],
        [(170, 150), (85, 165)],
        [(60, 180), (200, 178)],
        [(70, 205), (190, 203)],
        [(128, 155), (128, 235), (108, 225)],
    ]),
    # 火：點、撇、撇、捺
    "huo": ("火", [
        [(60, 135), (80, 165)],
        [(205, 120), (170, 170)],
        [(130, 40), (128, 150), (40, 235)],
        [(135, 165), (225, 230)],
    ]),
    # 金：撇、捺、橫、橫、豎、點、撇、橫
    "jin": ("金", [
        [(130, 30), (30, 140)],
        [(130, 40), (230, 140)],
        [(85, 135), (175, 135)],
        [(65, 170), (195, 170)],
        [(130, 140), (130, 225)],
        [(85, 185), (105, 210)],
        [(180, 185), (160, 210)],
        [(35, 225), (225, 225)],
    ]),
    # 血：撇、豎、橫折、豎、豎、橫
    "xue": ("血", [
        [(140, 30), (118, 75)],
        [(52, 95), (52, 215)],
        [(52, 95), (205, 95), (205, 215)],
        [(100, 100), (100, 210)],
        [(155, 100), (155, 210)],
        [(30, 218), (230, 218)],
    ]),
}


def render(font_path, char):
    f = ImageFont.truetype(str(font_path), 220)
    im = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), char, font=f)
    d.text(((SIZE - (bb[2] - bb[0])) / 2 - bb[0], (SIZE - (bb[3] - bb[1])) / 2 - bb[1]), char, font=f, fill=255)
    return np.asarray(im, np.float32) / 255


def seg_dist(px, py, a, b):
    """點到線段的距離與投影參數 t（0–1）。"""
    ax, ay = a
    bx, by = b
    vx, vy = bx - ax, by - ay
    L2 = max(1e-6, vx * vx + vy * vy)
    t = np.clip(((px - ax) * vx + (py - ay) * vy) / L2, 0, 1)
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return np.sqrt(dx * dx + dy * dy), t


def build(font_path, name):
    char, strokes = GLYPHS[name]
    alpha = render(font_path, char)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    best = np.full((SIZE, SIZE), 1e9, np.float32)
    when = np.zeros((SIZE, SIZE), np.float32)
    which = np.zeros((SIZE, SIZE), np.float32)
    # 交叉處：筆畫寬度內任一筆先寫到就算寫到（取最早），免得交點留洞等後面的筆
    early = np.full((SIZE, SIZE), 9.0, np.float32)
    n = len(strokes)
    for i, pts in enumerate(strokes):
        lengths = [np.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
        total = sum(lengths)
        done = 0.0
        for (a, b), L in zip(zip(pts, pts[1:]), lengths):
            d, t = seg_dist(xs, ys, a, b)
            along = (done + t * L) / total
            early = np.where(d < REACH, np.minimum(early, (i + along) / n), early)
            closer = d < best
            best = np.where(closer, d, best)
            when = np.where(closer, (i + along) / n, when)
            which = np.where(closer, (i + 0.5) / n, which)
            done += L
    when = np.where(early < 9.0, early, when)
    rgb = np.stack([alpha, when * (alpha > 0.02), which * (alpha > 0.02)], -1)
    out = ROOT / "art/fx" / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgb * 255).round().astype(np.uint8), "RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    for name in GLYPHS:
        build(sys.argv[1], name)
