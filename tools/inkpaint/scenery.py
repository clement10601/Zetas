"""場景元件：天色、遠山、松、竹、屋簷、山門……都用 ink.py 的筆畫組成。"""
import math
from pathlib import Path

import numpy as np

from .ink import INK, fbm1d, mix, smoothstep

FONT = str(Path(__file__).with_name("fonts") / "Zetas-Kai.ttf")

# 區塊左右兩端統一過渡到這些高度與色調，任兩塊接起來都不會斷
EDGE_SKY = (218, 214, 198)
EDGE_FAR = 330
EDGE_MID = 420
EDGE_FADE = 140

THEMES = {
    "forest": {"sky": ((196, 208, 196), (232, 226, 206)), "far": (104, 120, 122), "mid": (66, 92, 80), "near": (44, 60, 48)},
    "sect": {"sky": ((194, 208, 218), (234, 230, 214)), "far": (112, 126, 140), "mid": (78, 94, 106), "near": (52, 60, 66)},
    "mountain": {"sky": ((176, 168, 156), (214, 204, 184)), "far": (100, 96, 92), "mid": (64, 60, 56), "near": (36, 34, 32)},
    "illusion": {"sky": ((34, 8, 12), (104, 26, 30)), "far": (60, 14, 20), "mid": (28, 8, 10), "near": (10, 6, 6)},
}
ILLUSION_EDGE = (70, 18, 22)


def edge_weight(w):
    """0 在兩端、1 在中段：用來把東西收斂到 EDGE_* 標準值。"""
    x = np.arange(w)
    return smoothstep(0, EDGE_FADE, np.minimum(x, w - 1 - x))


# ---------- 天與山 ----------

def sky(cv, theme, edge=EDGE_SKY):
    top, bot = THEMES[theme]["sky"]
    ys = np.linspace(0, 1, cv.H)[:, None, None]
    col = np.array(top, np.float32) * (1 - ys) + np.array(bot, np.float32) * ys
    ew = np.repeat(edge_weight(cv.w), 2)[None, :, None]
    edge_col = np.array(edge, np.float32)
    # 兩端：上半保留天色、下半收斂到標準色
    col = col * ew + (col * 0.5 + edge_col * 0.5) * (1 - ew)
    cv.prgb[:] = col / 255
    cv.a[:] = 1
    # 淡淡的雲紋
    m = cv.textured(cv.full(np.ones((cv.H, cv.W), np.float32)), 1.0, "cloud", lo=0.55)
    cv.paint(m, (255, 255, 255) if theme != "illusion" else (140, 30, 30), 0.18, "screen")


def ridge(cv, base, amp, cell, edge_y, peaks=None):
    w = cv.w
    y = base - amp * (fbm1d(w, cell, cv.rng, 5) - 0.3)
    if peaks:
        xs = np.arange(w)
        for px, ph, pw in peaks:
            y -= ph * np.exp(-((xs - px) / pw) ** 2)
    ew = edge_weight(w)
    return y * ew + edge_y * (1 - ew)


def mountains(cv, y, color, alpha=0.55, mist=140, ink_edge=0.0, cuns=0, bottom=600):
    """一層山：輪廓 y（每個輸出像素一個值），往下漸淡成霧。"""
    w = cv.w
    pts = [(x, y[x]) for x in range(0, w, 3)] + [(w - 1, y[-1]), (w - 1, bottom), (0, bottom)]
    m = cv.poly(pts, blur=1.5)
    top = float(np.min(y))
    m = cv.vgrad(m, top + 20, top + 20 + mist, 1.0, 0.15)
    cv.paint(cv.textured(m, 0.5, "cloud"), color, alpha, "multiply")
    if ink_edge > 0:
        # 山脊線斷斷續續地描
        x = 30
        while x < w - 30:
            L = int(cv.rng.integers(60, 220))
            xs = range(x, min(w - 1, x + L), 6)
            cv.stroke([(xx, y[xx] + 1) for xx in xs], ink_edge, mix(color, INK, 0.6), 0.75, dry=0.5)
            x += L + int(cv.rng.integers(10, 80))
    for _ in range(cuns):
        # 皴法：貼著山脊往下的短筆，順著坡向
        x = int(cv.rng.uniform(40, w - 40))
        slope = (y[min(w - 1, x + 6)] - y[max(0, x - 6)]) / 12
        yy = y[x] + cv.rng.uniform(4, 30)
        L = cv.rng.uniform(10, 22)
        dx = -L * 0.5 if slope > 0 else L * 0.5
        cv.stroke([(x, yy), (x + dx * 0.5, yy + L * 0.5), (x + dx, yy + L)], 1.8,
                  mix(color, INK, 0.45), 0.25, dry=0.6)


