"""玩家衣櫃的單件衣物：上衣、下裳、外罩、腰封、護腕、鞋靴、髮飾，每件各畫成自己的圖層。

跟 figures.figure 用同一個 Fig 幾何（身高、站位一樣），所以任何一件疊在任何一件上都對得上。
每件衣物是一個 dict（長相），draw_<部位>(f, spec, part) 只畫那件衣物在某一個圖層的部分
（例如上衣分成後袖、身、前袖三層，外罩分成後袖、身、前袖三層），疊圖順序見 wardrobe.ORDER。
"""
from . import figures as F
from .ink import INK, chaikin, mix

GOLD = F.GOLD
SKIN = F.SKIN


# ---------- 上衣 ----------

def top_body(f, t):
    """上衣的身：長袍（到腳踝）或短衣（到臀），可開前衩讓下裳露出來。"""
    c, fl = t["color"], t.get("flare", 1.0)
    trim = t.get("trim", INK)
    if t.get("length") == "short":
        body = [(-12, .855), (-44, .815), (-42, .72), (-34, .6), (-44, .45), (-50, .36), (50, .36), (46, .45), (36, .6), (42, .72), (44, .815), (12, .855)]
    else:
        hem_front = [(2, .06), (12, .36), (30, .075)] if t.get("split") else [(20, .065)]
        body = [(-12, .855), (-44, .815), (-42, .72), (-34, .6), (-40, .5), (-56 * fl, .2), (-62 * fl, .07), (-20, .055)] + hem_front + \
               [(64 * fl, .08), (58 * fl, .22), (44, .5), (36, .6), (42, .72), (44, .815), (12, .855)]
    f.fill(body, c, 2.4, 0.32)
    band = t.get("hem_band")
    if band:
        if t.get("length") == "short":
            f.fill([(-50, .40), (50, .40), (50, .36), (-50, .36)], band, 1.2, 0.2)
        elif t.get("split"):
            f.fill([(-58 * fl, .15), (5, .155), (2, .06), (-20, .055), (-62 * fl, .07)], band, 1.2, 0.2)
            f.fill([(22, .155), (55 * fl, .17), (64 * fl, .08), (30, .075)], band, 1.2, 0.2)
        else:
            f.fill([(-58 * fl, .15), (55 * fl, .17), (64 * fl, .08), (20, .065), (-20, .055), (-62 * fl, .07)], band, 1.2, 0.2)
        pat = t.get("hem_pattern")
        if pat:  # 鑲邊上的回紋
            short = t.get("length") == "short"
            for k in range(8):
                u = (k + 0.5) / 8
                x = -50 + 100 * u if short else (-56 * fl) + (114 * fl) * u
                if t.get("split") and 4 < x < 26:
                    continue
                cx, cy = f.P(x, (.38 if short else .11) + .01 * u)
                f.cv.stroke([(cx - 3, cy + 3), (cx - 3, cy - 3), (cx + 3, cy - 3), (cx + 3, cy + 1), (cx, cy + 1)], 1.3, pat, 0.9, smooth=0, taper=(0.05, 0.05))
    if t.get("split") and t.get("length") != "short":
        f.line([(12, .36), (30, .075)], 2.4, trim, 1.0, taper=(0.1, 0.1))
        f.line([(12, .36), (2, .06)], 2.4, trim, 1.0, taper=(0.1, 0.1))
    for e in t.get("marks", []):
        e(f)
    if t.get("length") != "short":
        for x0, x1 in ((-20, -34), (8, 18), (26, 46)):
            if t.get("split") and x0 > 0:
                continue
            f.line([(x0, .48), (x0 * 0.9 + x1 * 0.1, .3), (x1, .1)], 1.4, mix(c, INK, 0.6), 0.5, dry=0.5)
    # 交領：寬領緣，裡面多露一道中衣的白
    f.line([(-8, .855), (8, .77), (18, .7)], 9, (240, 238, 230), 1.0, taper=(0.05, 0.05), smooth=1)
    f.line([(-12, .86), (6, .77), (14, .7)], 7, trim, 1.0, taper=(0.05, 0.05), smooth=1)
    f.line([(10, .86), (0, .79)], 6, trim, 1.0, taper=(0.05, 0.05), smooth=0)


def top_sleeve_back(f, t):
    c = mix(t["color"], INK, 0.18)
    cuff = t.get("cuff")
    if t.get("sleeve") == "wide":
        f.fill([(-36, .81), (-58, .7), (-74, .5), (-62, .44), (-46, .48), (-34, .64)], c, 2.4, 0.2)
        if cuff:
            f.line([(-73, .5), (-62, .45), (-47, .485)], 6, mix(cuff, INK, 0.15), 1.0, taper=(0.05, 0.05))
    else:
        f.fill([(-34, .81), (-48, .66), (-50, .5), (-40, .48), (-34, .64)], c, 2.4, 0.2)


