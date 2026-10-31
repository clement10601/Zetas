"""產生全畫面疊的宣紙纖維貼圖 art/ui/paper_grain.png（可左右上下無縫鋪）。
值接近白、纖維略暗，遊戲用乘法疊上去（強度約 0.08），讓古畫、程式畫角色、介面像在同一張紙上。
python tools/paper_grain.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

N = 512
rng = np.random.default_rng(20261031)
fib = np.zeros((N, N), np.float32)
# 纖維：很多條短而彎的細線，用環繞座標畫，所以可以無縫鋪
for _ in range(1400):
    x, y = rng.uniform(0, N, 2)
    ang = rng.uniform(0, np.pi)
    length = rng.uniform(8, 40)
    curve = rng.uniform(-0.04, 0.04)
    w = rng.uniform(0.3, 1.0)
    for t in np.linspace(0, length, int(length * 2)):
        a = ang + curve * t
        px, py = int(x + np.cos(a) * t) % N, int(y + np.sin(a) * t) % N
        fib[py, px] = max(fib[py, px], w)
# 紙漿的雲紋：低頻雜訊（用環繞的高斯模糊）
cloud = rng.random((N, N)).astype(np.float32)
big = np.tile(cloud, (3, 3))
big = np.asarray(Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10)), np.float32) / 255
cloud = big[N:2 * N, N:2 * N]
cloud = (cloud - cloud.min()) / max(1e-6, cloud.max() - cloud.min())
fine = rng.random((N, N)).astype(np.float32)
big = np.tile(fib, (3, 3))
big = np.asarray(Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255
fib = big[N:2 * N, N:2 * N]
dark = np.clip(0.3 * fib + 0.45 * cloud + 0.25 * fine, 0, 1)
STRENGTH = 0.15  # 乘法強度直接烤進圖裡：平均約暗 0.06–0.08
val = 1.0 - STRENGTH * dark  # 1 = 不變暗
out = Path(__file__).resolve().parents[1] / "art/ui/paper_grain.png"
out.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray((val * 255).round().astype(np.uint8), "L").save(out)
print("wrote", out)