def mist(cv, y, h, color=(240, 238, 228), alpha=0.6):
    m = cv.vgrad(cv.rect(-10, y - h, cv.w + 10, y + h, blur=h / 3), y - h, y + h, 0.0, 1.0)
    arr, x0, y0 = m
    mid = arr.shape[0] // 2
    arr = arr.copy()
    arr[mid:] = arr[mid - 1::-1][:arr.shape[0] - mid]
    cv.paint(cv.textured((arr, x0, y0), 0.7, "cloud"), color, alpha)


def moon(cv, x, y, r, color, alpha=0.9, halo=None):
    if halo:
        cv.paint(cv.ellipse(x, y, r * 2.2, r * 2.2, blur=r * 0.8), halo, 0.35, "screen")
    cv.paint(cv.textured(cv.ellipse(x, y, r, r, blur=1.0), 0.25, "cloud"), color, alpha)


def cloud_scroll(cv, x, y, s, color, alpha=0.5):
    """祥雲：幾個捲曲的圈。"""
    for i, (dx, r) in enumerate([(0, 1.0), (1.6, 0.8), (-1.4, 0.7)]):
        cx = x + dx * s * 20
        t = np.linspace(0, 2.6 * math.pi, 40)
        rr = s * 14 * r * (1 - t / (3.2 * math.pi))
        pts = [(cx + rr[k] * math.cos(t[k] + i), y + rr[k] * 0.6 * math.sin(t[k] + i)) for k in range(len(t))]
        cv.stroke(pts, 2.5 * s, color, alpha, dry=0.3, taper=(0.05, 0.6))
    cv.stroke([(x - s * 40, y + s * 10), (x + s * 50, y + s * 10)], 2 * s, color, alpha * 0.8, taper=(0.3, 0.4))


# ---------- 樹木花草 ----------

def pine(cv, x, gy, h, lean=0.0, color=INK, alpha=0.9):
    rng = cv.rng
    pts, cx = [], x
    for i in range(7):
        t = i / 6
        cx += lean * h * 0.06 + rng.uniform(-1, 1) * h * 0.025
        pts.append((cx, gy - t * h))
    tw = max(3.0, h * 0.045)
    cv.stroke(pts, tw, color, alpha, taper=(0.0, 0.6), press=[1.0, 0.95, 0.85, 0.6, 0.35], dry=0.5)
    cv.stroke([(p[0] + tw * 0.4, p[1]) for p in pts[:-2]], tw * 0.35, color, alpha * 0.6, dry=0.7)
    # 枝與針葉團
    for i in range(3, 8):
        t = i / 7
        px, py = np.interp(t, np.linspace(0, 1, 7), [p[0] for p in pts]), gy - t * h
        side = 1 if i % 2 else -1
        L = h * (0.32 - 0.22 * t) * rng.uniform(0.8, 1.2)
        ex, ey = px + side * L, py - L * 0.12
        cv.stroke([(px, py), (px + side * L * 0.5, py + L * 0.06), (ex, ey)], tw * 0.45, color, alpha, dry=0.5)
        needles(cv, ex - side * L * 0.25, ey - h * 0.03, L * 0.75, h * 0.07, color, alpha)
    needles(cv, pts[-1][0], pts[-1][1], h * 0.22, h * 0.07, color, alpha)


