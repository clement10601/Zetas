"""每個地圖區塊的背景構圖。寬度照 content/chunks.json，高 600，地面線在最底下。"""
import math

import numpy as np
from PIL import Image

from . import scenery as S
from .ink import INK, Canvas, chaikin, mix, seed_of

RED = (178, 30, 36)
BLOOD = (150, 16, 24)


def base(cid, w, theme, far_peaks=None, mid_peaks=None, far_amp=90, mid_amp=70, mist_y=470):
    cv = Canvas(w, 600, seed_of(cid))
    S.sky(cv, theme, S.ILLUSION_EDGE if theme == "illusion" else S.EDGE_SKY)
    t = S.THEMES[theme]
    far = S.ridge(cv, S.EDGE_FAR, far_amp, 160, S.EDGE_FAR, far_peaks)
    S.mountains(cv, far, t["far"], 0.45, mist=160)
    S.mist(cv, 400, 50, (230, 228, 216) if theme != "illusion" else (120, 30, 34), 0.45)
    mid = S.ridge(cv, S.EDGE_MID, mid_amp, 120, S.EDGE_MID, mid_peaks)
    S.mountains(cv, mid, t["mid"], 0.55, mist=120, ink_edge=2.2, cuns=int(w / 40))
    S.mist(cv, mist_y, 40, (236, 232, 220) if theme != "illusion" else (110, 24, 28), 0.5)
    return cv


def finish(cv, name, theme, dark=False):
    S.ground_strip(cv, theme)
    light = dark or theme == "illusion"
    S.inscription(cv, name, (214, 196, 176) if light else INK, 0.6 if light else 0.5)
    return blend_edges(cv.image(), "illusion" if theme == "illusion" else "world")


_PROFILES = {}


def edge_profile(family):
    """區塊兩端要收斂到的「標準邊」：平的遠山、中山、霧、地面，每一列一個顏色。"""
    if family not in _PROFILES:
        cv = Canvas(64, 600, seed_of("edge." + family))
        if family == "illusion":
            S.sky(cv, "illusion", S.ILLUSION_EDGE)
            colors = [S.THEMES["illusion"]["far"], S.THEMES["illusion"]["mid"]]
            mist_c = (110, 24, 28)
        else:
            S.sky(cv, "forest", S.EDGE_SKY)
            colors = [tuple(np.mean([S.THEMES[t][k] for t in ("forest", "sect", "mountain")], 0)) for k in ("far", "mid")]
            mist_c = (236, 232, 220)
        S.mountains(cv, np.full(64, float(S.EDGE_FAR)), colors[0], 0.45, mist=160)
        S.mist(cv, 400, 50, mist_c, 0.45)
        S.mountains(cv, np.full(64, float(S.EDGE_MID)), colors[1], 0.55, mist=120)
        S.mist(cv, 470, 40, mist_c, 0.5)
        S.ground_strip(cv, "illusion" if family == "illusion" else "forest", with_grass=False)
        _PROFILES[family] = np.asarray(cv.image(), np.float32)[:, 16:48].mean(1)
    return _PROFILES[family]


def blend_edges(img, family, fade=56):
    """左右各 fade 像素往標準邊漸變，任兩個區塊接在一起都不會有明顯接縫。"""
    a = np.asarray(img, np.float32).copy()
    prof = edge_profile(family)
    w = a.shape[1]
    d = np.minimum(np.arange(w), w - 1 - np.arange(w))
    k = (1 - S.smoothstep(0, fade, d))[None, :, None]
    a = a * (1 - k) + prof[:, None, :] * k
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


# ---------- 青雲山腳（forest） ----------

def qingyun_road(cid, w, name):
    cv = base(cid, w, "forest", far_peaks=[(w * 0.7, 120, 90)])
    S.pagoda(cv, w * 0.72, 300, 110, (90, 100, 104), 0.45)
    for x, h in [(120, 260), (260, 200), (820, 280)]:
        S.pine(cv, x, 600, h, lean=cv.rng.uniform(-0.5, 0.5))
    S.leafy_tree(cv, 470, 600, 170, INK, (60, 84, 64))
    S.rock(cv, 380, 600, 90, 50, (120, 130, 120))
    S.rock(cv, 700, 600, 60, 34, (120, 130, 120))
    return finish(cv, name, "forest")


