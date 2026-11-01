"""每個地圖區塊的背景構圖。寬度照 content/chunks.json，高 600，地面線在最底下。"""
import math

import numpy as np
from PIL import Image

from . import layers as L
from . import paintings as P
from . import scenery as S
from .ink import INK, Canvas, chaikin, mix, seed_of

RED = (178, 30, 36)
BLOOD = (150, 16, 24)


# 戶外區塊（2026-11-01 起）：背景是多張獨立圖層（layers.py），區塊圖只畫這一塊自己的東西——
# 建築、石碑、樹與坡腳，其餘透明；顏色用 layers.PALETTES 同一套，和丘陵、近景山石對得上。
REGION = {
    "chunk.qingyun_road": "forest", "chunk.qingyun_woods": "forest", "chunk.forest_clearing_a": "forest",
    "chunk.mountain_village": "village", "chunk.ruined_shrine": "village",
    "chunk.sect_gate": "sect", "chunk.sect_plaza": "sect", "chunk.sect_hall": "sect",
    "chunk.heifeng_pass": "mountain", "chunk.heifeng_ravine": "mountain",
}


def bank(cv, region):
    """區塊底部的坡腳：一道起伏的土坡（受光的上緣、墨線、皴點），兩頭種幾棵樹、散幾塊石頭。"""
    p = L.PALETTES[region]
    w, rng = cv.w, cv.rng
    xs = np.linspace(-10, w + 10, max(12, int(w / 30)))
    ph = [rng.uniform(0, 6.3) for _ in range(3)]
    top = [(x, 488 - 22 * math.sin(x / 170 + ph[0]) - 12 * math.sin(x / 61 + ph[1]) - 6 * math.sin(x / 23 + ph[2])) for x in xs]
    m = cv.poly(top + [(w + 10, 605), (-10, 605)], blur=1.5)
    cv.paint(m, p["rock"], 1.0)        # 坡體不透明，後面的圖層不會透過來
    cv.paint(cv.textured(cv.vgrad(m, 450, 560, 1.0, 0.0), 0.5, "cloud"), p["lit"], 0.7)
    cv.paint(cv.textured(cv.vgrad(m, 520, 600, 0.0, 1.0), 0.5, "cloud"), p["pine"], 0.35)
    cv.stroke(top, 2.6, p["pine"], 0.9, dry=0.45, taper=(0.02, 0.02))
    for _ in range(int(w / 18)):
        x = rng.uniform(10, w - 10)
        y = np.interp(x, xs, [t[1] for t in top]) + rng.uniform(4, 60)
        cv.dab(x, y, rng.uniform(1.4, 3.0), p["pine"], rng.uniform(0.4, 0.8), squash=0.5)
    for _ in range(int(w / 70)):
        x = rng.uniform(20, w - 20)
        y = np.interp(x, xs, [t[1] for t in top]) + rng.uniform(8, 40)
        cv.stroke([(x, y), (x - 6, y + 14), (x - 9, y + 28)], 1.6, p["pine"], 0.5, dry=0.6)
    for x0, x1 in ((40, w * 0.18), (w * 0.82, w - 40)):
        for _ in range(rng.integers(1, 3)):
            x = rng.uniform(x0, x1)
            gy = np.interp(x, xs, [t[1] for t in top]) + 10
            if region in ("sect", "mountain") or rng.random() < 0.5:
                S.pine(cv, x, gy, rng.uniform(150, 230), lean=rng.uniform(-0.6, 0.6), color=p["pine"], alpha=0.95)
            else:
                S.leafy_tree(cv, x, gy, rng.uniform(150, 220), color=p["pine"], leaf=p["rock"], alpha=0.95)
    for _ in range(rng.integers(2, 5)):
        x = rng.uniform(30, w - 30)
        S.rock(cv, x, 600, rng.uniform(40, 90), rng.uniform(24, 46), p["rock"], 0.9)


def _mist(cv, *args, **kw):
    """區塊裡的橫向霧帶；戶外區塊（只畫坡腳與建築、上面透明）不畫，霧交給遊戲的山嵐層，免得在區塊兩端切出直邊"""
    if not getattr(cv, "layered", False):
        S.mist(cv, *args, **kw)