def needles(cv, cx, cy, w, h, color, alpha):
    """松針：一叢扁平的墨團加細碎的線。"""
    cv.paint(cv.textured(cv.ellipse(cx, cy, w / 2, h / 2, blur=2), 0.5), color, alpha * 0.55)
    for _ in range(int(w / 3)):
        x = cx + cv.rng.uniform(-w / 2, w / 2)
        y = cy + cv.rng.uniform(-h / 3, h / 4)
        L = cv.rng.uniform(4, 9)
        cv.stroke([(x - L, y + L * 0.3), (x, y - L * 0.2), (x + L, y + L * 0.3)], 1.6, color, alpha * 0.8, dry=0.2, smooth=1)


def leafy_tree(cv, x, gy, h, color=INK, leaf=None, alpha=0.9):
    """米點樹：彎曲樹幹加一層層點苔。"""
    rng = cv.rng
    leaf = leaf or color
    top = (x + rng.uniform(-h * 0.1, h * 0.1), gy - h * 0.62)
    cv.stroke([(x, gy), (x + rng.uniform(-6, 6), gy - h * 0.3), top], max(3, h * 0.05), color, alpha,
              press=[1, 0.8, 0.5], dry=0.5)
    for k in range(3):
        a = rng.uniform(-2.4, -0.7)
        L = h * rng.uniform(0.18, 0.3)
        sx, sy = x + (top[0] - x) * 0.6, gy - h * (0.35 + 0.1 * k)
        cv.stroke([(sx, sy), (sx + math.cos(a) * L, sy + math.sin(a) * L)], h * 0.02 + 1, color, alpha, dry=0.5)
    for _ in range(4):
        bx = top[0] + rng.uniform(-h * 0.28, h * 0.28)
        by = top[1] - h * 0.05 + rng.uniform(-h * 0.18, h * 0.12)
        cv.paint(cv.textured(cv.ellipse(bx, by, h * 0.17, h * 0.11, blur=h * 0.03), 0.6, "cloud"), leaf, alpha * 0.35, "multiply")
        for _ in range(int(h * 0.3)):
            ang = rng.uniform(0, 2 * math.pi)
            rad = math.sqrt(rng.random())
            cv.dab(bx + math.cos(ang) * rad * h * 0.17, by + math.sin(ang) * rad * h * 0.1,
                   rng.uniform(2.5, 4.5) * h / 160, leaf, alpha * rng.uniform(0.35, 0.85), squash=0.45, angle=rng.uniform(-0.3, 0.3))


def bare_branch(cv, x, y, L, ang, depth, w, color=INK, alpha=0.85):
    if depth == 0 or L < 4:
        return
    ex, ey = x + math.cos(ang) * L, y + math.sin(ang) * L
    mx, my = (x + ex) / 2 + cv.rng.uniform(-L, L) * 0.1, (y + ey) / 2 + cv.rng.uniform(-L, L) * 0.1
    cv.stroke([(x, y), (mx, my), (ex, ey)], w, color, alpha, dry=0.5, taper=(0.0, 0.5))
    for s in (-1, 1):
        bare_branch(cv, ex, ey, L * cv.rng.uniform(0.55, 0.75), ang + s * cv.rng.uniform(0.3, 0.7), depth - 1, w * 0.62, color, alpha)


def dead_tree(cv, x, gy, h, color=INK, alpha=0.9):
    cv.stroke([(x, gy), (x + h * 0.05, gy - h * 0.4), (x - h * 0.03, gy - h * 0.6)], h * 0.06, color, alpha, press=[1, 0.7, 0.4])
    bare_branch(cv, x - h * 0.03, gy - h * 0.6, h * 0.25, -1.9, 4, h * 0.03, color, alpha)
    bare_branch(cv, x + h * 0.03, gy - h * 0.45, h * 0.22, -0.7, 4, h * 0.025, color, alpha)


def bamboo(cv, x, gy, h, color, alpha=0.85, lean=0.0):
    rng = cv.rng
    seg = h / rng.integers(6, 9)
    y, cx = gy, x
    while y > gy - h:
        ny = y - seg
        nx = cx + lean * seg
        cv.stroke([(cx, y - 2), (nx, ny + 2)], 5, color, alpha, taper=(0.1, 0.1), dry=0.3, smooth=0)
        if rng.random() < 0.45:
            for _ in range(rng.integers(2, 4)):
                a = rng.uniform(-0.6, 0.6) + (0 if rng.random() < 0.5 else math.pi)
                L = rng.uniform(16, 30)
                cv.stroke([(nx, ny), (nx + math.cos(a) * L * 0.5, ny + 6), (nx + math.cos(a) * L, ny + 4 + rng.uniform(4, 14))],
                          5, color, alpha * 0.9, taper=(0.1, 0.8), dry=0.2)
        y, cx = ny, nx