def top_sleeve_front(f, t):
    c, cuff = t["color"], t.get("cuff")
    if t.get("sleeve") == "wide":
        f.fill([(28, .82), (52, .79), (66, .63), (86, .49), (72, .44), (44, .46), (30, .6)], c, 2.4, 0.3)
        f.fill([(66, .48), (78, .47), (78, .43), (66, .43)], SKIN, 1.2, 0)
        if cuff:
            f.line([(86, .49), (72, .44), (45, .465)], 7, cuff, 1.0, taper=(0.05, 0.05))
    else:
        f.fill([(30, .82), (50, .79), (58, .64), (62, .5), (50, .49), (44, .62), (32, .7)], c, 2.4, 0.3)
        f.fill([(52, .5), (64, .5), (64, .46), (52, .455)], SKIN, 1.2, 0)


# ---------- 下裳 ----------

def bottom(f, b):
    """下裳：長褲兩條褲腿，或從腰垂到腳踝的裙裳（可襯幾層紗）。長袍底下主要從開衩、短衣下面看得到。"""
    c = b["color"]
    if b.get("kind") == "skirt":
        for k, lc in reversed(list(enumerate(b.get("layers", [])))):
            d = (k + 1) * .016
            f.fill([(-46, .3), (46, .3), (62 + k * 3, .07 - d), (14, .055 - d), (-30, .05 - d), (-70 - k * 9, .065 - d * 0.6)], lc, 1.2, 0.15)
        f.fill([(-36, .6), (38, .6), (52, .3), (60, .05), (10, .035), (-30, .03), (-56, .05), (-46, .3)], c, 2.0, 0.3)
        for x in (-20, 0, 22, 40):
            f.line([(x * 0.6, .55), (x, .06)], 1.2, mix(c, INK, 0.55), 0.45, dry=0.5)
        if b.get("hem"):
            f.fill([(-56, .1), (58, .1), (60, .05), (10, .035), (-30, .03), (-56, .05)], b["hem"], 1.2, 0.2)
    else:
        for x in (-18, 18):
            f.fill([(x - 16, .6), (x + 16, .6), (x + 15, .37), (x + 13, .04), (x - 13, .04), (x - 15, .37)], c, 2.2, 0.3)
            f.line([(x - 4, .5), (x - 2, .1)], 1.1, mix(c, INK, 0.55), 0.45, dry=0.5)


# ---------- 鞋靴 ----------

def shoes(f, s):
    c = s["color"]
    for x in (-16, 22):
        if s.get("kind") == "boots":
            f.fill([(x - 11, .13), (x + 11, .13), (x + 12, .03), (x + 19, .0), (x - 12, .0), (x - 12, .03)], c, 1.4, 0.25)
            f.line([(x - 11, .125), (x + 11, .125)], 3, s.get("cuff", mix(c, (230, 220, 200), 0.35)), 0.8, smooth=0)
        elif s.get("kind") == "wraps":  # 綁腿草鞋：小腿纏布，腳上草鞋
            f.fill([(x - 13, .2), (x + 13, .2), (x + 12, .03), (x - 12, .03)], s.get("wrap", (214, 206, 188)), 1.2, 0.2)
            for k in range(4):
                f.line([(x - 12, .19 - k * .04), (x + 12, .165 - k * .04)], 1.0, INK, 0.45, smooth=0)
            f.fill([(x - 12, .03), (x + 14, .03), (x + 18, .0), (x - 12, .0)], c, 1.2, 0)
        elif s.get("kind") == "cloud":  # 雲頭履：鞋頭翹起一朵捲雲
            f.fill([(x - 12, .03), (x + 14, .03), (x + 18, .0), (x - 12, .0)], c, 1.2, 0)
            cx, cy = f.P(x + 18, .02)
            f.cv.stroke([(cx - 4, cy + 3), (cx + 2, cy - 4), (cx + 6, cy), (cx + 2, cy + 2)], 2.0, s.get("tip", GOLD), 1.0, smooth=1)
        else:
            f.fill([(x - 12, .03), (x + 14, .03), (x + 18, .0), (x - 12, .0)], c, 1.2, 0)


# ---------- 外罩 ----------

