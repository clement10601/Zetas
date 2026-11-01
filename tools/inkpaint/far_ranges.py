"""遠山層：左右可以無縫重複的水墨山脊，給遊戲疊在古畫後面、捲得很慢的幾層遠景。

每層一條起伏的山脊線（整數倍頻率的正弦疊加，所以頭尾接得起來），山脊下往下漸淡成霧（高遠：
山頭清楚、山腳沒入雲氣），山脊沿線一道淡墨勾邊，山體上有順坡的乾筆皴。只畫墨色與透明度，
顏色由遊戲依地區調（modulate）。

用法：python -m tools.inkpaint.far_ranges   → art/bg/ranges_far.png、art/bg/ranges_mid.png
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
W, H = 2048, 480


def periodic(rng, n, harmonics):
    x = np.arange(n) / n
    y = np.zeros(n, np.float32)
    for k, amp in harmonics:
        y += amp * np.sin(2 * np.pi * (k * x + rng.uniform()))
    return y


def noise2d(rng, h, w, cell):
    """可左右重複的平滑雜訊"""
    gh, gw = h // cell + 2, w // cell
    g = rng.uniform(0, 1, (gh, gw)).astype(np.float32)
    g = np.concatenate([g, g[:, :1]], 1)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + cell, (gh) * cell), Image.BICUBIC)
    return np.asarray(img, np.float32)[:h, :w] / 255


def layer(seed, base, harmonics, fall, alpha, edge, cun):
    rng = np.random.default_rng(seed)
    ridge = base - periodic(rng, W, harmonics)
    ys = np.arange(H, dtype=np.float32)[:, None]
    d = ys - ridge[None, :]                         # 山脊以下的距離
    body = np.clip(d / 3.0, 0, 1)                   # 山脊邊緣柔一點
    fade = np.exp(-np.maximum(d, 0) / fall)         # 往下沒入雲氣
    cloud = noise2d(rng, H, W, 64) * 0.55 + noise2d(rng, H, W, 16) * 0.45
    a = body * (0.08 + 0.92 * fade) * (0.75 + 0.5 * cloud)
    # 雲氣切過山腰：幾條水平的淡帶把山體切斷
    for _ in range(3):
        cy = rng.uniform(H * 0.45, H * 0.85)
        band = np.exp(-((ys - cy) / rng.uniform(14, 30)) ** 2) * (0.6 + 0.4 * noise2d(rng, H, W, 128))
        a *= 1 - 0.75 * band
    # 山脊勾邊
    rim = np.exp(-(np.maximum(d, 0) / 2.5) ** 2) * body
    a = np.maximum(a * alpha, rim * edge * (0.6 + 0.4 * cloud))
    # 皴：沿坡往下的乾筆短線（用斜向雜訊條紋近似）
    xs = np.arange(W, dtype=np.float32)[None, :]
    slope = np.gradient(ridge)[None, :]
    streak = np.sin((xs + d * np.sign(slope) * 0.6) * 0.9 + noise2d(rng, H, W, 8) * 6) * 0.5 + 0.5
    a += cun * body * np.exp(-np.maximum(d, 0) / (fall * 0.6)) * (streak > 0.86) * cloud
    a = np.clip(a, 0, 1)
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = (40, 44, 50)
    rgba[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(rgba, "RGBA").filter(ImageFilter.GaussianBlur(0.6))


def main():
    out = ROOT / "art/bg"
    out.mkdir(parents=True, exist_ok=True)
    # 最遠：高而尖的峰群，很淡
    layer(11, 230, [(3, 70), (5, 42), (9, 26), (17, 12), (31, 7), (57, 3)], 55, 0.45, 0.6, 0.0).save(out / "ranges_far.png", optimize=True)
    # 中遠：較低、較寬的山，濃一點、有皴
    layer(23, 320, [(2, 40), (4, 34), (7, 22), (13, 14), (27, 7), (49, 4)], 45, 0.62, 0.85, 0.15).save(out / "ranges_mid.png", optimize=True)
    print("ranges ->", out)


if __name__ == "__main__":
    main()