def grass(cv, x0, x1, gy, density=0.25, color=INK, alpha=0.7, hmax=22):
    rng = cv.rng
    for _ in range(int((x1 - x0) * density)):
        x = rng.uniform(x0, x1)
        h = rng.uniform(6, hmax)
        bend = rng.uniform(-0.6, 0.6) * h
        cv.stroke([(x, gy), (x + bend * 0.3, gy - h * 0.6), (x + bend, gy - h)], rng.uniform(1.4, 2.6), color,
                  alpha * rng.uniform(0.5, 1), taper=(0.0, 0.9), dry=0.2, smooth=1)


def rock(cv, x, gy, w, h, color, alpha=0.8):
    rng = cv.rng
    n = 9
    pts = []
    for i in range(n + 1):
        t = i / n
        ang = math.pi * (1 - t)
        r = rng.uniform(0.75, 1.05)
        pts.append((x + math.cos(ang) * w / 2 * r, gy - math.sin(ang) * h * r))
    cv.wash(pts + [(x + w / 2, gy), (x - w / 2, gy)], color, alpha * 0.7, blur=1.5, tex=0.5)
    cv.stroke(pts, max(2, w * 0.04), INK, alpha, dry=0.5)
    for _ in range(int(w / 18)):
        sx = x + rng.uniform(-w * 0.3, w * 0.3)
        sy = gy - rng.uniform(h * 0.2, h * 0.8)
        cv.stroke([(sx, sy), (sx - 5, sy + 8), (sx - 7, sy + 16)], 1.8, INK, 0.45, dry=0.6)


def ground_strip(cv, theme, density=1.0, with_grass=True):
    """畫面最下面的近景：草、碎石，壓得很低，不擋角色。"""
    c = THEMES[theme]["near"]
    w = cv.w
    m = cv.vgrad(cv.rect(-5, 560, w + 5, 605, blur=6), 560, 600, 0.0, 1.0)
    cv.paint(cv.textured(m, 0.5, "cloud"), c, 0.55, "multiply")
    if theme != "illusion" and with_grass:
        grass(cv, 20, w - 20, 600, 0.2 * density, c, 0.75)


# ---------- 建築 ----------

def roof(cv, cx, y, w, h, color=INK, alpha=0.95, curl=0.25):
    """飛簷：屋脊、兩端上翹的弧線屋面。y 是屋簷最低處。"""
    L, R = cx - w / 2, cx + w / 2
    ridge_y = y - h
    pts = [(L - w * 0.06, y - h * curl), (L + w * 0.08, y), (cx, y + h * 0.05), (R - w * 0.08, y), (R + w * 0.06, y - h * curl),
           (R - w * 0.14, ridge_y + h * 0.15), (cx, ridge_y), (L + w * 0.14, ridge_y + h * 0.15)]
    cv.wash(pts, color, alpha * 0.8, blur=1.0, tex=0.3, mode="over")
    cv.stroke([(L - w * 0.08, y - h * curl * 1.4), (L + w * 0.08, y), (cx, y + h * 0.05), (R - w * 0.08, y), (R + w * 0.08, y - h * curl * 1.4)],
              max(2.5, h * 0.12), INK, alpha, dry=0.3, taper=(0.1, 0.1))
    cv.stroke([(L + w * 0.1, ridge_y + h * 0.12), (cx, ridge_y - h * 0.02), (R - w * 0.1, ridge_y + h * 0.12)], max(2.5, h * 0.14), INK, alpha, dry=0.3)
    # 瓦楞
    for k in range(1, 12):
        xx = L + w * k / 12
        cv.stroke([(xx + (cx - xx) * 0.25, ridge_y + h * 0.2), (xx, y - 2)], 1.2, INK, alpha * 0.35, dry=0.5, smooth=0)