def qingyun_woods(cid, w, name):
    cv = base(cid, w, "forest", mid_amp=40, mist_y=440)
    t = S.THEMES["forest"]
    for x in np.linspace(80, w - 80, 9):
        S.pine(cv, x + cv.rng.uniform(-30, 30), 560, cv.rng.uniform(220, 300), color=mix(t["mid"], (230, 228, 216), 0.35), alpha=0.5)
    S.mist(cv, 520, 40, (236, 232, 220), 0.6)
    for x in [90, 330, 560, 880]:
        S.pine(cv, x, 600, cv.rng.uniform(300, 380), lean=cv.rng.uniform(-0.4, 0.4))
    S.bamboo(cv, 450, 600, 330, (50, 70, 52), 0.8, lean=0.02)
    S.bamboo(cv, 475, 600, 300, (50, 70, 52), 0.7, lean=-0.03)
    S.bamboo(cv, 760, 600, 320, (50, 70, 52), 0.75, lean=0.01)
    return finish(cv, name, "forest")


def forest_clearing_a(cid, w, name):
    cv = base(cid, w, "forest", far_peaks=[(w * 0.35, 90, 120)], mid_amp=40)
    S.moon(cv, w * 0.55, 120, 34, (246, 240, 222), 0.8, halo=(255, 250, 230))
    for x in [100, 220, 900, 1000]:
        S.leafy_tree(cv, x, 600, cv.rng.uniform(180, 240), INK, (58, 86, 66))
    S.rock(cv, 560, 600, 140, 60, (130, 136, 124))
    S.grass(cv, 420, 700, 600, 0.5, INK, 0.6, 30)
    # 林中一道光
    cv.paint(cv.vgrad(cv.poly([(480, 0), (620, 0), (700, 600), (420, 600)], blur=30), 0, 600, 0.35, 0.0), (255, 248, 220), 0.6, "screen")
    return finish(cv, name, "forest")


def mountain_cave(cid, w, name):
    cv = Canvas(w, 600, seed_of(cid))
    S.sky(cv, "mountain")
    cv.paint(cv.full(np.ones((cv.H, cv.W), np.float32)), (70, 66, 58), 0.85, "multiply")
    # 洞內深處一點天光
    cv.paint(cv.ellipse(w * 0.62, 330, 120, 160, blur=60), (230, 220, 190), 0.45, "screen")
    S.cave_frame(cv, (44, 42, 38))
    S.rock(cv, 200, 600, 160, 90, (70, 68, 60))
    S.rock(cv, 760, 600, 120, 70, (70, 68, 60))
    for x in (380, 520):
        cv.stroke([(x, 600), (x + 8, 560)], 3, (90, 110, 80), 0.6)
    S.mist(cv, 560, 30, (120, 116, 104), 0.4)
    return finish(cv, name, "mountain", dark=True)


def ruined_shrine(cid, w, name):
    cv = base(cid, w, "forest", mid_amp=50)
    S.moon(cv, w * 0.3, 110, 28, (240, 232, 210), 0.7)
    S.dead_tree(cv, 140, 600, 280)
    # 傾頹的廟
    S.hall(cv, 560, 600, 300, 260, wall=(170, 160, 140), pillar=(110, 70, 50), roof_c=(60, 58, 52), text="山神")
    cv.paint(cv.textured(cv.poly([(620, 370), (700, 350), (715, 395), (640, 410)], blur=2), 0.6), (200, 196, 180), 0.8)
    cv.stroke([(620, 370), (660, 400), (700, 352)], 2, INK, 0.7, dry=0.6)
    S.rock(cv, 360, 600, 70, 30, (120, 120, 110))
    S.leafy_tree(cv, 860, 600, 200, INK, (70, 80, 64))
    for x in range(420, 720, 30):
        S.grass(cv, x, x + 20, 600, 0.6, INK, 0.7, 34)
    return finish(cv, name, "forest")


