"""角色立繪：面朝右、全身、透明背景，腳底貼齊畫布底邊（art/STYLE.md）。

人形角色都由 figure(spec) 組出來：袍子、袖子、頭、髮、帽、兵器各是一組筆觸；
spec 換顏色、髮型、兵器、姿勢就是不同角色或同一模板的變體。
"""
import math

import numpy as np

from .ink import INK, chaikin, mix

W, H = 360, 480
FEET = 474
SKIN = (236, 214, 188)
GOLD = (196, 160, 80)
HEAD_SCALE = 1.25


def hramp(mask, x0, x1, a0, a1):
    arr, mx, my = mask
    xs = (np.arange(arr.shape[1]) + mx) / 2
    t = np.clip((xs - x0) / max(1e-3, x1 - x0), 0, 1)
    return arr * (a0 + (a1 - a0) * t)[None, :], mx, my


class Fig:
    def __init__(self, cv, spec):
        self.cv, self.s = cv, spec
        self.h = spec.get("height", 430)
        self.cx = W / 2 + spec.get("dx", -10)
        self.lean = spec.get("lean", 0.0)
        self.girth = spec.get("girth", 1.0)

    def P(self, x, f):
        """x：離身體中線的水平距離（往右為正）；f：離地高度佔身高的比例。"""
        return (self.cx + x * self.girth + self.lean * f * f * 150, FEET - f * self.h)

    def pts(self, seq):
        return [self.P(x, f) for x, f in seq]

    def fill(self, seq, color, outline=2.4, shade=0.3, alpha=1.0, close=True, ink=INK):
        cv = self.cv
        pts = chaikin(self.pts(seq), 2)
        m = cv.poly(pts, 0.6)
        cv.paint(m, color, alpha)
        if shade:
            xs = [p[0] for p in pts]
            sh = hramp(m, min(xs), max(xs), 0.0, 1.0)
            cv.paint(cv.textured(sh, 0.6, "cloud"), mix(color, INK, 0.45), shade * alpha)
            cv.paint(cv.textured(m, 1.0, "cloud", lo=0.55), mix(color, INK, 0.3), 0.25 * alpha)
        if outline:
            cv.stroke(pts + ([pts[0]] if close else []), outline, ink, 0.9 * alpha, dry=0.35, taper=(0.03, 0.05), smooth=0)

    def line(self, seq, width=2.0, color=INK, alpha=0.85, **kw):
        self.cv.stroke(self.pts(seq), width, color, alpha, **kw)


# ---------- 人形 ----------

def figure(cv, s):
    f = Fig(cv, s)
    robe, inner = s.get("robe", (200, 206, 210)), s.get("inner", (236, 232, 222))
    sash, trim = s.get("sash", (60, 80, 110)), s.get("trim", (60, 80, 110))
    flare = s.get("flare", 1.0)
    alpha = s.get("alpha", 1.0)
    outline = s.get("outline", 2.4)
    ink = s.get("ink", INK)
    # only：只畫這些部位（換裝用的分層立繪，見 wardrobe.py）；None 是整張一次畫完
    only = s.get("only")
    on = (lambda part: True) if only is None else (lambda part: part in only)

    if on("behind"):
        for e in s.get("behind", []):
            e(f)
    # 背後的頭髮
    hair = s.get("hair", "bun")
    hc = s.get("hair_color", INK)
    if on("hair_back"):
        back_hair(f, hair, hc, alpha, ink)
    # 後袖
    sleeve = s.get("sleeve", "wide")
    if on("sleeve_back"):
        if sleeve == "wide":
            f.fill([(-36, .81), (-58, .7), (-74, .5), (-62, .44), (-46, .48), (-34, .64)], mix(robe, INK, 0.18), outline, 0.2, alpha, ink=ink)
        else:
            f.fill([(-34, .81), (-48, .66), (-50, .5), (-40, .48), (-34, .64)], mix(robe, INK, 0.18), outline, 0.2, alpha, ink=ink)
    if on("back_items"):
        for e in s.get("back_items", []):
            e(f)
    if on("body"):
        body_layer(f, s, robe, inner, sash, trim, flare, alpha, outline, ink)
    if on("belt"):
        for e in s.get("belt", []):
            e(f)
    # 頭
    if on("face"):
        neck = [(-6, .86), (10, .86), (10, .89), (-6, .89)]
        f.fill(neck, s.get("skin", SKIN), 0, 0, alpha)
    head(f, s, alpha, ink, on)
    # 前袖與手
    pose = s.get("pose", "rest")
    skin = s.get("skin", SKIN)
    front_sleeve(f, s, pose, sleeve, robe, skin, alpha, outline, ink, on("sleeve_front"))
    if on("front"):
        for e in s.get("front", []):
            e(f)
    return f


def back_hair(f, hair, hc, alpha, ink):
    if hair in ("long", "long_bun"):
        f.fill([(-6, .97), (-34, .9), (-40, .7), (-34, .55), (-18, .6), (-14, .8), (6, .9)], hc, 1.6, 0, alpha, ink=ink)
    if hair == "ponytail":
        f.line([(-26, .97), (-46, .9), (-50, .78), (-44, .66)], 12, hc, alpha, taper=(0.0, 0.8))
    if hair == "high_tail":
        # 高馬尾：從頭頂後方束起，甩一道長弧到背後
        f.line([(-14, 1.06), (-44, 1.05), (-66, .96), (-74, .82), (-70, .68)], 15, hc, alpha, taper=(0.0, 0.85))
        f.line([(-30, 1.05), (-58, .99), (-70, .86)], 1.0, mix(hc, INK, 0.5), 0.5 * alpha, dry=0.5)
    if hair == "wild":
        # 散亂長髮：幾綹參差往後下散開
        for k, (x, y) in enumerate(((-44, .62), (-56, .7), (-50, .56), (-36, .58))):
            f.line([(-8, .99 - k * .02), (-30 - k * 4, .9), (x, y)], 12 - k * 2, hc, alpha, taper=(0.05, 0.9), jitter=0.2)