def plaque(cv, cx, cy, text, w=None, size=22, board=(60, 34, 24), ink=(214, 178, 96)):
    w = w or size * (len(text) + 0.8)
    h = size * 1.5
    cv.paint(cv.rect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, blur=0.5), board, 0.95)
    cv.stroke([(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2), (cx - w / 2, cy - h / 2)],
              2, INK, 0.8, smooth=0, taper=(0.02, 0.02))
    cv.text(text, cx - size * len(text) / 2 * 1.0, cy - size * 0.62, size, ink, 0.95, FONT)


# 殿堂開間數：傳統殿宇是單數開間（正中是明間、沒有中柱），柱子是雙數
HALL_BAYS = 5


def hall(cv, cx, gy, w, h, wall=(196, 184, 160), pillar=(120, 40, 30), roof_c=(52, 58, 66), text=None, alpha=1.0, tiers=1):
    """殿堂：台基、柱、牆、飛簷，可加匾額。"""
    base_h = h * 0.1
    cv.paint(cv.rect(cx - w * 0.55, gy - base_h, cx + w * 0.55, gy, blur=0.6), (150, 144, 132), 0.9 * alpha)
    cv.stroke([(cx - w * 0.55, gy - base_h), (cx + w * 0.55, gy - base_h)], 2, INK, 0.7 * alpha, smooth=0)
    top = gy - h * 0.62
    cv.paint(cv.textured(cv.rect(cx - w * 0.42, top, cx + w * 0.42, gy - base_h, blur=0.6), 0.3, "cloud"), wall, 0.92 * alpha)
    n = HALL_BAYS
    for k in range(n + 1):
        px = cx - w * 0.4 + w * 0.8 * k / n
        cv.paint(cv.rect(px - 4, top, px + 4, gy - base_h), pillar, 0.9 * alpha)
        cv.stroke([(px - 4, top), (px - 4, gy - base_h)], 1.4, INK, 0.5 * alpha, smooth=0)
    # 門窗格
    for k in range(1, n - 1):
        if k == n // 2:
            continue                       # 正中明間是敞開的殿門
        px = cx - w * 0.4 + w * 0.8 * (k + 0.5) / n
        for yy in np.arange(top + 14, gy - base_h - 8, 9):
            cv.stroke([(px - w * 0.04, yy), (px + w * 0.04, yy)], 1, INK, 0.25 * alpha, smooth=0, dry=0.3)
    roof(cv, cx, top + 6, w, h * 0.32, roof_c, alpha)
    if tiers > 1:
        t2 = top - h * 0.3
        cv.paint(cv.rect(cx - w * 0.28, t2, cx + w * 0.28, top - h * 0.18, blur=0.6), wall, 0.92 * alpha)
        roof(cv, cx, t2 + 4, w * 0.66, h * 0.26, roof_c, alpha)
    if text:
        plaque(cv, cx, top + h * 0.03 - (h * 0.3 if tiers > 1 else 0) + (0 if tiers == 1 else h * 0.12), text, size=max(14, h * 0.07))


def pagoda(cv, cx, gy, h, color, alpha=0.5, levels=7):
    lw = h * 0.22
    y = gy
    for i in range(levels):
        lh = h / levels
        w = lw * (1 - i * 0.07)
        cv.paint(cv.rect(cx - w * 0.35, y - lh, cx + w * 0.35, y), color, alpha * 0.8, "multiply")
        roof(cv, cx, y - lh * 0.75, w, lh * 0.35, color, alpha, curl=0.4)
        y -= lh
    cv.stroke([(cx, y), (cx, y - h * 0.08)], 2, color, alpha)