def mountain_village(cid, w, name):
    cv = base(cid, w, "forest", far_peaks=[(w * 0.8, 100, 140)], mid_amp=50)
    for cx, hw in [(240, 190), (520, 160), (850, 200)]:
        S.house(cv, cx, 600, hw, hw * 0.9, lantern=cx == 520)
    S.leafy_tree(cv, 380, 600, 220, INK, (66, 90, 60))
    S.leafy_tree(cv, 1000, 600, 180, INK, (66, 90, 60))
    # 籬笆
    for x in range(640, 740, 14):
        cv.stroke([(x, 600), (x + 1, 570)], 3, (90, 70, 50), 0.9, smooth=0)
    cv.stroke([(636, 582), (744, 580)], 2.5, (90, 70, 50), 0.9)
    # 炊煙
    pts = [(560 + math.sin(i * 0.6) * 12 + i * 4, 440 - i * 16) for i in range(12)]
    cv.stroke(pts, 9, (200, 200, 196), 0.35, taper=(0.1, 0.9), dry=0.5)
    return finish(cv, name, "forest")


# ---------- 青雲宗（sect） ----------

def sect_gate(cid, w, name):
    cv = base(cid, w, "sect", far_peaks=[(w * 0.6, 160, 110), (w * 0.25, 100, 80)], mid_amp=60)
    S.cloud_scroll(cv, w * 0.3, 150, 1.6, (250, 250, 246), 0.6)
    S.cloud_scroll(cv, w * 0.75, 110, 1.2, (250, 250, 246), 0.5)
    S.hall(cv, w * 0.8, 400, 150, 130, roof_c=(70, 84, 96), alpha=0.55, tiers=2)
    # 石階往上
    for k in range(10):
        y = 600 - k * 14
        cv.paint(cv.rect(560 - 90 + k * 6, y - 14, 560 + 90 - k * 6, y, blur=0.5), (170, 168, 160), 0.85)
        cv.stroke([(560 - 90 + k * 6, y - 14), (560 + 90 - k * 6, y - 14)], 1.5, INK, 0.5, smooth=0)
    S.paifang(cv, 560, 600, 300, 340, "青雲")
    S.pine(cv, 330, 600, 280, lean=-0.4)
    S.pine(cv, 800, 600, 250, lean=0.4)
    return finish(cv, name, "sect")


def sect_plaza(cid, w, name):
    cv = base(cid, w, "sect", far_peaks=[(w * 0.5, 120, 160)], mid_amp=40)
    S.cloud_scroll(cv, w * 0.2, 130, 1.3, (250, 250, 246), 0.55)
    cv.paint(cv.textured(cv.rect(w * 0.5 - 230, 468, w * 0.5 + 230, 502, blur=0.6), 0.4, "cloud"), (160, 158, 150), 0.95)
    cv.stroke([(w * 0.5 - 230, 468), (w * 0.5 + 230, 468)], 2, INK, 0.6, smooth=0)
    S.hall(cv, w * 0.5, 470, 360, 230, roof_c=(60, 74, 88), text="演武", tiers=2)
    # 石板地的透視線
    for k in range(-8, 9):
        cv.stroke([(w * 0.5 + k * 30, 500), (w * 0.5 + k * 90, 600)], 1, INK, 0.18, smooth=0, taper=(0.02, 0.02))
    for y in (520, 548, 580):
        cv.stroke([(60, y), (w - 60, y)], 1, INK, 0.15, smooth=0)
    S.cauldron(cv, w * 0.5, 590, 34)
    S.stele(cv, 190, 600, 70, 200, "道", glow=None)
    # 木人樁
    for x in (850, 950):
        cv.stroke([(x, 600), (x, 470)], 12, (110, 80, 54), 0.95, taper=(0.02, 0.05), smooth=0)
        for y in (500, 530):
            cv.stroke([(x - 26, y), (x + 26, y + 4)], 6, (110, 80, 54), 0.95, smooth=0)
        cv.stroke([(x - 6, 600), (x - 6, 470)], 2, INK, 0.6, smooth=0)
    S.pine(cv, 330, 600, 230, lean=-0.3)
    return finish(cv, name, "sect")


