"""地區景深圖層：背景不再只靠一張古畫，而是由遠到近好幾張各自獨立、各自捲動速度的圖疊起來。

  天色（程式漸層）→ 遠峰 ranges_far → 遠山 ranges_mid（far_ranges.py）
  → 丘陵 hills_<地區>：青綠／赭石上色的山丘，山脊上有松、點苔，山腳沒入霧
  → 水面 water（村、林、山路）或雲海 cloudsea（宗門）：一條橫亙的水光／雲帶，「水深」
  → 古畫只留下半段（建築、近景）當一層
  → 近景山石 near_<地區>：一簇簇深色的石塊與松樹，捲得比古畫快，夾在古畫和角色之間
  → 前景草石、垂掛（scenery.gd 程式畫）

每張左右都能無縫重複（週期函數＋物件左右包圈），顏色直接畫進圖裡（越遠越淡越藍、越近越深越濃）。
用法：python -m tools.inkpaint.layers   → art/bg/hills_*.png、near_*.png、water.png、cloudsea.png
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .far_ranges import noise2d, periodic

ROOT = Path(__file__).resolve().parents[2]
W = 2048

# 地區 -> 丘陵山頂色、丘陵山腳（霧）色、近景石色、近景亮面色、松色
PALETTES = {
    "forest": dict(hill=(78, 132, 112), hill_low=(178, 196, 184), rock=(46, 66, 58), lit=(104, 140, 120), pine=(30, 52, 44)),
    "sect": dict(hill=(76, 118, 150), hill_low=(186, 202, 214), rock=(42, 56, 70), lit=(98, 128, 152), pine=(28, 44, 56)),
    "mountain": dict(hill=(128, 104, 76), hill_low=(196, 184, 164), rock=(62, 48, 38), lit=(138, 110, 80), pine=(40, 34, 28)),
    "village": dict(hill=(112, 128, 82), hill_low=(196, 196, 168), rock=(56, 54, 40), lit=(126, 128, 90), pine=(38, 46, 32)),
}


def _rgba(color, alpha):
    h, w = alpha.shape
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = color
    out[..., 3] = alpha
    return out


def _over(dst, src):
    """src 疊在 dst 上（兩者都是 0～1 的 float RGBA，非預乘）"""
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    a = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(a, 1e-6)
    return np.concatenate([rgb, a], -1)


def _to_image(arr):
    return Image.fromarray((np.clip(arr, 0, 1) * 255).round().astype(np.uint8), "RGBA")


def _pine(draw, x, y, size, color, rng):
    """一棵松（國畫畫法）：彎曲的幹，枝頭幾片扁平的針葉團左右錯開，頂上一團最小"""
    c = tuple(int(v) for v in color) + (255,)
    lean = rng.uniform(-0.3, 0.3)
    bend = rng.uniform(-0.12, 0.12)
    trunk = [(x + (lean * t + bend * math.sin(t * math.pi)) * size, y - size * t) for t in np.linspace(0, 1, 8)]
    for i in range(len(trunk) - 1):
        draw.line([trunk[i], trunk[i + 1]], fill=c, width=max(1, int(size / 12 * (1.2 - i / len(trunk)))))
    tiers = int(rng.integers(3, 6))
    for k in range(tiers):
        t = 0.38 + 0.62 * (k + 1) / tiers
        bx, by = x + (lean * t + bend * math.sin(t * math.pi)) * size, y - size * t
        side = 1 if k % 2 == 0 else -1
        reach = size * (0.42 - 0.22 * t) * rng.uniform(0.85, 1.2)
        cx = bx + side * reach * 0.55
        if k == tiers - 1:
            cx = bx
        draw.line([(bx, by), (cx, by - size * 0.02)], fill=c, width=max(1, int(size / 22)))
        hw, hh = reach * 0.75 + size * 0.06, size * rng.uniform(0.05, 0.075)
        # 針葉團：一片淡墨底，上面一束束放射的短針（不是實心的一塊）
        draw.ellipse([cx - hw, by - hh * 1.3, cx + hw, by + hh * 0.4], fill=c[:3] + (120,))
        for _ in range(int(hw / 1.6) + 6):
            px = cx + rng.uniform(-hw * 0.85, hw * 0.85)
            py = by - hh * 0.3 + rng.uniform(-hh * 0.6, hh * 0.3)
            ang = rng.uniform(-2.6, -0.5)
            ln = size * rng.uniform(0.04, 0.08)
            draw.line([(px, py), (px + math.cos(ang) * ln, py + math.sin(ang) * ln)], fill=c[:3] + (230,), width=max(1, int(size / 45)))


def _wrap_draw(img, fn, x, *args):
    """在 x、x-W、x+W 都畫一次，左右接得起來"""
    d = ImageDraw.Draw(img, "RGBA")
    for dx in (-W, 0, W):
        fn(d, x + dx, *args)


def hills(name, seed):
    """兩道丘陵（後面一道淡），山頂上色、往下沒入霧色，山脊勾墨、點苔、松樹。"""
    p = PALETTES[name]
    rng = np.random.default_rng(seed)
    H = 420
    ys = np.arange(H, dtype=np.float32)[:, None]
    out = np.zeros((H, W, 4), np.float32)
    mist = np.array(p["hill_low"], np.float32) / 255
    for depth, (base, harm, fade, alpha) in enumerate([
            (150, [(2, 40), (3, 30), (6, 16), (11, 9), (23, 4)], 150, 0.78),
            (215, [(3, 34), (5, 26), (8, 14), (15, 7), (29, 3)], 120, 0.92)]):
        ridge = base - periodic(rng, W, harm)
        d = ys - ridge[None, :]
        body = np.clip(d / 2.5, 0, 1)
        cloud = noise2d(rng, H, W, 48) * 0.6 + noise2d(rng, H, W, 12) * 0.4
        # 顏色：山頂主色（帶一點雜訊明暗），往下混到霧色
        top = np.array(p["hill"], np.float32) / 255 * (0.95 if depth else 1.12)
        t = np.clip(d / (fade * 1.4), 0, 1)[..., None]
        col = top * (1 - t) + mist * t
        col = col * (0.88 + 0.24 * cloud[..., None])
        a = body * np.clip(1.15 - np.maximum(d, 0) / (fade * 1.6), 0, 1) * alpha
        # 雲氣切過山腰
        cy = rng.uniform(H * 0.55, H * 0.75)
        a *= 1 - 0.6 * np.exp(-((ys - cy) / 22) ** 2) * (0.5 + 0.5 * noise2d(rng, H, W, 96))
        layer = np.concatenate([col, a[..., None]], -1)
        # 山脊墨線
        ink = np.array(p["pine"], np.float32) / 255
        rim = np.exp(-(np.maximum(d, 0) / 2.2) ** 2) * body * (0.55 + 0.45 * cloud) * (0.6 if depth == 0 else 0.85)
        layer = _over(layer, _rgba(ink, rim))
        # 披麻皴：沿坡的淡墨細線
        xs = np.arange(W, dtype=np.float32)[None, :]
        slope = np.gradient(ridge)[None, :]
        streak = np.sin((xs + d * np.sign(slope) * 0.7) * 0.7 + noise2d(rng, H, W, 8) * 5) * 0.5 + 0.5
        cun = body * np.exp(-np.maximum(d, 0) / fade) * (streak > 0.9) * cloud * 0.35
        layer = _over(layer, _rgba(ink, cun))
        img = _to_image(layer)
        # 松與點苔
        x = rng.uniform(0, 80)
        while x < W:
            xi = int(x) % W
            if rng.uniform() < 0.55:
                size = rng.uniform(16, 26) * (0.75 if depth == 0 else 1.0)
                pine_col = np.array(p["pine"]) * (1.25 if depth == 0 else 1.0)
                _wrap_draw(img, _pine, x, ridge[xi] + 3, size, pine_col, rng)
            else:
                for _ in range(rng.integers(3, 7)):
                    dx, dy = rng.uniform(-12, 12), rng.uniform(0, 8)
                    r = rng.uniform(1.4, 2.8)
                    c = tuple(int(v) for v in p["pine"]) + (int(200 * (0.7 if depth == 0 else 1)),)
                    _wrap_draw(img, lambda dr, cx, cy, rr, cc: dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=cc),
                               x + dx, ridge[int(x + dx) % W] + dy, r, c)
            x += rng.uniform(40, 120)
        out = _over(out, np.asarray(img, np.float32) / 255)
    return _to_image(out).filter(ImageFilter.GaussianBlur(0.5))


def near(name, seed):
    """近景：一簇簇深色石塊（上緣亮面、斧劈皴），有的頂著一兩棵松；簇與簇之間空著，看得到後面的古畫。"""
    p = PALETTES[name]
    rng = np.random.default_rng(seed)
    H = 340
    ys = np.arange(H, dtype=np.float32)[:, None]
    xs = np.arange(W, dtype=np.float32)
    env = np.zeros(W, np.float32)
    clumps = []
    x = rng.uniform(100, 300)
    while x < W - 150:
        width = rng.uniform(110, 210)
        height = rng.uniform(100, 210)
        clumps.append((x, width, height))
        for dx in (-W, 0, W):
            u = (xs - x - dx) / width
            skew = rng.uniform(-0.3, 0.3) if dx == 0 else 0
            env = np.maximum(env, height * np.clip(1 - np.abs(u + skew * u * u) ** 2.2, 0, 1) ** 0.55)
        x += width + rng.uniform(260, 620)
    detail = (periodic(rng, W, [(13, 12), (29, 7), (61, 3)]) + np.round(periodic(rng, W, [(41, 8)]) / 6) * 6) * np.clip(env / 120, 0, 1)
    top = H - env - np.where(env > 1, detail, 0)
    d = ys - top[None, :]
    body = np.clip(d / 2.0, 0, 1) * (env[None, :] > 4)
    cloud = noise2d(rng, H, W, 24)
    rock = np.array(p["rock"], np.float32) / 255
    lit = np.array(p["lit"], np.float32) / 255
    # 上緣受光、往下變深；左坡亮右坡暗
    slope = np.gradient(top)[None, :]
    light = np.exp(-np.maximum(d, 0) / 26) * (0.6 + 0.4 * np.tanh(slope * 0.3)) * (0.6 + 0.4 * cloud)
    col = rock + (lit - rock) * np.clip(light, 0, 1)[..., None]
    layer = np.concatenate([col, (body * 0.96)[..., None]], -1)
    # 斧劈皴：斜向的深色短筆
    streak = (np.sin(xs[None, :] * 0.6 + ys * 0.08 + noise2d(rng, H, W, 20) * 4) * 0.5 + 0.5) * (noise2d(rng, H, W, 18) > 0.55)
    ink = np.array(p["pine"], np.float32) / 255 * 0.7
    layer = _over(layer, _rgba(ink, body * (streak > 0.9) * 0.45 * (d > 12)))
    rim = np.exp(-(np.maximum(d, 0) / 2.0) ** 2) * body
    layer = _over(layer, _rgba(ink, rim * 0.9))
    img = _to_image(layer)
    for x, width, height in clumps:
        for _ in range(rng.integers(0, 3)):
            px = x + rng.uniform(-width * 0.4, width * 0.4)
            _wrap_draw(img, _pine, px, top[int(px) % W] + 6, rng.uniform(45, 85), np.array(p["pine"]), rng)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def water(seed):
    """水面：上緣一道淡淡的水岸線，往下幾條長短不一的水波橫筆與粼光；兩頭往上下淡掉。只畫白與墨，顏色由遊戲 modulate。"""
    rng = np.random.default_rng(seed)
    H = 100
    ys = np.arange(H, dtype=np.float32)[:, None]
    band = np.exp(-((ys - 52) / 30) ** 4)
    out = _rgba(np.array([0.86, 0.9, 0.92], np.float32), np.broadcast_to(band * 0.6, (H, W)).copy())
    img = _to_image(out)
    d = ImageDraw.Draw(img)
    for _ in range(110):
        y = rng.uniform(28, 82)
        x = rng.uniform(0, W)
        length = rng.uniform(30, 160) * (0.5 + y / 120)
        dark = rng.uniform() < 0.55
        c = (60, 78, 92, int(rng.uniform(70, 150))) if dark else (255, 255, 255, int(rng.uniform(120, 220)))
        for dx in (-W, 0, W):
            pts = [(x + dx + length * t, y + math.sin(t * 6 + x) * 1.5) for t in np.linspace(0, 1, 8)]
            d.line(pts, fill=c, width=1 if y < 55 else 2)
    shore = (40, 52, 60, 110)
    edge = 26 + periodic(rng, W, [(5, 3), (11, 2), (23, 1)])
    d.line([(i, float(edge[i])) for i in range(0, W, 4)] + [(W, float(edge[0]))], fill=shore, width=2)
    return img.filter(ImageFilter.GaussianBlur(0.7))


def cloudsea(seed):
    """雲海：一層翻湧的雲頭，上緣是一團團圓弧，往下變實；白色，遊戲依天色 modulate。"""
    rng = np.random.default_rng(seed)
    H = 200
    ys = np.arange(H, dtype=np.float32)[:, None]
    crest = 60 - periodic(rng, W, [(7, 10), (13, 9), (29, 6), (53, 3)])
    d = ys - crest[None, :]
    cloud = noise2d(rng, H, W, 40) * 0.6 + noise2d(rng, H, W, 10) * 0.4
    a = np.clip(d / 18, 0, 1) * (0.55 + 0.45 * cloud) * np.clip(1.2 - ys / H, 0, 1)
    # 雲頭陰影：每團雲頭下面一點點灰
    shade = np.exp(-((d - 16) / 8) ** 2) * 0.18
    col = np.ones((H, W, 3), np.float32) - shade[..., None] * np.array([1.0, 0.9, 0.7], np.float32)
    return _to_image(np.concatenate([col, a[..., None]], -1)).filter(ImageFilter.GaussianBlur(1.2))


def main():
    out = ROOT / "art/bg"
    out.mkdir(parents=True, exist_ok=True)
    for i, name in enumerate(PALETTES):
        hills(name, 100 + i).save(out / f"hills_{name}.png", optimize=True)
        near(name, 200 + i).save(out / f"near_{name}.png", optimize=True)
    water(301).save(out / "water.png", optimize=True)
    cloudsea(302).save(out / "cloudsea.png", optimize=True)
    print("layers ->", out)


if __name__ == "__main__":
    main()