def paifang(cv, cx, gy, w, h, text, wood=(110, 36, 28), roof_c=(40, 46, 52)):
    """牌樓山門：四柱三間、主簷加兩側小簷、中間匾額。"""
    cols = [cx - w * 0.5, cx - w * 0.2, cx + w * 0.2, cx + w * 0.5]
    for i, x in enumerate(cols):
        top = gy - h * (0.78 if i in (1, 2) else 0.6)
        cv.paint(cv.rect(x - 7, top, x + 7, gy), wood, 0.95)
        cv.stroke([(x - 7, top), (x - 7, gy)], 2, INK, 0.7, smooth=0)
        cv.paint(cv.rect(x - 14, gy - 26, x + 14, gy), (140, 132, 120), 0.95)
    for y, x0, x1 in [(gy - h * 0.62, cols[1], cols[2]), (gy - h * 0.45, cols[0], cols[1]), (gy - h * 0.45, cols[2], cols[3])]:
        cv.paint(cv.rect(x0 - 10, y - 10, x1 + 10, y + 6), wood, 0.95)
        cv.stroke([(x0 - 10, y + 6), (x1 + 10, y + 6)], 2, INK, 0.7, smooth=0)
    roof(cv, (cols[0] + cols[1]) / 2, gy - h * 0.6, w * 0.36, h * 0.1, roof_c)
    roof(cv, (cols[2] + cols[3]) / 2, gy - h * 0.6, w * 0.36, h * 0.1, roof_c)
    roof(cv, cx, gy - h * 0.78, w * 0.52, h * 0.15, roof_c)
    plaque(cv, cx, gy - h * 0.7, text, size=h * 0.075, board=(30, 40, 60))


def house(cv, cx, gy, w, h, thatch=(120, 100, 70), wall=(200, 186, 160), alpha=1.0, lantern=False, skew=0.0):
    sk = lambda x, y: (x + skew * (gy - y), y)
    wall_top = gy - h * 0.55
    cv.paint(cv.textured(cv.poly([sk(cx - w * 0.4, wall_top), sk(cx + w * 0.4, wall_top), sk(cx + w * 0.4, gy), sk(cx - w * 0.4, gy)], 0.6), 0.4, "cloud"), wall, 0.92 * alpha)
    for x in (cx - w * 0.4, cx + w * 0.4):
        cv.stroke([sk(x, wall_top), sk(x, gy)], 2.4, INK, 0.75 * alpha, smooth=0)
    cv.paint(cv.poly([sk(cx - w * 0.08, gy - h * 0.38), sk(cx + w * 0.08, gy - h * 0.38), sk(cx + w * 0.08, gy), sk(cx - w * 0.08, gy)]), (60, 46, 34), 0.9 * alpha)
    cv.paint(cv.poly([sk(cx + w * 0.18, gy - h * 0.4), sk(cx + w * 0.32, gy - h * 0.4), sk(cx + w * 0.32, gy - h * 0.28), sk(cx + w * 0.18, gy - h * 0.28)]), (50, 40, 30), 0.8 * alpha)
    pts = [sk(cx - w * 0.55, wall_top + 4), sk(cx, gy - h), sk(cx + w * 0.55, wall_top + 4)]
    cv.wash(pts, thatch, 0.9 * alpha, blur=1, tex=0.6, mode="over")
    for k in range(14):
        t = k / 13
        bx = cx - w * 0.55 + w * 1.1 * t
        cv.stroke([sk(cx + (bx - cx) * 0.15, gy - h * 0.95), sk(bx, wall_top + 4)], 1.2, INK, 0.3 * alpha, dry=0.6, smooth=0)
    cv.stroke(pts, 3, INK, 0.85 * alpha, dry=0.4)
    if lantern:
        lx, ly = sk(cx - w * 0.3, wall_top + 18)
        cv.stroke([(lx, wall_top + 4), (lx, ly - 8)], 1.2, INK, 0.8)
        cv.paint(cv.ellipse(lx, ly + 6, 18, 18, blur=10), (255, 90, 60), 0.35, "screen")
        cv.paint(cv.ellipse(lx, ly + 6, 7, 10, blur=0.6), (196, 40, 36), 0.95)


def seal(cv, x, y, s=26, text="仙魔", color=(178, 34, 34)):
    """朱印：紅底白字的小方印。"""
    cv.paint(cv.textured(cv.rect(x, y, x + s, y + s, blur=0.4), 0.35, lo=0.15), color, 0.85)
    fs = s * 0.42
    cv.text(text[0], x + s * 0.08, y + s * 0.04, fs, (240, 226, 210), 0.9, FONT)
    if len(text) > 1:
        cv.text(text[1], x + s * 0.08, y + s * 0.5, fs, (240, 226, 210), 0.9, FONT)