def body_layer(f, s, robe, inner, sash, trim, flare, alpha, outline, ink):
    # 內袍下襬
    if not s.get("short_robe"):
        f.fill([(-46 * flare, .14), (52 * flare, .14), (50 * flare, .03), (10, .015), (-44 * flare, .03)], inner, outline * 0.8, 0.15, alpha, ink=ink)
    # 鞋
    for x in (-16, 22):
        f.fill([(x - 12, .03), (x + 14, .03), (x + 18, .0), (x - 12, .0)], s.get("shoes", (40, 36, 34)), 1.2, 0, alpha, ink=ink)
    # 外袍
    body = [(-12, .855), (-44, .815), (-42, .72), (-34, .6), (-40, .5), (-56 * flare, .2), (-62 * flare, .07),
            (-20, .055), (20, .065), (64 * flare, .08), (58 * flare, .22), (44, .5), (36, .6), (42, .72), (44, .815), (12, .855)]
    if s.get("short_robe"):
        body = [(-12, .855), (-44, .815), (-42, .72), (-34, .6), (-44, .45), (-50, .36), (50, .36), (46, .45), (36, .6), (42, .72), (44, .815), (12, .855)]
        for x in (-18, 18):  # 褲腿
            f.fill([(x - 16, .37), (x + 16, .37), (x + 13, .04), (x - 13, .04)], s.get("pants", mix(robe, INK, 0.3)), outline, 0.25, alpha, ink=ink)
    f.fill(body, robe, outline, 0.32, alpha, ink=ink)
    band = s.get("hem_band")
    if band:  # 下襬鑲邊：一道寬色帶沿著袍底
        if s.get("short_robe"):
            f.fill([(-50, .40), (50, .40), (50, .36), (-50, .36)], band, 1.2, 0.2, alpha, ink=ink)
        else:
            f.fill([(-58 * flare, .15), (55 * flare, .17), (64 * flare, .08), (20, .065), (-20, .055), (-62 * flare, .07)], band, 1.2, 0.2, alpha, ink=ink)
    for e in s.get("robe_marks", []):
        e(f)
    # 衣褶
    for x0, x1 in ((-20, -34), (8, 18), (26, 46)):
        if not s.get("short_robe"):
            f.line([(x0, .48), (x0 * 0.9 + x1 * 0.1, .3), (x1, .1)], 1.4, mix(robe, ink, 0.6), 0.5 * alpha, dry=0.5)
    # 交領
    f.line([(-10, .85), (8, .76), (16, .7)], 5, trim, alpha, taper=(0.05, 0.05), smooth=1)
    f.line([(10, .85), (2, .79)], 4, trim, alpha, taper=(0.05, 0.05), smooth=0)
    # 腰帶
    f.fill([(-36, .63), (38, .635), (37, .585), (-35, .58)], sash, 1.4, 0.2, alpha, ink=ink)
    if s.get("sash_tail", True):
        f.line([(-4, .59), (-8, .48), (-4, .4)], 5, sash, alpha, taper=(0.1, 0.4))


def front_sleeve(f, s, pose, sleeve, robe, skin, alpha, outline, ink, draw=True):
    """前袖與手。draw=False 只算出手的位置（f.hand），給兵器、提籃用。"""
    if not draw:
        f = _Ghost(f)
    if pose == "forward":
        f.fill([(28, .82), (50, .81), (84, .7), (100, .66), (98, .58), (72, .6), (42, .66), (30, .72)], robe, outline, 0.28, alpha, ink=ink)
        f.fill([(96, .66), (110, .645), (110, .61), (97, .6)], skin, 1.2, 0, alpha, ink=ink)
        f.hand = f.P(104, .63)
    elif pose == "clasp":
        f.fill([(24, .81), (48, .79), (62, .66), (66, .58), (40, .57), (26, .64)], robe, outline, 0.28, alpha, ink=ink)
        f.fill([(60, .64), (72, .63), (72, .59), (60, .585)], skin, 1.2, 0, alpha, ink=ink)
        f.hand = f.P(68, .61)
    else:
        if sleeve == "wide":
            f.fill([(28, .82), (52, .79), (66, .63), (86, .49), (72, .44), (44, .46), (30, .6)], robe, outline, 0.3, alpha, ink=ink)
            f.fill([(66, .48), (78, .47), (78, .43), (66, .43)], skin, 1.2, 0, alpha, ink=ink)
            f.hand = f.P(72, .45)
        else:
            f.fill([(30, .82), (50, .79), (58, .64), (62, .5), (50, .49), (44, .62), (32, .7)], robe, outline, 0.3, alpha, ink=ink)
            f.fill([(52, .5), (64, .5), (64, .46), (52, .455)], skin, 1.2, 0, alpha, ink=ink)
            f.hand = f.P(58, .475)
    if not draw:
        f.real.hand = f.hand


class _Ghost:
    """不畫任何東西的 Fig 替身：front_sleeve 只想知道手在哪。"""
    def __init__(self, real):
        self.real, self.P = real, real.P

    def fill(self, *a, **kw):
        pass


# 臉型：側臉下半部的輪廓。chin＝下巴尖、jaw＝下顎角（都以頭的半徑為單位，相對頭心）
FACES = {
    "oval":   dict(rx=0.82, ry=0.86, chin=(0.40, 0.98), jaw=None),          # 鵝蛋臉（原本的臉）
    "slender": dict(rx=0.76, ry=0.86, chin=(0.58, 1.08), jaw=(0.02, 0.78)),  # 瓜子臉：下巴尖、往前
    "round":  dict(rx=0.90, ry=0.84, chin=(0.34, 0.96), jaw=(-0.10, 0.86)),  # 圓臉：頰肉飽滿
    "square": dict(rx=0.84, ry=0.86, chin=(0.52, 1.02), jaw=(-0.04, 0.96)),  # 方臉：下顎角明顯，劍客相
}