def base(cid, w, theme):
    """戶外區塊：透明底＋程式畫的坡腳（bank）。沒有分層的區塊（幻境）才用古畫（paintings.py）或程式畫的天與山。"""
    cv = Canvas(w, 600, seed_of(cid))
    if cid in REGION:
        cv.layered = True
        bank(cv, REGION[cid])
        return cv
    img = P.crop(cid, w)
    if img is not None:
        arr = np.asarray(P.grade(img, theme).resize((cv.W, cv.H), Image.BICUBIC), np.float32) / 255
        cv.prgb[:] = arr
        cv.a[:] = 1
        return cv
    S.sky(cv, theme, S.ILLUSION_EDGE if theme == "illusion" else S.EDGE_SKY)
    t = S.THEMES[theme]
    S.mountains(cv, S.ridge(cv, S.EDGE_FAR, 90, 160, S.EDGE_FAR), t["far"], 0.45, mist=160)
    _mist(cv, 400, 50, (230, 228, 216) if theme != "illusion" else (120, 30, 34), 0.45)
    S.mountains(cv, S.ridge(cv, S.EDGE_MID, 70, 120, S.EDGE_MID), t["mid"], 0.55, mist=120, ink_edge=2.2, cuns=int(w / 40))
    _mist(cv, 470, 40, (236, 232, 220) if theme != "illusion" else (110, 24, 28), 0.5)
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
            # 古畫都畫在紙絹上：兩端收斂到紙色，接縫看起來像卷軸接紙
            cv.prgb[:] = np.array(S.EDGE_SKY, np.float32) / 255
            cv.a[:] = 1
            S.ground_strip(cv, "forest", with_grass=False)
            _PROFILES[family] = np.asarray(cv.image(), np.float32)[:, 16:48].mean(1)
            return _PROFILES[family]
        S.mountains(cv, np.full(64, float(S.EDGE_FAR)), colors[0], 0.45, mist=160)
        _mist(cv, 400, 50, mist_c, 0.45)
        S.mountains(cv, np.full(64, float(S.EDGE_MID)), colors[1], 0.55, mist=120)
        _mist(cv, 470, 40, mist_c, 0.5)
        S.ground_strip(cv, "illusion" if family == "illusion" else "forest", with_grass=False)
        _PROFILES[family] = np.asarray(cv.image(), np.float32)[:, 16:48].mean(1)
    return _PROFILES[family]


def blend_edges(img, family, fade=0):
    """左右各 fade 像素往標準邊漸變。
    2026-10-31 起預設不漸變（fade=0）：統一的紙色標準邊在暗區塊（洞窟、宗門）旁邊會變成一條白帶，
    接縫改由遊戲在兩個區塊之間做鏡像交疊（main.gd 的 _blend_seam），這裡保留原圖邊緣。"""
    if fade <= 0:
        return img
    a = np.asarray(img, np.float32).copy()
    prof = edge_profile(family)
    w = a.shape[1]
    d = np.minimum(np.arange(w), w - 1 - np.arange(w))
    k = (1 - S.smoothstep(0, fade, d))[None, :, None]
    a = a * (1 - k) + prof[:, None, :] * k
    return Image.fromarray(a.round().astype(np.uint8), "RGBA")


# ---------- 青雲山腳（forest） ----------

def qingyun_road(cid, w, name):
    cv = base(cid, w, "forest")
    return finish(cv, name, "forest")


def qingyun_woods(cid, w, name):
    cv = base(cid, w, "forest")
    _mist(cv, 540, 40, (236, 232, 220), 0.45)
    return finish(cv, name, "forest")


def forest_clearing_a(cid, w, name):
    cv = base(cid, w, "forest")
    S.moon(cv, w * 0.5, 70, 26, (246, 240, 222), 0.75, halo=(255, 250, 230))
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
    _mist(cv, 560, 30, (120, 116, 104), 0.4)
    return finish(cv, name, "mountain", dark=True)


def ruined_shrine(cid, w, name):
    cv = base(cid, w, "forest")
    _mist(cv, 560, 50, (236, 232, 220), 0.55)
    S.dead_tree(cv, 140, 600, 260)
    # 山神廟是場景物件（landmarks.py）
    for x in range(430, 700, 30):
        S.grass(cv, x, x + 20, 600, 0.6, INK, 0.7, 34)
    return finish(cv, name, "forest")


def mountain_village(cid, w, name):
    cv = base(cid, w, "forest")
    _mist(cv, 560, 50, (236, 232, 220), 0.55)
    # 三間村屋是場景物件（landmarks.py）
    for x in range(640, 740, 14):
        cv.stroke([(x, 600), (x + 1, 570)], 3, (90, 70, 50), 0.9, smooth=0)
    cv.stroke([(636, 582), (744, 580)], 2.5, (90, 70, 50), 0.9)
    pts = [(560 + math.sin(i * 0.6) * 12 + i * 4, 450 - i * 16) for i in range(12)]
    cv.stroke(pts, 9, (200, 200, 196), 0.35, taper=(0.1, 0.9), dry=0.5)
    return finish(cv, name, "forest")


def sect_gate(cid, w, name):
    # 山門牌坊與石階是場景物件（landmarks.py），人能從柱間穿過；這裡只畫坡腳
    cv = base(cid, w, "sect")
    return finish(cv, name, "sect")