def inscription(cv, name, color=INK, alpha=0.5):
    """右上角直書題字加朱印（水墨卷軸感）。"""
    x = cv.w - 84
    cv.text(name, x, 34, 24, color, alpha, FONT, vertical=True)
    seal(cv, x + 2, 40 + len(name) * 25.5)


# ---------- 洞穴 ----------

def cave_frame(cv, color=(40, 38, 34), opening=None):
    """畫面四周的岩壁與鐘乳石，中間留出洞內空間。"""
    w = cv.w
    xs = np.arange(w)
    top = 90 + 50 * fbm1d(w, 70, cv.rng, 4) - 30 * np.sin(xs / w * math.pi)
    pts = [(x, top[x]) for x in range(0, w, 4)] + [(w - 1, top[-1]), (w + 10, -10), (-10, -10)]
    cv.wash(pts, color, 0.92, blur=3, tex=0.4, mode="over")
    cv.stroke([(x, top[x]) for x in range(30, w - 30, 8)], 3, INK, 0.7, dry=0.5)
    for _ in range(int(w / 45)):
        x = cv.rng.uniform(50, w - 50)
        L = cv.rng.uniform(20, 70)
        y0 = top[int(x)] - 4
        cv.wash([(x - 9, y0), (x + 9, y0), (x + 1, y0 + L), (x - 1, y0 + L)], color, 0.9, blur=1.2, mode="over")
        cv.stroke([(x - 8, y0), (x, y0 + L)], 1.5, INK, 0.5, dry=0.5)
    # 左右岩壁，往中間漸淡
    for side in (0, 1):
        ys = np.linspace(top[0 if side == 0 else -1], 600, 24)
        xs_edge = [(120 + 40 * math.sin(y / 50) + cv.rng.uniform(-12, 12)) for y in ys]
        if side:
            xs_edge = [w - x for x in xs_edge]
        outer = -20 if side == 0 else w + 20
        pts = list(zip(xs_edge, ys)) + [(outer, 600), (outer, ys[0])]
        cv.wash(pts, color, 0.85, blur=10, tex=0.5, mode="over")
        cv.stroke(list(zip(xs_edge, ys)), 3, INK, 0.5, dry=0.6)


def stele(cv, cx, gy, w, h, char, stone=(150, 150, 140), glow=None):
    """石碑，碑上刻一個大字（字訣）。"""
    pts = [(cx - w / 2, gy), (cx - w / 2, gy - h + w * 0.2), (cx, gy - h), (cx + w / 2, gy - h + w * 0.2), (cx + w / 2, gy)]
    cv.wash(pts, stone, 0.95, blur=0.8, tex=0.5, mode="over")
    cv.stroke(pts, 3, INK, 0.8, dry=0.4)
    cv.paint(cv.rect(cx - w * 0.7, gy - 16, cx + w * 0.7, gy, blur=0.6), mix(stone, INK, 0.3), 0.95)
    size = w * 0.7
    if glow:
        cv.paint(cv.ellipse(cx, gy - h * 0.5, w * 0.7, w * 0.7, blur=w * 0.25), glow, 0.6, "screen")
    cv.text(char, cx - size / 2, gy - h * 0.5 - size * 0.6, size, glow or INK, 0.9, FONT)


def cauldron(cv, cx, gy, s, color=(90, 80, 60)):
    cv.wash([(cx - s, gy - s * 1.2), (cx + s, gy - s * 1.2), (cx + s * 0.8, gy - s * 0.3), (cx - s * 0.8, gy - s * 0.3)], color, 0.95, blur=0.8, mode="over")
    for dx in (-0.6, 0, 0.6):
        cv.stroke([(cx + dx * s, gy - s * 0.35), (cx + dx * s * 1.1, gy)], s * 0.18, INK, 0.9, smooth=0)
    for dx in (-0.75, 0.75):
        cv.stroke([(cx + dx * s, gy - s * 1.2), (cx + dx * s, gy - s * 1.6), (cx + dx * s * 0.7, gy - s * 1.6)], s * 0.1, INK, 0.9)
    cv.stroke([(cx - s, gy - s * 1.2), (cx + s, gy - s * 1.2)], s * 0.12, INK, 0.9)
    # 香煙
    for k in range(3):
        x = cx + (k - 1) * s * 0.3
        pts = [(x + math.sin(i * 0.7 + k) * s * 0.25, gy - s * 1.3 - i * s * 0.35) for i in range(10)]
        cv.stroke(pts, s * 0.06, (120, 120, 120), 0.35, taper=(0.1, 0.9), dry=0.3)