def eyes(cv, s, ex, ey, eye_c, alpha, ink):
    style = s.get("eye_style", "almond")
    if style == "phoenix":   # 鳳眼：細長、眼尾上挑
        cv.stroke([(ex - 7, ey + 0.8), (ex - 1, ey - 1.4), (ex + 6, ey - 3.6)], 2.4, eye_c, alpha, taper=(0.1, 0.2))
        if not s.get("glow_eyes"):
            cv.paint(cv.ellipse(ex - 0.5, ey + 0.2, 1.6, 1.7, blur=0.4), eye_c, alpha)
            cv.stroke([(ex - 4, ey + 2.2), (ex + 3, ey + 1.0)], 0.9, ink, 0.35 * alpha, smooth=0)
    elif style == "gentle":  # 垂眼：圓、眼尾微垂，溫和
        cv.stroke([(ex - 6, ey - 1.6), (ex - 1, ey - 2.8), (ex + 4, ey + 0.6)], 2.4, eye_c, alpha, taper=(0.1, 0.4))
        if not s.get("glow_eyes"):
            cv.paint(cv.ellipse(ex - 0.8, ey + 0.6, 2.2, 2.4, blur=0.4), eye_c, alpha)
            cv.stroke([(ex - 4, ey + 3.0), (ex + 2, ey + 3.0)], 0.9, ink, 0.35 * alpha, smooth=0)
    else:                    # 杏眼（原本的眼）
        cv.stroke([(ex - 6, ey - 0.5), (ex - 1, ey - 2.2), (ex + 4, ey - 1)], 2.4, eye_c, alpha, taper=(0.1, 0.4))
        if not s.get("glow_eyes"):
            cv.paint(cv.ellipse(ex - 0.5, ey + 0.6, 1.9, 2.1, blur=0.4), eye_c, alpha)
            cv.stroke([(ex - 4, ey + 2.6), (ex + 2, ey + 2.4)], 0.9, ink, 0.35 * alpha, smooth=0)


def brows(cv, s, ex, ey, color, alpha):
    style = s.get("brow_style", "straight")
    if style == "sword":     # 劍眉：粗、斜飛入鬢
        cv.stroke([(ex - 9, ey - 3.5), (ex - 2, ey - 6), (ex + 6, ey - 9)], 3.0, color, 0.95 * alpha, taper=(0.1, 0.7))
    elif style == "willow":  # 柳葉眉：細、彎
        cv.stroke([(ex - 7, ey - 4.5), (ex - 1.5, ey - 7), (ex + 5, ey - 5.5)], 1.5, color, 0.9 * alpha, taper=(0.4, 0.5))
    elif style == "low":     # 原本 NPC 的眉，位置偏高、多半藏在瀏海下
        cv.stroke([(ex - 7, ey - 8), (ex + 4, ey - 10)], 1.8, color, 0.9 * alpha, taper=(0.1, 0.5))
    else:                    # 平眉
        cv.stroke([(ex - 7, ey - 5), (ex + 4, ey - 6.5)], 2.0, color, 0.9 * alpha, taper=(0.1, 0.5))


def head(f, s, alpha, ink, on=lambda part: True):
    cv = f.cv
    hx, hy = f.P(4, .935)
    rx, ry = f.h * 0.052, f.h * 0.064
    # 頭放大（遊戲角色的比例，臉在小畫面上也看得清）：下巴留在原位，頭往上長
    k = s.get("head_scale", HEAD_SCALE)
    hy += ry * 0.98 * (1 - k)
    rx, ry = rx * k, ry * k
    hair, hc = s.get("hair", "bun"), s.get("hair_color", INK)
    skin = s.get("skin", SKIN)
    shape = FACES[s.get("face", "oval")]
    # 頭髮底：比臉大、往後上偏
    if on("hair_under"):
        cv.paint(cv.ellipse(hx - rx * 0.25, hy - ry * 0.12, rx * 1.12, ry * 1.08, blur=0.6), hc, alpha)
    nx, ny = hx + rx * 1.08, hy + ry * 0.12
    cx_, cy_ = shape["chin"]
    if on("face"):
        # 臉：側臉，往右前偏
        face = cv.ellipse(hx + rx * 0.28, hy + ry * 0.18, rx * shape["rx"], ry * shape["ry"], blur=0.6)
        cv.paint(face, skin, alpha)
        if shape["jaw"]:   # 下半臉照臉型補一塊膚色：下顎角到下巴尖
            jx, jy = shape["jaw"]
            low = cv.poly(chaikin([(hx - rx * 0.3, hy + ry * 0.2), (hx + rx * jx, hy + ry * jy), (hx + rx * cx_, hy + ry * cy_),
                                   (hx + rx * 0.9, hy + ry * 0.55), (hx + rx * 0.9, hy - ry * 0.1)], 1), 0.6)
            cv.paint(low, skin, alpha)
            cv.stroke(chaikin([(hx + rx * (jx - 0.08), hy + ry * (jy - 0.12)), (hx + rx * jx, hy + ry * jy), (hx + rx * cx_, hy + ry * cy_)], 1), 1.2, ink, 0.4 * alpha, dry=0.3, taper=(0.6, 0.1))
        cv.paint(hramp(face, hx, hx + rx * 1.2, 0.0, 0.25), mix(skin, INK, 0.3), alpha)
        # 鼻與下巴輪廓
        cv.stroke([(hx + rx * 0.9, hy - ry * 0.2), (nx + 2, ny), (nx - 2, ny + 4), (hx + rx * 0.9, hy + ry * 0.55), (hx + rx * cx_, hy + ry * cy_)], 1.6, ink, 0.8 * alpha, dry=0.2)
    # 瀏海：蓋住額頭
    if on("hair_over"):
        cv.paint(cv.poly(chaikin([(hx - rx * 0.6, hy - ry * 1.05), (hx + rx * 0.95, hy - ry * 0.75), (hx + rx * 0.8, hy - ry * 0.35), (hx + rx * 0.2, hy - ry * 0.3), (hx - rx * 0.4, hy + ry * 0.3)], 2), 0.6), hc, alpha)
    # 眼與眉
    ex, ey = hx + rx * 0.62, hy + ry * 0.02
    eye_c = s.get("eye", ink)
    if on("face"):
        # 耳：臉後緣一個小弧，頭像裁出來時側臉才有結構
        ear_x, ear_y = hx - rx * 0.1, hy + ry * 0.15
        cv.paint(cv.ellipse(ear_x, ear_y, rx * 0.16, ry * 0.22, blur=0.5), mix(skin, INK, 0.12), alpha)
        cv.stroke([(ear_x + rx * 0.05, ear_y - ry * 0.18), (ear_x - rx * 0.14, ear_y), (ear_x + rx * 0.02, ear_y + ry * 0.2)], 1.2, ink, 0.6 * alpha, dry=0.2)
    # 眼：上眼線＋瞳仁，眼角一點下眼線
    if on("eyes"):
        eyes(cv, s, ex, ey, eye_c, alpha, ink)
    if on("face"):
        # 頰上一抹淡紅
        cv.paint(cv.ellipse(hx + rx * 0.45, hy + ry * 0.38, rx * 0.22, ry * 0.12, blur=2.0), (205, 120, 105), 0.25 * alpha)
    if on("eyes") and s.get("glow_eyes"):
        cv.paint(cv.ellipse(ex, ey, 10, 7, blur=4), s["glow_eyes"], 0.9, "over")
        cv.paint(cv.ellipse(ex, ey, 3.5, 2.2, blur=0.6), (255, 230, 200), 1.0)
    if on("brows"):
        brows(cv, s, ex, ey, s.get("brow_color", hc if hc != (236, 236, 230) else (150, 150, 150)), alpha) if "brow_style" in s else \
            brows(cv, dict(brow_style="low"), ex, ey, hc if hc != (236, 236, 230) else (150, 150, 150), alpha)
    if on("face"):
        cv.stroke([(hx + rx * 0.62, hy + ry * 0.6), (hx + rx * 0.8, hy + ry * 0.58)], 1.4, (150, 70, 60), 0.7 * alpha, smooth=0)
    if on("hair_over"):
        hair_top(f, s, hx, hy, rx, ry, hair, hc, alpha, ink)
    if on("head_items"):
        for e in s.get("head_items", []):
            e(f, hx, hy, rx, ry)