def sect_plaza(cid, w, name):
    cv = base(cid, w, "sect")
    # 石板地：從畫的下緣鋪出一片演武場
    m = cv.vgrad(cv.rect(-5, 480, w + 5, 605, blur=8), 480, 520, 0.0, 1.0)
    cv.paint(cv.textured(m, 0.4, "cloud"), (176, 172, 160), 0.92)
    for k in range(-9, 10):
        cv.stroke([(w * 0.5 + k * 34, 505), (w * 0.5 + k * 90, 600)], 1, INK, 0.2, smooth=0, taper=(0.02, 0.02))
    for y in (528, 556, 586):
        cv.stroke([(60, y), (w - 60, y)], 1, INK, 0.16, smooth=0)
    S.cauldron(cv, w * 0.5, 590, 34)
    S.stele(cv, 190, 600, 70, 200, "道")
    for x in (850, 950):
        cv.stroke([(x, 600), (x, 470)], 12, (110, 80, 54), 0.95, taper=(0.02, 0.05), smooth=0)
        for y in (500, 530):
            cv.stroke([(x - 26, y), (x + 26, y + 4)], 6, (110, 80, 54), 0.95, smooth=0)
        cv.stroke([(x - 6, 600), (x - 6, 470)], 2, INK, 0.6, smooth=0)
    return finish(cv, name, "sect")


def sect_hall(cid, w, name):
    cv = base(cid, w, "sect")
    _mist(cv, 590, 60, (234, 230, 214), 0.6)
    # 傳功殿是場景物件（landmarks.py）；殿前香爐留在底圖
    S.cauldron(cv, w * 0.5, 600, 28)
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
    cv = base(cid, w, "mountain")
    wind(cv, 9)
    S.stele(cv, 760, 600, 40, 110, "險", stone=(120, 116, 106))
    return finish(cv, name, "mountain")


def heifeng_ravine(cid, w, name):
    cv = base(cid, w, "mountain")
    t = S.THEMES["mountain"]
    # 兩側斷崖把畫框成一道谷
    for side in (0, 1):
        x0 = 60 if side == 0 else w - 60
        sgn = 1 if side == 0 else -1
        ys = np.linspace(-10, 600, 34)
        edge = [(x0 + sgn * (190 + 40 * math.sin(y / 40) + cv.rng.uniform(-10, 10)), y) for y in ys]
        outer = [(x0 - sgn * 200, 600), (x0 - sgn * 200, -10)]
        cv.wash(edge + outer, L.PALETTES["mountain"]["rock"], 0.95, blur=2, tex=0.5, mode="over")
        cv.stroke(edge, 4, INK, 0.85, dry=0.5)
        for _ in range(16):
            y = cv.rng.uniform(100, 560)
            x = x0 + sgn * cv.rng.uniform(40, 180)
            cv.stroke([(x, y), (x - sgn * 10, y + 20), (x - sgn * 14, y + 40)], 2, INK, 0.45, dry=0.6)
    _mist(cv, 560, 60, (220, 214, 200), 0.7)
    xs = np.linspace(250, w - 250, 30)
    bridge = [(x, 250 + 60 * math.sin((x - 250) / (w - 500) * math.pi)) for x in xs[:18]]
    cv.stroke(bridge, 2, (80, 60, 40), 0.85)
    cv.stroke([(w - 250, 250), (w - 290, 300), (w - 300, 360)], 2, (80, 60, 40), 0.8)
    for x, y in bridge[::2]:
        cv.stroke([(x - 8, y + 4), (x + 8, y + 4)], 4, (100, 76, 50), 0.9, smooth=0)
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
    cv = base(cid, w, "illusion")
    S.moon(cv, w * 0.5, 170, 60, (210, 40, 40), 0.9, halo=(255, 60, 50))
    S.glyph_ring(cv, w * 0.5, 420, 150, "心魔劫幻妄執貪嗔", (240, 80, 70), 0.85, size=30)
    shards(cv, 10)
    return finish(cv, name, "illusion")


def illusion_qingyun_town(cid, w, name):
    cv = base(cid, w, "illusion")
    S.moon(cv, w * 0.8, 120, 46, (210, 40, 40), 0.9, halo=(255, 60, 50))
    for i, (cx, hw, sk) in enumerate([(160, 170, 0.12), (380, 200, -0.08), (620, 180, 0.15), (850, 190, -0.12)]):
        S.house(cv, cx, 600 - (i % 2) * 6, hw, hw * 0.95, thatch=(60, 30, 30), wall=(120, 70, 70), lantern=True, skew=sk)
    S.lantern_string(cv, 220, 780, 300, 6)
    shards(cv, 12)
    return finish(cv, name, "illusion")


def illusion_arena(cid, w, name):
    cv = base(cid, w, "illusion")
    S.moon(cv, w * 0.5, 210, 110, (190, 24, 30), 0.95, halo=(255, 60, 50))
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