def sect_hall(cid, w, name):
    cv = base(cid, w, "sect", mid_amp=30)
    S.hall(cv, w * 0.55, 600, 560, 440, roof_c=(56, 68, 80), text="傳功殿")
    S.pine(cv, 110, 600, 300, lean=-0.3)
    S.cauldron(cv, w * 0.55, 600, 28)
    return finish(cv, name, "sect")


def master_cave(cid, w, name):
    cv = Canvas(w, 600, seed_of(cid))
    S.sky(cv, "sect")
    cv.paint(cv.full(np.ones((cv.H, cv.W), np.float32)), (90, 100, 104), 0.8, "multiply")
    # 洞口望出去的雲海
    ox, oy = w * 0.68, 330
    hole = [(ox + 120 * math.cos(a) * (0.85 + 0.25 * cv.rng.random()), oy + 170 * math.sin(a) * (0.85 + 0.2 * cv.rng.random())) for a in np.linspace(0, 2 * math.pi, 18, endpoint=False)]
    cv.paint(cv.poly(hole, blur=2), (226, 232, 234), 1.0)
    for k, (yy, c) in enumerate([(330, (150, 164, 176)), (380, (110, 124, 136))]):
        xs = np.linspace(ox - 140, ox + 140, 30)
        ridge_pts = [(x, yy - 50 * math.exp(-((x - ox - 30 + k * 60) / 50) ** 2) - 8 * cv.rng.random()) for x in xs]
        m = cv.clip(cv.poly(ridge_pts + [(ox + 140, 520), (ox - 140, 520)], blur=1), cv.poly(hole, blur=2))
        cv.paint(cv.vgrad(m, yy - 40, yy + 120, 1.0, 0.1), c, 0.6, "multiply")
    cv.stroke(chaikin(hole + hole[:1], 2), 6, INK, 0.8, dry=0.5)
    S.cave_frame(cv, (52, 58, 60))
    # 掛軸：靜
    cv.paint(cv.rect(180, 170, 260, 400, blur=0.5), (226, 218, 196), 0.95)
    cv.stroke([(170, 168), (270, 168)], 5, (90, 60, 40), 0.95, smooth=0)
    cv.stroke([(176, 402), (264, 402)], 6, (90, 60, 40), 0.95, smooth=0)
    cv.text("靜", 186, 220, 68, INK, 0.9, S.FONT)
    S.seal(cv, 238, 350, 14)
    # 蒲團與燈
    cv.paint(cv.ellipse(420, 594, 60, 12, blur=1), (120, 96, 60), 0.95)
    cv.paint(cv.ellipse(420, 586, 54, 14, blur=1), (150, 120, 76), 0.95)
    cv.paint(cv.ellipse(320, 520, 50, 50, blur=22), (255, 210, 120), 0.5, "screen")
    cv.stroke([(320, 600), (320, 540)], 4, INK, 0.9, smooth=0)
    cv.paint(cv.ellipse(320, 530, 4, 9, blur=1.5), (255, 200, 90), 0.95)
    return finish(cv, name, "sect", dark=True)


# ---------- 黑風嶺（mountain） ----------

def wind(cv, n, color=(250, 246, 236), alpha=0.35):
    for _ in range(n):
        x = cv.rng.uniform(60, cv.w - 260)
        y = cv.rng.uniform(80, 480)
        L = cv.rng.uniform(120, 260)
        pts = [(x + L * t, y + math.sin(t * 5) * 8 - t * 20) for t in np.linspace(0, 1, 12)]
        cv.stroke(pts, 2.5, color, alpha, taper=(0.3, 0.6), dry=0.5)


def heifeng_pass(cid, w, name):
    cv = base(cid, w, "mountain", far_peaks=[(w * 0.4, 150, 80), (w * 0.75, 110, 70)], mid_amp=110)
    wind(cv, 8)
    for x in (180, 620):
        S.dead_tree(cv, x, 600, cv.rng.uniform(200, 260), INK)
    S.rock(cv, 400, 600, 180, 110, (90, 84, 76))
    S.rock(cv, 860, 600, 120, 80, (90, 84, 76))
    S.stele(cv, 760, 600, 40, 110, "險", stone=(120, 116, 106))
    return finish(cv, name, "mountain")