def hair_top(f, s, hx, hy, rx, ry, hair, hc, alpha, ink):
    cv = f.cv
    # 髮型
    if hair in ("bun", "long_bun"):
        cv.paint(cv.ellipse(hx - rx * 0.35, hy - ry * 1.05, rx * 0.5, ry * 0.36, blur=0.6), hc, alpha)
        cv.stroke([(hx - rx * 0.9, hy - ry * 1.05), (hx + rx * 0.3, hy - ry * 1.12)], 2.2, s.get("pin", GOLD), alpha, taper=(0.1, 0.1))
    elif hair == "topknot":
        cv.paint(cv.ellipse(hx - rx * 0.2, hy - ry * 1.08, rx * 0.36, ry * 0.3, blur=0.6), hc, alpha)
    elif hair == "twin":
        for dx in (-0.7, 0.25):
            cv.paint(cv.ellipse(hx + rx * dx, hy - ry * 0.95, rx * 0.34, ry * 0.3, blur=0.6), hc, alpha)
    elif hair == "high_tail":
        # 頭頂後方的束髮處，綁一條髮帶
        cv.paint(cv.ellipse(hx - rx * 0.45, hy - ry * 1.02, rx * 0.34, ry * 0.26, blur=0.6), hc, alpha)
        cv.stroke([(hx - rx * 0.62, hy - ry * 1.18), (hx - rx * 0.38, hy - ry * 0.84)], 3.2, s.get("pin", GOLD), alpha, taper=(0.1, 0.1))
    elif hair == "wild":
        # 額前幾綹亂髮垂到眉眼
        for k, (dx, dy) in enumerate(((0.95, -0.05), (0.7, 0.1), (0.4, -0.1))):
            cv.stroke([(hx + rx * (0.1 + k * 0.15), hy - ry * 0.75), (hx + rx * (dx - 0.1), hy - ry * 0.3), (hx + rx * dx, hy + ry * dy)], 7 - k, hc, alpha, taper=(0.05, 0.9))
    cv.stroke(chaikin([(hx - rx * 1.1, hy + ry * 0.1), (hx - rx * 1.05, hy - ry * 0.7), (hx - rx * 0.2, hy - ry * 1.15), (hx + rx * 0.7, hy - ry * 0.9)], 2), 1.8, ink, 0.8 * alpha, dry=0.4)


# ---------- 配件 ----------

def crown(f, hx, hy, rx, ry, color=(40, 40, 44)):
    cv = f.cv
    cv.paint(cv.poly([(hx - rx * 0.7, hy - ry * 0.95), (hx + rx * 0.1, hy - ry * 0.95), (hx + rx * 0.05, hy - ry * 1.5), (hx - rx * 0.6, hy - ry * 1.45)], 0.6), color, 1.0)
    cv.stroke([(hx - rx * 1.2, hy - ry * 1.2), (hx + rx * 0.5, hy - ry * 1.25)], 2.4, GOLD, 1.0, taper=(0.05, 0.05))


def douli(f, hx, hy, rx, ry, color=(150, 120, 74)):
    """斗笠：寬沿竹笠。"""
    cv = f.cv
    pts = [(hx - rx * 2.6, hy - ry * 0.45), (hx, hy - ry * 1.55), (hx + rx * 2.7, hy - ry * 0.5), (hx + rx * 1.2, hy - ry * 0.35), (hx - rx * 1.2, hy - ry * 0.3)]
    cv.paint(cv.poly(chaikin(pts, 1), 0.6), color, 1.0)
    for k in range(-4, 5):
        cv.stroke([(hx + k * 2, hy - ry * 1.5), (hx + k * rx * 0.62, hy - ry * 0.42)], 1.0, INK, 0.45, smooth=0)
    cv.stroke(chaikin(pts + pts[:1], 1), 2.2, INK, 0.9, taper=(0.02, 0.02), smooth=0)