def lantern_string(cv, x0, x1, y, n, sag=30):
    xs = np.linspace(x0, x1, 40)
    ys = y + sag * np.sin((xs - x0) / (x1 - x0) * math.pi)
    cv.stroke(list(zip(xs, ys)), 1.2, INK, 0.7, taper=(0.02, 0.02))
    for k in range(1, n + 1):
        lx = x0 + (x1 - x0) * k / (n + 1)
        ly = y + sag * math.sin(k / (n + 1) * math.pi) + 14
        cv.paint(cv.ellipse(lx, ly, 20, 20, blur=10), (255, 80, 50), 0.35, "screen")
        cv.paint(cv.ellipse(lx, ly, 7, 10, blur=0.6), (190, 34, 30), 0.95)


def bones(cv, x, gy, n=5):
    for _ in range(n):
        cx = x + cv.rng.uniform(-40, 40)
        a = cv.rng.uniform(-0.4, 0.4)
        L = cv.rng.uniform(16, 30)
        p0, p1 = (cx - math.cos(a) * L / 2, gy - 4 - math.sin(a) * L / 2), (cx + math.cos(a) * L / 2, gy - 4 + math.sin(a) * L / 2)
        cv.stroke([p0, p1], 3.5, (220, 210, 190), 0.95, taper=(0.02, 0.02), dry=0.1)
        for p in (p0, p1):
            cv.paint(cv.ellipse(p[0], p[1], 3.5, 3.5), (220, 210, 190), 0.95)
    sx = x + 20
    cv.paint(cv.ellipse(sx, gy - 10, 10, 9), (220, 210, 190), 0.95)
    for dx in (-4, 4):
        cv.paint(cv.ellipse(sx + dx, gy - 11, 2.5, 3), INK, 0.9)


def claw_marks(cv, x, y, s=1.0, color=(150, 30, 30)):
    for k in range(3):
        cv.stroke([(x + k * 9 * s, y), (x + k * 9 * s + 18 * s, y + 48 * s)], 3.5 * s, color, 0.7, taper=(0.2, 0.7), dry=0.4)


def ink_splash(cv, x, y, r, color=INK, alpha=0.85):
    cv.dab(x, y, r, color, alpha, squash=0.8)
    for _ in range(9):
        a = cv.rng.uniform(0, 2 * math.pi)
        d = r * cv.rng.uniform(1.1, 2.2)
        cv.dab(x + math.cos(a) * d, y + math.sin(a) * d, r * cv.rng.uniform(0.08, 0.22), color, alpha)


def glyph_ring(cv, cx, cy, r, chars, color, alpha=0.85, size=30, tilt=0.35):
    """字訣環：一圈字環繞，像法陣。"""
    n = len(chars)
    cv.paint(cv.ellipse(cx, cy, r * 1.1, r * 1.1 * tilt, blur=r * 0.2), color, 0.35, "screen")
    t = np.linspace(0, 2 * math.pi, 80)
    cv.stroke([(cx + r * math.cos(a), cy + r * tilt * math.sin(a)) for a in t], 2.2, color, alpha * 0.8, taper=(0.02, 0.02), dry=0.3)
    for i, ch in enumerate(chars):
        a = 2 * math.pi * i / n - math.pi / 2
        cv.text(ch, cx + r * math.cos(a) - size / 2, cy + r * tilt * math.sin(a) - size * 0.6, size * (0.8 + 0.3 * (math.sin(a) + 1) / 2), color, alpha, FONT)
