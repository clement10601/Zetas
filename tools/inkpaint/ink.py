"""水墨筆觸的基本工具：畫布、筆畫、暈染、雜訊紋理。

全部用 numpy + Pillow，同一個 seed 每次畫出同一張圖。
座標一律是輸出像素；畫布內部放大 SS 倍畫，最後縮回去當反鋸齒。
"""
import math
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SS = 2

PAPER = (233, 226, 207)
INK = (26, 24, 22)


def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def seed_of(name):
    return zlib.crc32(name.encode("utf-8"))


def mix(c1, c2, t):
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def value_noise(h, w, cell, rng, octaves=4, persistence=0.5):
    """多層 value noise，值域約 0..1。cell 是最粗一層的格子大小（像素）。"""
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for _ in range(octaves):
        gh, gw = max(2, int(h / cell) + 2), max(2, int(w / cell) + 2)
        grid = rng.random((gh, gw)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8), "L").resize(
            (int(gw * cell), int(gh * cell)), Image.BICUBIC)
        out += np.asarray(img, np.float32)[:h, :w] / 255.0 * amp
        total += amp
        amp *= persistence
        cell = max(1.0, cell / 2)
    return out / total


def fbm1d(n, cell, rng, octaves=5, persistence=0.5):
    out = np.zeros(n)
    amp, total = 1.0, 0.0
    for _ in range(octaves):
        k = max(2, int(n / cell) + 3)
        pts = rng.random(k)
        xs = np.arange(n) / cell
        i = np.floor(xs).astype(int)
        f = xs - i
        f = f * f * (3 - 2 * f)
        out += (pts[i] * (1 - f) + pts[np.minimum(i + 1, k - 1)] * f) * amp
        total += amp
        amp *= persistence
        cell = max(1.0, cell / 2)
    return out / total


def chaikin(pts, n=2):
    pts = [tuple(p) for p in pts]
    for _ in range(n):
        if len(pts) < 3:
            break
        out = [pts[0]]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            out += [(x0 * .75 + x1 * .25, y0 * .75 + y1 * .25), (x0 * .25 + x1 * .75, y0 * .25 + y1 * .75)]
        out.append(pts[-1])
        pts = out
    return pts


def resample(pts, step):
    pts = np.asarray(pts, float)
    if len(pts) < 2:
        return pts
    seg = np.hypot(*np.diff(pts, axis=0).T)
    d = np.concatenate([[0], np.cumsum(seg)])
    if d[-1] < 1e-6:
        return pts[:1]
    t = np.linspace(0, d[-1], max(2, int(d[-1] / step) + 1))
    return np.stack([np.interp(t, d, pts[:, 0]), np.interp(t, d, pts[:, 1])], 1)