def headband(f, hx, hy, rx, ry, color=(150, 40, 36)):
    cv = f.cv
    cv.stroke([(hx - rx * 1.1, hy - ry * 0.55), (hx + rx * 0.95, hy - ry * 0.6)], 5, color, 1.0, taper=(0.02, 0.02))
    cv.stroke([(hx - rx * 1.05, hy - ry * 0.55), (hx - rx * 1.8, hy - ry * 0.2), (hx - rx * 2.2, hy + ry * 0.1)], 4, color, 1.0, taper=(0.1, 0.8))


def scarf_hood(f, hx, hy, rx, ry, color=(110, 100, 86)):
    cv = f.cv
    cv.paint(cv.poly(chaikin([(hx - rx * 1.3, hy + ry * 0.6), (hx - rx * 1.25, hy - ry * 0.8), (hx, hy - ry * 1.25), (hx + rx * 0.9, hy - ry * 0.85), (hx + rx * 0.6, hy - ry * 0.45), (hx - rx * 0.4, hy - ry * 0.55), (hx - rx * 0.6, hy + ry * 0.7)], 2), 0.6), color, 1.0)


def fox_ears(f, hx, hy, rx, ry, color=(236, 230, 220)):
    cv = f.cv
    for dx, tilt in ((-0.7, -0.35), (0.25, 0.15)):
        bx = hx + rx * dx
        pts = [(bx - rx * 0.32, hy - ry * 0.8), (bx + rx * tilt * 1.4, hy - ry * 1.75), (bx + rx * 0.36, hy - ry * 0.85)]
        cv.paint(cv.poly(pts, 0.6), color, 1.0)
        cv.paint(cv.poly([(bx - rx * 0.12, hy - ry * 0.9), (bx + rx * tilt * 1.2, hy - ry * 1.5), (bx + rx * 0.18, hy - ry * 0.92)], 0.6), (220, 150, 140), 1.0)
        cv.stroke(pts, 1.8, INK, 0.9, smooth=0, taper=(0.05, 0.05))


def beard(f, hx, hy, rx, ry, color=(236, 236, 230)):
    cv = f.cv
    pts = [(hx + rx * 0.2, hy + ry * 0.55), (hx + rx * 0.95, hy + ry * 0.5), (hx + rx * 0.9, hy + ry * 1.6), (hx + rx * 0.5, hy + ry * 2.6), (hx + rx * 0.25, hy + ry * 1.5)]
    cv.paint(cv.poly(chaikin(pts, 2), 0.8), color, 1.0)
    for k in range(4):
        cv.stroke([(hx + rx * (0.4 + k * 0.12), hy + ry * 0.8), (hx + rx * (0.45 + k * 0.05), hy + ry * 2.2)], 1.0, (150, 150, 150), 0.7)
    cv.stroke([(hx + rx * 0.5, hy + ry * 0.45), (hx + rx * 1.1, hy + ry * 0.55)], 3, color, 1.0, taper=(0.1, 0.6))


def white_brows(f, hx, hy, rx, ry):
    f.cv.stroke([(hx + rx * 0.3, hy - ry * 0.18), (hx + rx * 0.95, hy - ry * 0.12), (hx + rx * 1.3, hy + ry * 0.1)], 3, (240, 240, 236), 1.0, taper=(0.1, 0.8))


def ribbon(color=(120, 170, 180), alpha=0.85):
    """飄帶：從肩後拉出一條往後飄的長綢，仙俠角色的招牌剪影。"""
    def draw(f):
        # 中線：肩後 → 往後上揚 → 甩出去再往下飄；兩側各偏半個帶寬
        mid = [(-14, .82), (-50, .8), (-90, .76), (-122, .66), (-128, .52), (-112, .4), (-124, .26), (-140, .17)]
        wid = [0.016, 0.026, 0.032, 0.034, 0.032, 0.028, 0.024, 0.012]
        top = [(x, y + w) for (x, y), w in zip(mid, wid)]
        bot = [(x + 4, y - w) for (x, y), w in reversed(list(zip(mid, wid)))]
        f.fill(top + bot, color, 1.6, 0.3, alpha)
        f.line([(-40, .8), (-96, .75), (-122, .62)], 1.0, mix(color, INK, 0.5), 0.5 * alpha, dry=0.5)
    return draw


def sword_back(f, scab=(50, 40, 36), hilt=(70, 50, 30)):
    """背劍：劍鞘斜在背後，劍柄從左肩後露出來。"""
    cv = f.cv
    a, b = f.P(30, .42), f.P(-30, .9)
    cv.stroke([a, b], 9, scab, 1.0, taper=(0.02, 0.02), smooth=0, dry=0.1)
    cv.stroke([a, b], 2, INK, 0.8, taper=(0.02, 0.02), smooth=0)
    g = b
    cv.stroke([(g[0] - 9, g[1] + 6), (g[0] + 9, g[1] - 6)], 5, GOLD, 1.0, smooth=0, taper=(0.02, 0.02))
    top = f.P(-44, 1.0)
    cv.stroke([g, top], 6, hilt, 1.0, smooth=0, taper=(0.02, 0.02))
    cv.stroke([top, (top[0] - 6, top[1] + 22), (top[0] - 2, top[1] + 40)], 2, (180, 40, 40), 0.9, taper=(0.1, 0.8))


def blade(f, length=150, angle=-0.25, width=6, color=(200, 206, 210), curve=0.0, glow=None):
    """手上的劍／刀。angle 是弧度（0 朝右、負的往上）。"""
    cv = f.cv
    hx, hy = f.hand
    tip = (hx + math.cos(angle) * length, hy + math.sin(angle) * length)
    mid = ((hx + tip[0]) / 2 - math.sin(angle) * curve, (hy + tip[1]) / 2 + math.cos(angle) * curve)
    if glow:
        cv.stroke([(hx, hy), mid, tip], width * 4, glow, 0.35, taper=(0.1, 0.3), dry=0)
    cv.stroke([(hx, hy), mid, tip], width, color, 1.0, taper=(0.02, 0.6), press=[1, 1, 0.9, 0.2], dry=0.05)
    cv.stroke([(hx, hy), mid, tip], 1.4, INK, 0.8, taper=(0.02, 0.6))
    gx, gy = hx + math.cos(angle) * 8, hy + math.sin(angle) * 8
    n = (-math.sin(angle), math.cos(angle))
    cv.stroke([(gx - n[0] * 10, gy - n[1] * 10), (gx + n[0] * 10, gy + n[1] * 10)], 4, GOLD, 1.0, smooth=0, taper=(0.05, 0.05))
    back = (hx - math.cos(angle) * 22, hy - math.sin(angle) * 22)
    cv.stroke([(hx, hy), back], 5, (70, 50, 30), 1.0, smooth=0, taper=(0.05, 0.05))