def heifeng_ravine(cid, w, name):
    cv = base(cid, w, "mountain", far_amp=60, mid_amp=40, mist_y=420)
    t = S.THEMES["mountain"]
    # 兩側斷崖
    for side in (0, 1):
        x0 = 60 if side == 0 else w - 60
        sgn = 1 if side == 0 else -1
        ys = np.linspace(-10, 600, 34)
        edge = [(x0 + sgn * (240 + 50 * math.sin(y / 40) + cv.rng.uniform(-10, 10)), y) for y in ys]
        outer = [(x0 - sgn * 200, 600), (x0 - sgn * 200, -10)]
        cv.wash(edge + outer, mix(t["mid"], INK, 0.2), 0.9, blur=2, tex=0.5, mode="over")
        cv.stroke(edge, 4, INK, 0.85, dry=0.5)
        for _ in range(16):
            y = cv.rng.uniform(100, 560)
            x = x0 + sgn * cv.rng.uniform(40, 220)
            cv.stroke([(x, y), (x - sgn * 10, y + 20), (x - sgn * 14, y + 40)], 2, INK, 0.45, dry=0.6)
    # 谷底雲霧與吊橋殘索
    S.mist(cv, 560, 60, (220, 214, 200), 0.75)
    xs = np.linspace(300, w - 300, 30)
    cv.stroke([(x, 250 + 60 * math.sin((x - 300) / (w - 600) * math.pi)) for x in xs[:18]], 2, (80, 60, 40), 0.85)
    cv.stroke([(w - 300, 250), (w - 340, 300), (w - 350, 360)], 2, (80, 60, 40), 0.8)
    for x in xs[:18:2]:
        y = 250 + 60 * math.sin((x - 300) / (w - 600) * math.pi)
        cv.stroke([(x - 8, y + 4), (x + 8, y + 4)], 4, (100, 76, 50), 0.9, smooth=0)
    S.dead_tree(cv, 200, 300, 120)
    return finish(cv, name, "mountain")


def demon_den(cid, w, name):
    cv = Canvas(w, 600, seed_of(cid))
    S.sky(cv, "mountain")
    cv.paint(cv.full(np.ones((cv.H, cv.W), np.float32)), (70, 40, 34), 0.85, "multiply")
    cv.paint(cv.ellipse(w * 0.5, 420, 260, 140, blur=70), (200, 60, 40), 0.4, "screen")
    S.cave_frame(cv, (40, 26, 22))
    for x in (260, 520, 700):
        S.bones(cv, x, 600, 4)
    S.claw_marks(cv, 180, 260, 1.4)
    S.claw_marks(cv, 760, 300, 1.1)
    # 深處的眼睛
    for ex, ey in [(430, 330), (600, 300), (520, 370)]:
        for dx in (0, 16):
            cv.paint(cv.ellipse(ex + dx, ey, 5, 3, blur=2.5), (255, 70, 40), 0.9, "screen")
    return finish(cv, name, "mountain", dark=True)


# ---------- 心魔幻境（illusion） ----------

def illusion_base(cid, w):
    cv = Canvas(w, 600, seed_of(cid))
    S.sky(cv, "illusion", S.ILLUSION_EDGE)
    t = S.THEMES["illusion"]
    far = S.ridge(cv, S.EDGE_FAR, 120, 90, S.EDGE_FAR)
    S.mountains(cv, far, t["far"], 0.7, mist=200, cuns=0)
    return cv


def tilted_ridge(cv, y0, slope, amp, color, alpha):
    w = cv.w
    xs = np.arange(w)
    y = y0 + slope * (xs - w / 2) - amp * cv.rng.random() * 0 - amp * S.fbm1d(w, 70, cv.rng, 5)
    ew = S.edge_weight(w)
    y = y * ew + S.EDGE_MID * (1 - ew)
    S.mountains(cv, y, color, alpha, mist=160, ink_edge=3)