class Canvas:
    """預乘 alpha 的浮點畫布。opaque=True 時先鋪紙色，暈染用 multiply 疊色。"""

    def __init__(self, w, h, seed, bg=None):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.rng = np.random.default_rng(seed)
        self.prgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        if bg is not None:
            self.prgb[:] = np.array(bg, np.float32) / 255
            self.a[:] = 1
        # 全畫布共用的紋理，筆畫取對應位置，紋理才連得起來
        self.grain = value_noise(self.H, self.W, 6 * SS, self.rng, 3)
        self.cloud = value_noise(self.H, self.W, 90 * SS, self.rng, 5)

    # ---------- 合成 ----------
    def paint(self, mask, color, alpha=1.0, mode="over"):
        """mask 是 (陣列, x0, y0)，陣列在內部解析度。"""
        arr, x0, y0 = mask
        h, w = arr.shape
        xa, ya = max(0, x0), max(0, y0)
        xb, yb = min(self.W, x0 + w), min(self.H, y0 + h)
        if xa >= xb or ya >= yb:
            return
        m = arr[ya - y0:yb - y0, xa - x0:xb - x0] * alpha
        col = np.array(color[:3], np.float32) / 255
        p = self.prgb[ya:yb, xa:xb]
        a = self.a[ya:yb, xa:xb]
        mm = m[..., None]
        if mode == "multiply":
            p *= (1 - mm + mm * col)
        elif mode == "screen":
            p[:] = 1 - (1 - p) * (1 - mm * col)
        else:
            p[:] = p * (1 - mm) + col * mm
            a[:] = a * (1 - m) + m

    def erase(self, mask, amount=1.0):
        arr, x0, y0 = mask
        h, w = arr.shape
        xa, ya, xb, yb = max(0, x0), max(0, y0), min(self.W, x0 + w), min(self.H, y0 + h)
        if xa >= xb or ya >= yb:
            return
        k = 1 - arr[ya - y0:yb - y0, xa - x0:xb - x0] * amount
        self.prgb[ya:yb, xa:xb] *= k[..., None]
        self.a[ya:yb, xa:xb] *= k

    def image(self):
        a = np.clip(self.a, 1e-6, 1)
        rgb = np.clip(self.prgb / a[..., None], 0, 1)
        arr = np.dstack([rgb, np.clip(self.a, 0, 1)])
        img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
        return img.resize((self.w, self.h), Image.LANCZOS)

    # ---------- 遮罩 ----------
    def _bbox_draw(self, pts, pad=4):
        pts = np.asarray(pts, float) * SS
        x0, y0 = np.floor(pts.min(0)).astype(int) - pad * SS
        x1, y1 = np.ceil(pts.max(0)).astype(int) + pad * SS
        img = Image.new("L", (max(1, x1 - x0), max(1, y1 - y0)), 0)
        return img, ImageDraw.Draw(img), pts - (x0, y0), x0, y0

    def poly(self, pts, blur=0.0, pad=None):
        pad = int(max(4, blur * 3)) if pad is None else pad
        img, d, p, x0, y0 = self._bbox_draw(pts, pad)
        d.polygon([tuple(q) for q in p], fill=255)
        if blur > 0:
            img = img.filter(ImageFilter.GaussianBlur(blur * SS))
        return np.asarray(img, np.float32) / 255, x0, y0

    def ellipse(self, cx, cy, rx, ry, blur=0.0, angle=0.0):
        n = 48
        t = np.linspace(0, 2 * math.pi, n, endpoint=False)
        ca, sa = math.cos(angle), math.sin(angle)
        xs, ys = rx * np.cos(t), ry * np.sin(t)
        pts = np.stack([cx + xs * ca - ys * sa, cy + xs * sa + ys * ca], 1)
        return self.poly(pts, blur)

    def rect(self, x0, y0, x1, y1, blur=0.0):
        return self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], blur)

    def clip(self, mask, by):
        """兩個遮罩相乘（例如只在洞口裡畫遠山），回傳整張畫布大小的遮罩。"""
        out = np.zeros((self.H, self.W), np.float32)
        lay = np.zeros((self.H, self.W), np.float32)
        for arr, x0, y0 in (mask, by):
            lay[:] = 0
            h, w = arr.shape
            xa, ya, xb, yb = max(0, x0), max(0, y0), min(self.W, x0 + w), min(self.H, y0 + h)
            lay[ya:yb, xa:xb] = arr[ya - y0:yb - y0, xa - x0:xb - x0]
            out = lay.copy() if (arr is mask[0]) else out * lay
        return out, 0, 0

    def full(self, arr):
        return arr, 0, 0

    def textured(self, mask, k=0.5, field="grain", lo=0.0):
        """乘上紙紋／雲紋：k 越大越斑駁。"""
        arr, x0, y0 = mask
        f = self.grain if field == "grain" else self.cloud
        h, w = arr.shape
        sub = np.ones_like(arr)
        xa, ya, xb, yb = max(0, x0), max(0, y0), min(self.W, x0 + w), min(self.H, y0 + h)
        if xa < xb and ya < yb:
            sub[ya - y0:yb - y0, xa - x0:xb - x0] = f[ya:yb, xa:xb]
        t = np.clip((sub - lo) / max(1e-3, 1 - lo), 0, 1)
        return arr * (1 - k + k * t), x0, y0

    def vgrad(self, mask, y_top, y_bot, a_top=1.0, a_bot=0.0):
        """依垂直位置調整遮罩強度（輸出像素座標）。"""
        arr, x0, y0 = mask
        ys = (np.arange(arr.shape[0]) + y0) / SS
        t = np.clip((ys - y_top) / max(1e-3, y_bot - y_top), 0, 1)
        g = a_top + (a_bot - a_top) * t
        return arr * g[:, None], x0, y0

    # ---------- 筆畫 ----------
    def stroke(self, pts, width, color=INK, alpha=0.92, taper=(0.12, 0.35), dry=0.35,
               jitter=0.18, smooth=2, mode="over", press=None):
        """毛筆線：起筆按下、收筆提起，邊緣有飛白。width 是最粗處（輸出像素）。"""
        pts = resample(chaikin(pts, smooth), 1.5)
        if len(pts) < 2:
            return
        n = len(pts)
        t = np.linspace(0, 1, n)
        if press is None:
            a, b = taper
            prof = np.minimum(smoothstep(0, max(a, 1e-3), t) * 0.85 + 0.15, 1.0)
            prof = np.minimum(prof, 0.08 + 0.92 * smoothstep(1.0, 1.0 - max(b, 1e-3), t))
        else:
            prof = np.interp(t, np.linspace(0, 1, len(press)), press)
        wob = 1 + jitter * (fbm1d(n, 18, self.rng, 3) - 0.5) * 2
        wl = width * prof * wob / 2
        wr = width * prof * (1 + jitter * (fbm1d(n, 18, self.rng, 3) - 0.5) * 2) / 2
        d = np.gradient(pts, axis=0)
        d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-6)[:, None]
        nrm = np.stack([-d[:, 1], d[:, 0]], 1)
        left = pts + nrm * np.maximum(wl, 0.3)[:, None]
        right = pts - nrm * np.maximum(wr, 0.3)[:, None]
        m = self.poly(np.concatenate([left, right[::-1]]), blur=0.35)
        if dry > 0:
            m = self.textured(m, dry, lo=0.25)
        self.paint(m, color, alpha, mode)

    def wash(self, pts, color, alpha=0.5, blur=6.0, tex=0.45, mode="multiply"):
        m = self.textured(self.poly(pts, blur), tex, "cloud")
        self.paint(m, color, alpha, mode)

    def dab(self, cx, cy, r, color=INK, alpha=0.85, squash=0.7, angle=None, blur=0.6, mode="over"):
        """點苔／米點：一團不規則墨點。"""
        angle = self.rng.uniform(0, math.pi) if angle is None else angle
        n = 14
        t = np.linspace(0, 2 * math.pi, n, endpoint=False)
        rr = r * (0.75 + 0.5 * self.rng.random(n))
        xs, ys = rr * np.cos(t), rr * squash * np.sin(t)
        ca, sa = math.cos(angle), math.sin(angle)
        pts = np.stack([cx + xs * ca - ys * sa, cy + xs * sa + ys * ca], 1)
        self.paint(self.textured(self.poly(chaikin(pts, 2) + [chaikin(pts, 2)[0]], blur), 0.3), color, alpha, mode)

    def text(self, s, x, y, size, color, alpha=0.9, font=None, vertical=False, anchor="lt"):
        """寫字（書法字型）。vertical=True 由上往下直書。"""
        f = ImageFont.truetype(font, int(size * SS))
        chars = list(s) if vertical else [s]
        step = size * 1.05
        for i, ch in enumerate(chars):
            cx, cy = (x, y + i * step) if vertical else (x, y)
            bb = f.getbbox(ch, anchor=anchor)
            w, h = bb[2] - bb[0] + 8 * SS, bb[3] - bb[1] + 8 * SS
            img = Image.new("L", (w, h), 0)
            ImageDraw.Draw(img).text((-bb[0] + 4 * SS, -bb[1] + 4 * SS), ch, fill=255, font=f, anchor=anchor)
            arr = np.asarray(img.filter(ImageFilter.GaussianBlur(0.4 * SS)), np.float32) / 255
            m = (arr, int(cx * SS + bb[0] - 4 * SS), int(cy * SS + bb[1] - 4 * SS))
            self.paint(self.textured(m, 0.25, lo=0.2), color, alpha)