def whisk(f):
    cv = f.cv
    hx, hy = f.hand
    cv.stroke([(hx - 4, hy + 6), (hx + 10, hy - 40)], 4, (120, 80, 40), 1.0, smooth=0)
    for k in range(12):
        dx = -12 + k * 2.2
        cv.stroke([(hx - 4, hy + 6), (hx - 10 + dx, hy + 50), (hx - 30 + dx * 1.5, hy + 110)], 1.4, (240, 238, 232), 0.9, taper=(0.1, 0.6))


def staff(f, color=(110, 76, 44), top=None):
    cv = f.cv
    hx, hy = f.hand
    cv.stroke([(hx + 4, FEET), (hx, hy), (hx - 6, FEET - f.h * 1.02)], 6, color, 1.0, taper=(0.02, 0.02), dry=0.3)
    if top:
        top(f, (hx - 6, FEET - f.h * 1.02))


def gourd(f, color=(186, 140, 60)):
    cv = f.cv
    x, y = f.P(-30, .54)
    cv.paint(cv.ellipse(x, y + 10, 10, 12, blur=0.6), color, 1.0)
    cv.paint(cv.ellipse(x, y - 6, 7, 8, blur=0.6), color, 1.0)
    cv.stroke([(x - 8, y + 2), (x + 8, y + 2)], 2, (150, 40, 36), 1.0, smooth=0)
    cv.stroke([(x, y - 14), (x + 2, y - 20)], 3, (100, 70, 40), 1.0, smooth=0)


def talismans(f, n=3):
    cv = f.cv
    for k in range(n):
        x, y = f.P(-20 + k * 18, .575)
        cv.paint(cv.rect(x - 5, y, x + 5, y + 36), (226, 196, 90), 1.0)
        cv.stroke([(x, y + 6), (x - 2, y + 18), (x + 2, y + 30)], 2, (180, 30, 30), 1.0, smooth=1)


def book_box(f):
    """行商的書箱式背架。"""
    cv = f.cv
    a, b = f.P(-82, .82), f.P(-26, .45)
    cv.paint(cv.rect(a[0], a[1], b[0], b[1], blur=0.6), (130, 96, 60), 1.0)
    for f_ in (.72, .62, .52):
        y = f.P(0, f_)[1]
        cv.stroke([(a[0], y), (b[0], y)], 2, INK, 0.7, smooth=0)
    cv.stroke([(a[0], a[1]), (b[0], a[1]), (b[0], b[1]), (a[0], b[1]), (a[0], a[1])], 2.4, INK, 0.9, smooth=0, taper=(0.01, 0.01))
    cv.paint(cv.rect(a[0] - 4, a[1] - 26, b[0] + 4, a[1] - 2), (180, 160, 120), 1.0)
    cv.stroke([(a[0] - 6, a[1] - 26), (b[0] + 6, a[1] - 26)], 2, INK, 0.8, smooth=0)
    for x in (a[0] + 6, b[0] - 6):
        cv.stroke([(x, b[1]), (x, FEET - 6)], 3, (100, 70, 44), 1.0, smooth=0)
    # 掛在架上的布旗：藥
    cv.paint(cv.rect(a[0] - 26, a[1] - 60, a[0] - 4, a[1] + 10), (210, 200, 176), 1.0)
    cv.stroke([(a[0] - 4, a[1] - 70), (a[0] - 4, b[1])], 2.5, (100, 70, 44), 1.0, smooth=0)
    from .scenery import FONT
    cv.text("藥", a[0] - 25, a[1] - 46, 20, (150, 30, 30), 0.95, FONT)


def basket(f):
    cv = f.cv
    hx, hy = f.hand
    cv.paint(cv.poly([(hx - 22, hy), (hx + 22, hy), (hx + 16, hy + 30), (hx - 16, hy + 30)], 0.6), (170, 130, 80), 1.0)
    for k in range(4):
        cv.stroke([(hx - 20, hy + 6 + k * 7), (hx + 20, hy + 6 + k * 7)], 1.2, INK, 0.5, smooth=0)
    cv.stroke(chaikin([(hx - 20, hy), (hx, hy - 24), (hx + 20, hy)], 2), 2.5, (120, 86, 50), 1.0)
    for dx in (-8, 4):
        cv.paint(cv.ellipse(hx + dx, hy - 2, 7, 5), (90, 120, 70), 1.0)


