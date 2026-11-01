"""區塊圖的天空遮罩：把畫上方空白的天（紙／絹底）設成透明，讓遊戲在後面疊一層層遠山。

做法：每一欄從上往下找第一個「有東西」的位置（比紙色暗、或筆觸多），左右用中位數抹平當天際線；
天際線以上透明、往下 48px 漸變到不透明。天裡比紙色明顯暗的東西（題字、印、飛鳥、遠山）保留半透明，
所以題字不會不見。用法：python -m tools.inkpaint.skyline（全部區塊就地改寫並更新 content/sky.json；重跑結果相同）
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

FEATHER = 48
MAX_SKY = 0.72          # 天際線最低只到畫高的這個比例，下面一定不透明


def _box(a, r):
    """2D 方框模糊（積分圖）"""
    p = np.pad(a, r, mode="edge")
    c = p.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def sky_alpha(img):
    a = np.asarray(img.convert("RGB"), np.float32) / 255
    h, w = a.shape[:2]
    g = a @ np.array([0.3, 0.59, 0.11], np.float32)
    mean = _box(g, 6)
    std = np.sqrt(np.maximum(_box(g * g, 6) - mean * mean, 0))
    top = mean[: h // 8]
    paper = float(np.percentile(top, 70))
    empty = (mean > paper - 0.07) & (std < 0.035)
    # 每欄：連續 10 列都「空」才算天，找第一個不空的列
    run = np.ones(w, bool)
    line = np.full(w, int(h * MAX_SKY), np.float32)
    for y in range(int(h * MAX_SKY)):
        run &= empty[y]
        hit = (~run) & (line == int(h * MAX_SKY))
        line[hit] = y
        if not run.any():
            break
    # 題字、印章那幾欄會讓天際線突然跳到頂，用寬的中位數抹掉，再取小一點的平均讓線條柔和
    k = 91
    pad = np.pad(line, k // 2, mode="edge")
    med = np.array([np.median(pad[i:i + k]) for i in range(w)], np.float32)
    sm = np.convolve(np.pad(med, 15, mode="edge"), np.ones(31) / 31, mode="valid")
    ys = np.arange(h, dtype=np.float32)[:, None]
    ramp = np.clip((ys - (sm[None, :] - FEATHER)) / FEATHER, 0, 1)
    ramp = ramp * ramp * (3 - 2 * ramp)
    # 天裡比紙色暗的筆墨保留
    ink = np.clip((paper - 0.05 - g) / 0.22, 0, 1)
    alpha = np.maximum(ramp, ink)
    sky = (ys < sm[None, :] - FEATHER) & empty
    color = a[sky].mean(0) if sky.sum() > 200 else a[: h // 10].reshape(-1, 3).mean(0)
    return alpha, paper, color


def apply(path):
    """就地改寫 alpha，回傳天色（#rrggbb）；暗的區塊（洞窟）不處理，回傳 None。"""
    img = Image.open(path).convert("RGBA")
    alpha, paper, color = sky_alpha(img)
    if paper < 0.45:
        return None
    arr = np.asarray(img).copy()
    arr[..., 3] = (np.minimum(arr[..., 3] / 255, alpha) * 255).round().astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path, optimize=True)
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in color)


def update_all():
    """所有區塊圖加天空遮罩，天色寫進 content/sky.json（遊戲拿來畫遠山後面的天）。"""
    root = Path(__file__).resolve().parents[2]
    out = {}
    path = root / "content/sky.json"
    old = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    for p in sorted((root / "art/chunks").glob("chunk.*.png")):
        img = np.asarray(Image.open(p).convert("RGBA"))
        if img[: img.shape[0] // 4, :, 3].mean() < 20:
            # 戶外區塊（chunks.REGION）本來就只畫坡腳與建築、上面透明：不用再找天，天色沿用
            if p.stem in old:
                out[p.stem] = old[p.stem]
            continue
        c = apply(p) or old.get(p.stem)
        if c:
            out[p.stem] = c
    data = {"_comment": "區塊圖天空（透明處）後面的天色，tools/inkpaint/skyline.py 產生"}
    data.update(out)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return out


if __name__ == "__main__":
    if sys.argv[1:]:
        for p in sys.argv[1:]:
            print("sky", p, apply(p))
    else:
        print(update_all())