def coat_body(f, o):
    """外罩的身：半臂、褙子到膝、大氅到腳。對襟敞開，前緣與下襬鑲邊。"""
    hem, fl = o.get("length", .3), o.get("flare", 1.0)
    c, tr = o["color"], o.get("trim", INK)
    coat = [(-12, .86), (-46, .82), (-46, .72), (-40, .6), (-46, .5), (-60 * fl, hem + .06), (-66 * fl, hem),
            (-20, hem - .01), (14 * fl, hem + .005), (10, .5), (8, .64), (4, .78), (2, .855)]
    f.fill(coat, c, 2.4, 0.35)
    f.line([(2, .85), (4, .78), (8, .64), (10, .5), (14 * fl, hem + .01)], 5, tr, 1.0, taper=(0.05, 0.05))
    f.line([(14 * fl, hem + .01), (-20, hem - .005), (-66 * fl, hem + .005)], 5, tr, 1.0, taper=(0.05, 0.05))
    if o.get("slit"):
        f.line([(-44, .44), (-52 * fl, hem + .02)], 2.0, mix(c, INK, 0.6), 0.8)
    for e in o.get("marks", []):
        e(f)


def coat_sleeve_back(f, o):
    if o.get("sleeve") == "long":
        f.fill([(-38, .82), (-64, .7), (-84, .44), (-66, .38), (-46, .44), (-34, .64)], mix(o["color"], INK, 0.18), 2.4, 0.2)
        f.line([(-83, .45), (-66, .39), (-47, .445)], 5, mix(o.get("trim", o["color"]), INK, 0.15), 1.0, taper=(0.05, 0.05))


def coat_sleeve_front(f, o):
    c, tr = o["color"], o.get("trim", INK)
    if o.get("sleeve") == "half":
        f.fill([(26, .83), (52, .8), (60, .68), (40, .66), (28, .72)], c, 2.4, 0.3)
        f.line([(60, .68), (40, .66)], 5, tr, 1.0, taper=(0.05, 0.05))
    elif o.get("sleeve") == "long":
        f.fill([(26, .83), (54, .8), (72, .6), (94, .42), (78, .36), (46, .42), (30, .6)], c, 2.4, 0.32)
        f.line([(94, .42), (78, .365), (47, .425)], 6, tr, 1.0, taper=(0.05, 0.05))


# ---------- 腰封 ----------

def belt(f, w):
    """腰封：寬腰封＋繩結＋兩條垂帶（wrap）、細腰帶（sash）、繩腰帶（rope）。"""
    wc = w["color"]
    kind = w.get("kind", "wrap")
    if kind == "sash":
        f.fill([(-36, .63), (38, .635), (37, .585), (-35, .58)], wc, 1.4, 0.2)
        f.line([(-4, .59), (-8, .48), (-4, .4)], 5, wc, 1.0, taper=(0.1, 0.4))
        return
    if kind == "rope":
        for dy in (0, .02):
            f.line([(-36, .6 + dy), (0, .595 + dy), (38, .605 + dy)], 3.4, wc, 1.0, smooth=1)
        f.line([(22, .6), (16, .5), (20, .42)], 3, wc, 1.0, taper=(0.1, 0.5))
        f.line([(22, .6), (28, .52), (26, .44)], 3, wc, 1.0, taper=(0.1, 0.5))
    else:
        wt = w.get("trim", GOLD)
        f.fill([(-37, .655), (39, .66), (38, .565), (-36, .56)], wc, 1.6, 0.25)
        f.line([(-36, .645), (38, .65)], 1.6, wt, 0.9, smooth=0)
        f.line([(-35, .575), (37, .58)], 1.6, wt, 0.9, smooth=0)
        tail, n = w.get("tail", wc), w.get("tail_len", 1.0)
        F.streamer(f, [(20, .6), (15, .53), (19, .47), (12, .44 - .14 * n)], [.008, .012, .012, .008], tail)
        F.streamer(f, [(18, .6), (-2, .54), (-26, .47 - .02 * n), (-46, .4 - .07 * n), (-54, .33 - .12 * n)],
                   [.008, .013, .015, .014, .006], tail)
        f.cv.paint(f.cv.ellipse(*f.P(20, .61), 6, 5, blur=0.4), mix(tail, INK, 0.2), 1.0)
    if w.get("tassel"):
        n = w.get("tail_len", 1.0)
        tx, ty = f.P(12, .44 - .14 * n) if kind == "wrap" else f.P(20, .42)
        f.cv.paint(f.cv.ellipse(tx, ty, 3.5, 3.5, blur=0.4), w["tassel"], 1.0)
        for dx in (-2, 0, 2):
            f.cv.stroke([(tx + dx, ty + 2), (tx + dx * 1.6, ty + 20)], 1.3, w["tassel"], 0.9, taper=(0.1, 0.6))


# ---------- 護腕 ----------

def cuffs(f, c):
    """護腕（束袖版）：前手手腕一截，綁兩道繩。後手的被身體擋住，不畫。"""
    col = c["color"]
    f.fill([(48, .575), (63, .57), (64, .5), (50, .5)], col, 1.4, 0.25)
    for y in (.555, .52):
        f.line([(49, y), (63, y - .004)], 1.2, c.get("cord", mix(col, (240, 230, 200), 0.5)), 0.9, smooth=0)
    if c.get("stud"):
        f.cv.paint(f.cv.ellipse(*f.P(56, .537), 2.4, 2.4, blur=0.3), c["stud"], 1.0)