def chain(f):
    cv = f.cv
    hx, hy = f.hand
    pts = [(hx + k * 9, hy + 30 * math.sin(k / 5) + k * 3) for k in range(14)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        cv.paint(cv.ellipse((x0 + x1) / 2, (y0 + y1) / 2, 5.5, 3.5, angle=math.atan2(y1 - y0, x1 - x0)), (120, 120, 126), 1.0)
        cv.stroke([(x0, y0), (x1, y1)], 1.0, INK, 0.6, smooth=0)
    x, y = pts[-1]
    cv.paint(cv.poly([(x, y - 6), (x + 16, y), (x, y + 6)], 0.5), (160, 160, 166), 1.0)


def aura(color, rx=120, ry=220, alpha=0.5):
    def draw(f):
        cx, cy = f.P(0, .5)
        f.cv.paint(f.cv.ellipse(cx, cy, rx, ry, blur=40), color, alpha)
    return draw


def smoke(color=INK, alpha=0.8, reach=0.25):
    """腳邊的墨煙，讓輪廓下緣散開。"""
    def draw(f):
        cv = f.cv
        for _ in range(26):
            x = f.cx + cv.rng.uniform(-110, 110)
            y = FEET - cv.rng.uniform(0, f.h * reach)
            cv.dab(x, y, cv.rng.uniform(8, 22), color, alpha * cv.rng.uniform(0.3, 0.8), squash=0.5)
    return draw


def foxfire(f):
    cv = f.cv
    for x, fr in ((-90, .78), (98, .86), (-70, .35)):
        px, py = f.P(x, fr)
        cv.paint(cv.ellipse(px, py, 16, 20, blur=8), (120, 200, 255), 0.6)
        cv.paint(cv.poly(chaikin([(px - 7, py + 6), (px - 2, py - 16), (px + 2, py - 26), (px + 7, py + 4), (px, py + 10)], 2), 0.8), (210, 240, 255), 0.9)


def fox_tails(n=3, color=(236, 230, 220), tip=(240, 190, 160)):
    def draw(f):
        cv = f.cv
        for k in range(n):
            bx, by = f.P(-24, .38)
            spread = (k - (n - 1) / 2)
            pts = [(bx, by), (bx - 50, by + 10 - 20 * spread), (bx - 95, by - 30 - 55 * spread), (bx - 80 + 10 * spread, by - 90 - 50 * spread)]
            sp = chaikin(pts, 3)
            cv.stroke(sp, 36, mix(color, INK, 0.12 * k), 1.0, taper=(0.15, 0.55), dry=0.0, jitter=0.12)
            cv.stroke(sp[len(sp) * 2 // 3:], 26, tip, 0.9, taper=(0.2, 0.7), dry=0.0)
            cv.stroke(sp, 1.6, INK, 0.7, taper=(0.1, 0.5), dry=0.4)
    return draw


def fade_bottom(cv, start=0.55, end=0.98, keep=0.0):
    """記憶殘影：下半身漸漸散掉。"""
    ys = np.arange(cv.H) / 2
    t = np.clip((ys - start * H) / ((end - start) * H), 0, 1)
    k = 1 - t * (1 - keep)
    noise = np.clip(cv.cloud * 1.6 - 0.3, 0, 1)
    k = k[:, None] * (1 - t[:, None] * (1 - noise))
    cv.prgb *= k[..., None]
    cv.a *= k


# ---------- 非人形 ----------

def wolf_demon(cv):
    """狼妖：前傾、獸首、爪、尾，毛邊參差。"""
    fur, belly, dark = (96, 90, 84), (150, 140, 126), (50, 46, 44)
    cx = 170
    def jag(pts, amp=3, n=9):
        out = []
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            for k in range(n):
                t = k / n
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                nx, ny = -(y1 - y0), (x1 - x0)
                L = math.hypot(nx, ny) or 1
                j = amp * (1 if k % 3 == 0 else -0.2) * cv.rng.uniform(0.4, 1.3)
                out.append((x + nx / L * j, y + ny / L * j))
        out.append(pts[-1])
        return out

    def body_fill(pts, color, amp=3):
        p = jag(pts, amp)
        cv.paint(cv.poly(p, 0.6), color, 1.0)
        cv.paint(cv.textured(hramp(cv.poly(p, 0.6), min(x for x, _ in p), max(x for x, _ in p), 0, 1), 0.6, "cloud"), mix(color, INK, 0.5), 0.35)
        cv.stroke(p + [p[0]], 2.2, INK, 0.9, dry=0.4, smooth=0, taper=(0.02, 0.02))

    # 尾
    cv.stroke(chaikin([(cx - 50, 300), (cx - 110, 320), (cx - 150, 280), (cx - 160, 220)], 3), 34, fur, 1.0, taper=(0.3, 0.7), jitter=0.3, dry=0.2)
    cv.stroke(chaikin([(cx - 50, 300), (cx - 110, 320), (cx - 150, 280), (cx - 160, 220)], 3), 2, INK, 0.7, taper=(0.3, 0.7))
    # 後腿（反關節）
    body_fill([(cx - 50, 290), (cx - 10, 320), (cx - 20, 380), (cx - 2, 440), (cx + 10, 474), (cx - 30, 474), (cx - 40, 440), (cx - 70, 380)], dark)
    body_fill([(cx + 10, 300), (cx + 50, 330), (cx + 40, 390), (cx + 60, 440), (cx + 76, 474), (cx + 34, 474), (cx + 26, 440), (cx - 10, 380)], fur)
    # 軀幹，前傾
    body_fill([(cx - 60, 300), (cx - 40, 190), (cx + 20, 140), (cx + 80, 150), (cx + 90, 210), (cx + 60, 300), (cx + 10, 330)], fur, 4)
    cv.paint(cv.poly(chaikin([(cx + 40, 180), (cx + 82, 200), (cx + 60, 290), (cx + 20, 300)], 2), 2), belly, 0.8)
    # 破布腰帶
    cv.stroke([(cx - 50, 280), (cx + 64, 270)], 12, (120, 40, 34), 1.0, taper=(0.05, 0.05), dry=0.3)
    cv.stroke([(cx - 30, 282), (cx - 40, 330), (cx - 30, 360)], 8, (120, 40, 34), 1.0, taper=(0.1, 0.8), dry=0.3)
    # 後臂
    body_fill([(cx + 10, 170), (cx - 20, 230), (cx - 30, 290), (cx - 12, 296), (cx + 10, 240), (cx + 30, 190)], dark)
    # 頭：狼首
    hx = cx + 110
    body_fill([(hx - 60, 150), (hx - 50, 90), (hx - 30, 70), (hx - 20, 30), (hx - 4, 66), (hx + 20, 74), (hx + 60, 96), (hx + 74, 112), (hx + 50, 124), (hx + 60, 138), (hx + 20, 146), (hx - 10, 166)], fur, 3)
    cv.paint(cv.poly([(hx - 16, 40), (hx - 8, 64), (hx - 22, 66)], 0.5), (160, 90, 80), 1.0)
    cv.paint(cv.ellipse(hx + 72, 108, 5, 4), INK, 1.0)
    cv.stroke([(hx + 20, 126), (hx + 56, 128)], 2, INK, 0.9)
    for k in range(3):
        x = hx + 26 + k * 10
        cv.paint(cv.poly([(x, 124), (x + 4, 124), (x + 2, 134)], 0.3), (240, 236, 226), 1.0)
    cv.paint(cv.ellipse(hx + 14, 94, 10, 6, blur=4), (255, 140, 40), 0.9)
    cv.paint(cv.ellipse(hx + 15, 94, 4, 2.5), (255, 230, 160), 1.0)
    cv.stroke([(hx, 84), (hx + 26, 88)], 3, INK, 0.9, taper=(0.1, 0.6))
    # 前臂伸爪
    body_fill([(cx + 60, 170), (cx + 110, 200), (cx + 150, 230), (cx + 166, 222), (cx + 160, 248), (cx + 130, 250), (cx + 90, 228), (cx + 50, 210)], fur)
    for k in range(4):
        x0, y0 = cx + 150 + k * 4, 236 + k * 5
        cv.stroke([(x0, y0), (x0 + 22, y0 + 6 + k * 2)], 3, (236, 230, 216), 1.0, taper=(0.1, 0.9))


def demon_lord(cv):
    """妖王：高大、雙角、大氅邊緣如火，背後赤色妖氣。"""
    cx = 176
    cv.paint(cv.ellipse(cx, 260, 160, 230, blur=50), (180, 30, 30), 0.45)
    cloak = [(cx - 30, 120), (cx - 90, 160), (cx - 130, 300), (cx - 160, 474), (cx - 60, 450), (cx - 20, 474), (cx + 40, 452),
             (cx + 100, 474), (cx + 130, 380), (cx + 90, 250), (cx + 60, 140)]
    pts = []
    for (x0, y0), (x1, y1) in zip(cloak, cloak[1:] + cloak[:1]):
        for k in range(5):
            t = k / 5
            pts.append((x0 + (x1 - x0) * t + cv.rng.uniform(-8, 8), y0 + (y1 - y0) * t + cv.rng.uniform(-8, 8)))
    cv.paint(cv.poly(pts, 1), (24, 16, 20), 1.0)
    cv.paint(cv.textured(cv.poly(pts, 1), 1.0, "cloud", lo=0.6), (90, 20, 26), 0.6)
    cv.stroke(pts + pts[:1], 3, (150, 30, 30), 0.7, dry=0.5, smooth=0, taper=(0.01, 0.01))
    # 盔甲軀幹
    cv.paint(cv.poly(chaikin([(cx - 50, 140), (cx + 54, 140), (cx + 46, 290), (cx - 40, 290)], 2), 1), (70, 56, 50), 1.0)
    for y in range(160, 290, 22):
        cv.stroke([(cx - 44, y), (cx + 48, y + 4)], 3, (150, 120, 70), 0.9, taper=(0.05, 0.05))
    cv.stroke([(cx - 48, 290), (cx + 50, 290)], 10, (130, 30, 30), 1.0, taper=(0.05, 0.05))
    # 肩甲
    for sx in (-56, 60):
        cv.paint(cv.ellipse(cx + sx, 150, 32, 20, blur=1), (90, 70, 60), 1.0)
        for k in range(3):
            cv.stroke([(cx + sx - 26, 140 + k * 6), (cx + sx + 28, 140 + k * 6)], 2, INK, 0.6)
        cv.paint(cv.poly([(cx + sx - 10, 136), (cx + sx, 104), (cx + sx + 8, 136)], 0.6), (220, 214, 200), 1.0)
    # 頭與角
    hx, hy = cx + 8, 96
    cv.paint(cv.ellipse(hx, hy, 26, 30, blur=0.6), (150, 150, 160), 1.0)
    cv.paint(hramp(cv.ellipse(hx, hy, 26, 30, blur=0.6), hx - 26, hx + 26, 0, 1), (60, 50, 60), 0.5)
    cv.paint(cv.poly(chaikin([(hx - 30, hy - 6), (hx - 20, hy - 36), (hx + 22, hy - 34), (hx + 30, hy - 4), (hx + 10, hy - 18), (hx - 14, hy - 16)], 2), 0.6), INK, 1.0)
    for sgn in (-1, 1):
        cv.stroke(chaikin([(hx + sgn * 18, hy - 26), (hx + sgn * 38, hy - 56), (hx + sgn * 30, hy - 86), (hx + sgn * 44, hy - 100)], 2), 12, (220, 210, 190), 1.0, taper=(0.0, 0.95), dry=0.1)
    for ex in (hx + 6, hx + 20):
        cv.paint(cv.ellipse(ex, hy - 2, 9, 5, blur=3.5), (255, 40, 30), 1.0)
        cv.paint(cv.ellipse(ex, hy - 2, 3, 2), (255, 230, 200), 1.0)
    cv.stroke([(hx + 4, hy + 16), (hx + 24, hy + 14)], 2.5, INK, 0.9)
    # 長髮往後飄
    for k in range(4):
        cv.stroke(chaikin([(hx - 22, hy - 14 + k * 8), (hx - 60, hy + 20 + k * 14), (hx - 80, hy + 70 + k * 16), (hx - 110, hy + 110 + k * 10)], 3), 10, INK, 0.9, taper=(0.1, 0.9), dry=0.4)
    # 手持巨刃
    cv.stroke([(cx + 70, 270), (cx + 150, 60)], 14, (60, 60, 66), 1.0, taper=(0.02, 0.5), smooth=0)
    cv.stroke([(cx + 70, 270), (cx + 150, 60)], 2, (220, 60, 50), 0.8, taper=(0.02, 0.5), smooth=0)
    cv.paint(cv.ellipse(cx + 70, 270, 14, 14, blur=0.6), (80, 60, 50), 1.0)
    cv.stroke([(cx + 70, 270), (cx + 54, 320)], 8, (60, 30, 20), 1.0, smooth=0)
    # 腳下妖氣
    for _ in range(30):
        x = cx + cv.rng.uniform(-150, 150)
        cv.dab(x, 474 - cv.rng.uniform(0, 60), cv.rng.uniform(10, 24), (40, 10, 14), cv.rng.uniform(0.4, 0.9), squash=0.5)