def shards(cv, n):
    """幻境裡飄浮的碎片：尖角三角形，一邊描紅。"""
    for _ in range(n):
        x, y = cv.rng.uniform(80, cv.w - 80), cv.rng.uniform(80, 380)
        s = cv.rng.uniform(5, 12)
        a = cv.rng.uniform(0, 2 * math.pi)
        pts = [(x + s * math.cos(a + k * 2.2) * (1.6 if k == 0 else 1), y + s * math.sin(a + k * 2.2) * (1.6 if k == 0 else 1)) for k in range(3)]
        cv.paint(cv.poly(pts, 0.5), (20, 6, 8), 0.85)
        cv.stroke(pts[:2], 1.5, (230, 70, 60), 0.7, taper=(0.1, 0.1))


def illusion_entry(cid, w, name):
    cv = illusion_base(cid, w)
    S.moon(cv, w * 0.5, 170, 60, (210, 40, 40), 0.9, halo=(255, 60, 50))
    tilted_ridge(cv, 430, 0.12, 80, (20, 6, 8), 0.85)
    S.glyph_ring(cv, w * 0.5, 400, 150, "心魔劫幻妄執貪嗔", (240, 80, 70), 0.85, size=30)
    shards(cv, 10)
    return finish(cv, name, "illusion")


def illusion_qingyun_town(cid, w, name):
    cv = illusion_base(cid, w)
    S.moon(cv, w * 0.8, 120, 46, (210, 40, 40), 0.9, halo=(255, 60, 50))
    tilted_ridge(cv, 440, -0.08, 60, (30, 8, 10), 0.8)
    # 歪斜錯位的鎮子：紙色退成灰紅
    for i, (cx, hw, sk) in enumerate([(160, 170, 0.12), (380, 200, -0.08), (620, 180, 0.15), (850, 190, -0.12)]):
        S.house(cv, cx, 600 - (i % 2) * 6, hw, hw * 0.95, thatch=(60, 30, 30), wall=(120, 70, 70), lantern=True, skew=sk)
    S.lantern_string(cv, 220, 780, 300, 6)
    shards(cv, 12)
    return finish(cv, name, "illusion")


def illusion_arena(cid, w, name):
    cv = illusion_base(cid, w)
    S.moon(cv, w * 0.5, 210, 110, (190, 24, 30), 0.95, halo=(255, 60, 50))
    # 血月台：圓形石台
    cv.paint(cv.ellipse(w * 0.5, 560, 330, 50, blur=2), (40, 10, 12), 0.95)
    cv.paint(cv.ellipse(w * 0.5, 548, 320, 44, blur=2), (80, 24, 26), 0.95)
    cv.stroke([(w * 0.5 + 320 * math.cos(a), 548 + 44 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 90)], 3, INK, 0.85, taper=(0.01, 0.01))
    for x in (130, w - 130):
        cv.stroke([(x, 600), (x, 300)], 14, (24, 8, 10), 0.95, taper=(0.02, 0.1), smooth=0)
        cv.paint(cv.ellipse(x, 290, 22, 26, blur=12), (255, 70, 40), 0.6, "screen")
    S.glyph_ring(cv, w * 0.5, 540, 250, "心魔血月劫念", (230, 60, 50), 0.45, size=28, tilt=0.14)
    shards(cv, 8)
    return finish(cv, name, "illusion")


CHUNKS = {
    "chunk.qingyun_road": qingyun_road,
    "chunk.qingyun_woods": qingyun_woods,
    "chunk.forest_clearing_a": forest_clearing_a,
    "chunk.mountain_cave": mountain_cave,
    "chunk.ruined_shrine": ruined_shrine,
    "chunk.mountain_village": mountain_village,
    "chunk.sect_gate": sect_gate,
    "chunk.sect_plaza": sect_plaza,
    "chunk.sect_hall": sect_hall,
    "chunk.master_cave": master_cave,
    "chunk.heifeng_pass": heifeng_pass,
    "chunk.heifeng_ravine": heifeng_ravine,
    "chunk.demon_den": demon_den,
    "chunk.illusion_entry": illusion_entry,
    "chunk.illusion_qingyun_town": illusion_qingyun_town,
    "chunk.illusion_arena": illusion_arena,
}