def cuffs_wide(f, c):
    """寬袖版：護腕從袖口底下露出一截，在手腕上。"""
    col = c["color"]
    f.fill([(62, .5), (78, .49), (79, .44), (63, .445)], col, 1.4, 0.25)
    f.line([(63, .475), (78, .468)], 1.2, c.get("cord", mix(col, (240, 230, 200), 0.5)), 0.9, smooth=0)


# ---------- 髮飾 ----------

def hair_acc_front(f, a, hair, hx, hy, rx, ry):
    cv = f.cv
    kind, col = a["kind"], a.get("color", GOLD)
    if hair in ("twin",):
        anchors = [(hx + rx * -0.7, hy - ry * 0.95), (hx + rx * 0.25, hy - ry * 0.95)]
    elif hair in ("topknot",):
        anchors = [(hx - rx * 0.2, hy - ry * 1.08)]
    elif hair in ("ponytail", "high_tail"):
        anchors = [(hx - rx * 0.5, hy - ry * 0.95)]
    elif hair in ("long", "wild"):
        anchors = [(hx - rx * 0.6, hy - ry * 0.8)]
    else:
        anchors = [(hx - rx * 0.35, hy - ry * 1.08)]
    for bx, by in anchors:
        if kind == "buyao":     # 金步搖：簪頭一串珠子垂下來
            px, py = bx + rx * 0.4, by - ry * 0.05
            cv.stroke([(bx - rx * 0.5, by + 2), (px + 2, py - 2)], 2.2, col, 1.0, taper=(0.1, 0.1))
            cv.paint(cv.ellipse(px, py, 3.4, 3.4, blur=0.3), col, 1.0)
            for k in range(3):
                cv.stroke([(px, py + 3), (px + 1 + k, py + 13 + k * 3)], 0.9, col, 0.9, smooth=0)
                cv.paint(cv.ellipse(px + 1 + k, py + 14 + k * 3, 1.9, 1.9, blur=0.3), (110, 190, 190) if k != 1 else (200, 60, 50), 1.0)
        elif kind == "pin":     # 玉簪：一根長簪斜插，簪頭一顆玉
            a0, a1 = (bx - rx * 0.9, by + ry * 0.12), (bx + rx * 0.7, by - ry * 0.18)
            cv.stroke([a0, a1], 2.6, (226, 230, 220), 1.0, taper=(0.05, 0.3))
            cv.paint(cv.ellipse(a0[0], a0[1], 4, 4, blur=0.3), col, 1.0)
        elif kind == "ribbon":  # 髮帶：結在束髮處，兩條短尾
            cv.stroke([(bx - rx * 0.3, by - ry * 0.12), (bx + rx * 0.25, by + ry * 0.12)], 3.6, col, 1.0, taper=(0.1, 0.1))
        elif kind == "flower":  # 簪花：一朵小花加兩片葉
            cv.paint(cv.ellipse(bx + rx * 0.3, by - ry * 0.05, 5.5, 5.5, blur=0.5), col, 1.0)
            cv.paint(cv.ellipse(bx + rx * 0.3, by - ry * 0.05, 2, 2, blur=0.3), GOLD, 1.0)
            for dx in (-1, 1):
                cv.stroke([(bx + rx * 0.3, by), (bx + rx * (0.3 + dx * 0.35), by + ry * 0.2)], 2.6, (90, 140, 90), 1.0, taper=(0.1, 0.8))


def hair_acc_back(f, a, hair):
    """髮帶的長尾：跟著髮型從束髮處往後甩（在頭後面那一層）。"""
    if a["kind"] != "ribbon":
        return
    col = a.get("color", (176, 46, 40))
    if hair == "high_tail":
        f.line([(-16, 1.07), (-40, 1.1), (-70, 1.06), (-92, .98)], 4, col, 1.0, taper=(0.1, 0.85))
        f.line([(-16, 1.065), (-34, 1.02), (-54, .94), (-62, .86)], 3.4, col, 1.0, taper=(0.1, 0.85))
    elif hair == "ponytail":
        f.line([(-28, .975), (-40, .93), (-58, .9), (-70, .84)], 4, col, 1.0, taper=(0.1, 0.8))
        f.line([(-28, .97), (-36, .9), (-38, .82)], 3, col, 1.0, taper=(0.1, 0.8))
    else:
        f.line([(-14, 1.03), (-36, .98), (-56, .9), (-64, .8)], 4, col, 1.0, taper=(0.1, 0.85))
        f.line([(-14, 1.02), (-28, .94), (-34, .84)], 3.2, col, 1.0, taper=(0.1, 0.85))
