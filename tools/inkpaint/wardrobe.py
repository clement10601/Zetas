"""玩家換裝用的分層立繪：臉、眼、眉、髮、衣、配件各畫成一張透明圖，遊戲裡依序疊起來（scripts/wardrobe.gd）。

每一層都用同一個 Fig 幾何（身高、站位跟 player.disciple 一樣）去畫，只畫自己那個部位（figures.figure 的 only），
所以任何組合疊起來都對得上。圖會裁掉透明邊，位移寫在 content/wardrobe_layers.json（匯出時要帶，所以放 content/）。

選項的名稱、分類、解鎖條件在 content/wardrobe.json（遊戲讀的）；這裡只管長相。
用法：python tools/paint_art.py --wardrobe
"""
import json
import math
from functools import partial
from pathlib import Path

import numpy as np

from . import figures as F
from .ink import INK, Canvas, chaikin, mix, seed_of

GOLD = F.GOLD
SILVER = (178, 184, 192)
JADE = (104, 178, 178)
HEAD_SCALE = 1.36
TEAL = (30, 110, 120)
VERMILION = (176, 46, 40)

# 疊圖順序（由後往前）。每一層：(圖層名, figure 的部位, 決定這層長相的選項欄位)
ORDER = [
    ("back", "behind", "back"),
    ("hair_back", "hair_back", "hair"),
    ("sleeve_back", "sleeve_back", "outfit"),
    ("gear", "back_items", None),          # 背上的劍：武器另一串在做，先固定
    ("body", "body", "outfit"),
    ("waist", "belt", "waist"),
    ("hair_under", "hair_under", "hair"),
    ("face", "face", "face"),
    ("hair_over", "hair_over", "hair"),     # 瀏海在眼眉下面（跟整張畫時的順序一樣）
    ("eyes", "eyes", "eyes"),
    ("brows", "brows", "brows"),
    ("head", "head_items", "head"),
    ("sleeve_front", "sleeve_front", "outfit"),
    ("shoulder", "shoulder", "shoulder"),     # 肩飾蓋在前袖上
]

# hair_ornament：髻上步搖、馬尾髮帶；head_scale：玩家頭再放大一點（橫軸畫面上角色只有 88px 高，臉與髮型要撐得起來）
BASE = dict(inner=(238, 236, 228), back_items=[F.sword_back], hair_ornament=True, head_scale=HEAD_SCALE)

HAIR_COLORS = {
    "ink": (34, 30, 34),        # 墨黑
    "chestnut": (92, 62, 44),   # 栗褐
    "indigo": (44, 60, 82),     # 青黛
    "frost": (228, 228, 222),   # 霜白
    "crimson": (138, 38, 34),   # 赤霞
}
HAIRS = ["long_bun", "bun", "topknot", "ponytail", "high_tail", "long", "twin", "wild"]
FACES = list(F.FACES)
EYES = ["almond", "phoenix", "gentle"]
BROWS = ["straight", "sword", "willow"]


def brow_color(hc):
    return (172, 172, 168) if hc == HAIR_COLORS["frost"] else hc


# ---------- 新配件 ----------

def weimao(f, hx, hy, rx, ry):
    """帷帽：斗笠沿垂一圈薄紗到肩，臉在紗後若隱若現。"""
    cv = f.cv
    rim_l, rim_r = (hx - rx * 2.3, hy - ry * 0.5), (hx + rx * 2.4, hy - ry * 0.55)
    veil = [rim_l, rim_r, (hx + rx * 2.2, hy + ry * 1.7), (hx + rx * 0.4, hy + ry * 1.95), (hx - rx * 2.1, hy + ry * 1.6)]
    cv.paint(cv.textured(cv.poly(chaikin(veil, 2), 1.0), 1.0, "cloud", lo=0.2), (238, 236, 230), 0.42)
    for k in range(7):
        x = rim_l[0] + (rim_r[0] - rim_l[0]) * (k + 0.5) / 7
        cv.stroke([(x, hy - ry * 0.5), (x + 2, hy + ry * 1.8)], 1.0, INK, 0.18, dry=0.6)
    F.douli(f, hx, hy, rx, ry, color=(160, 132, 86))


def lotus_crown(f, hx, hy, rx, ry):
    """蓮華冠：頭頂一朵白玉蓮，花瓣描淡金。"""
    cv = f.cv
    bx, by = hx - rx * 0.3, hy - ry * 1.12
    for ang in (-1.0, -0.5, 0.0, 0.5, 1.0):
        tip = (bx + math.sin(ang) * rx * 0.62, by - math.cos(ang) * ry * 0.62)
        pts = [(bx - rx * 0.16, by), tip, (bx + rx * 0.16, by)]
        cv.paint(cv.poly(chaikin([(bx - rx * 0.18, by), ((bx + tip[0]) / 2 - rx * 0.12, (by + tip[1]) / 2), tip,
                                   ((bx + tip[0]) / 2 + rx * 0.12, (by + tip[1]) / 2), (bx + rx * 0.18, by)], 2), 0.6), (246, 244, 236), 1.0)
        cv.stroke(pts, 1.3, GOLD, 0.95, smooth=0, taper=(0.05, 0.05))
    cv.stroke([(bx - rx * 0.55, by + 2), (bx + rx * 0.55, by + 2)], 3, GOLD, 1.0, taper=(0.05, 0.05))
    cv.paint(cv.ellipse(bx, by - ry * 0.15, 3, 3, blur=0.5), (120, 200, 210), 1.0)


def demon_mask(f, hx, hy, rx, ry):
    """半面魔紋：墨色半臉面具蓋住眼眉，朱紅紋路從眼角往上燒。"""
    cv = f.cv
    pts = [(hx + rx * 0.05, hy - ry * 0.55), (hx + rx * 0.95, hy - ry * 0.45), (hx + rx * 1.12, hy + ry * 0.05),
           (hx + rx * 0.95, hy + ry * 0.28), (hx + rx * 0.35, hy + ry * 0.24), (hx + rx * 0.02, hy + ry * 0.05)]
    m = cv.poly(chaikin(pts, 2), 0.6)
    cv.paint(m, (26, 20, 24), 0.96)
    cv.stroke(chaikin(pts + pts[:1], 2), 1.6, INK, 0.9, smooth=0, taper=(0.02, 0.02))
    ex, ey = hx + rx * 0.62, hy + ry * 0.02
    cv.paint(cv.ellipse(ex, ey, 4.5, 1.8, blur=0.4), (230, 60, 44), 1.0)
    for k in range(3):
        cv.stroke([(ex - 2 - k * 4, ey - 3), (ex - 6 - k * 5, ey - 10 - k * 2), (ex - 2 - k * 6, ey - 16 - k * 3)], 1.4, (190, 40, 34), 0.9, taper=(0.1, 0.8))


def cloud_ribbon(f):
    """流雲披帛：兩條長綢，月白描淡金，比青玉飄帶更長更飄。"""
    F.ribbon((236, 234, 222), 0.9)(f)
    mid = [(-8, .74), (-46, .7), (-96, .64), (-134, .56), (-150, .42), (-136, .3), (-158, .18), (-176, .1)]
    wid = [0.012, 0.02, 0.026, 0.026, 0.024, 0.022, 0.018, 0.008]
    top = [(x, y + w) for (x, y), w in zip(mid, wid)]
    bot = [(x + 4, y - w) for (x, y), w in reversed(list(zip(mid, wid)))]
    f.fill(top + bot, (214, 228, 232), 1.4, 0.2, 0.85)
    f.line(mid[1:6], 1.2, GOLD, 0.7, dry=0.3)


def ink_cape(f):
    """墨焰披風：肩後一大片墨色披風，下緣燒成朱紅火舌。"""
    pts = [(-12, .86), (-46, .84), (-72, .7), (-92, .42), (-112, .16), (-98, .07), (-80, .13), (-62, .05), (-44, .11), (-30, .32), (-24, .62)]
    f.fill(pts, (30, 24, 28), 2.2, 0.4, 1.0)
    for k, (x, y) in enumerate(((-110, .14), (-96, .07), (-76, .13), (-58, .06), (-42, .11))):
        f.line([(x + 4, y + 0.08), (x - 2, y + 0.02), (x + 3, y - 0.02)], 5, (170, 34, 30), 0.8, taper=(0.2, 0.9))
    f.line([(-30, .8), (-60, .6), (-80, .3)], 1.2, (90, 30, 34), 0.6, dry=0.5)


def jade_pendant(f):
    """白玉佩：腰側一枚圓玉，下垂青色流蘇。"""
    cv = f.cv
    x, y = f.P(18, .545)
    cv.stroke([(x, y - 18), (x, y - 6)], 1.6, (40, 110, 120), 1.0, smooth=0)
    cv.paint(cv.ellipse(x, y, 8, 8, blur=0.5), (232, 236, 226), 1.0)
    cv.stroke([(x - 7, y - 1), (x - 2, y - 7), (x + 6, y - 4), (x + 7, y + 3), (x + 1, y + 8), (x - 6, y + 5), (x - 7, y - 1)], 1.4, INK, 0.8, smooth=0)
    cv.paint(cv.ellipse(x, y, 2.6, 2.6, blur=0.3), (150, 170, 160), 1.0)
    for dx in (-2, 0, 2):
        cv.stroke([(x + dx, y + 8), (x + dx * 1.5, y + 30)], 1.4, (40, 120, 130), 0.9, taper=(0.1, 0.6))


def fox_sachet(f):
    """狐毛香囊：白狐報恩後送的小香囊，白毛滾邊、朱紅繫繩。"""
    cv = f.cv
    x, y = f.P(14, .54)
    cv.stroke([(x, y - 16), (x, y - 4)], 1.8, (180, 40, 36), 1.0, smooth=0)
    cv.paint(cv.poly(chaikin([(x - 7, y - 4), (x + 7, y - 4), (x + 9, y + 10), (x, y + 15), (x - 9, y + 10)], 2), 0.6), (200, 60, 54), 1.0)
    cv.paint(cv.ellipse(x, y - 3, 9, 3.5, blur=1.2), (246, 242, 236), 1.0)
    cv.stroke(chaikin([(x - 7, y - 4), (x + 7, y - 4), (x + 9, y + 10), (x, y + 15), (x - 9, y + 10), (x - 7, y - 4)], 2), 1.2, INK, 0.8, smooth=0)
    cv.stroke([(x, y + 15), (x - 1, y + 28)], 1.4, (180, 40, 36), 0.9, taper=(0.1, 0.7))


def cloud_marks(color):
    """雲紋：袍角幾朵捲雲。"""
    def draw(f):
        cv = f.cv
        for x, fr in ((-36, .2), (6, .14), (40, .22), (-14, .32)):
            cx, cy = f.P(x, fr)
            pts = [(cx + 7 * math.cos(t) * (1 - t / 9), cy + 5 * math.sin(t) * (1 - t / 9)) for t in np.linspace(0, 6.5, 14)]
            cv.stroke(pts, 1.6, color, 0.85, taper=(0.1, 0.4), smooth=1)
            cv.stroke([(cx + 7, cy), (cx + 16, cy + 1)], 1.4, color, 0.7, taper=(0.1, 0.6))
    return draw


def flame_marks(color):
    """焰紋：從下襬往上燒的朱紅火舌。"""
    def draw(f):
        for x in (-44, -20, 6, 30, 52):
            f.line([(x, .09), (x + 6, .16), (x - 2, .22), (x + 4, .3)], 4, color, 0.8, taper=(0.1, 0.95), dry=0.2)
    return draw



# ---------- 肩飾 ----------

def cloud_collar(color=(70, 140, 150), edge=GOLD):
    """雲肩：圍在頸肩的四瓣雲頭，瓣尖垂一點流蘇。"""
    def draw(f):
        lobes = [(-44, .74), (-20, .72), (8, .73), (34, .74)]
        pts = [(-12, .86), (-40, .83)]
        for x, y in lobes:
            pts += [(x - 6, y + .03), (x, y), (x + 8, y + .025)]
        pts += [(44, .8), (14, .855)]
        f.fill(pts, color, 2.0, 0.3, 1.0)
        f.line(pts[1:-1], 2.2, edge, 0.9, dry=0.2)
        for x, y in lobes:  # 每瓣一朵小捲雲
            cx, cy = f.P(x, y + .045)
            f.cv.stroke([(cx - 4, cy + 2), (cx - 4, cy - 3), (cx + 3, cy - 3), (cx + 3, cy + 1)], 1.3, edge, 0.85, smooth=1)
            tx, ty = f.P(x, y - .004)
            f.cv.stroke([(tx, ty), (tx, ty + 12)], 1.4, VERMILION, 0.9, taper=(0.1, 0.6))
    return draw


def pauldron(f):
    """護肩：前肩三片疊甲，皮繩斜綁過胸，劍修、散修的利落感。"""
    f.line([(-30, .82), (8, .7), (40, .62)], 3, (96, 66, 44), 0.95, smooth=1)
    for k in range(3):
        y = .835 - k * .04
        f.fill([(22 + k * 3, y + .015), (52 + k * 4, y), (62 + k * 4, y - .05), (52 + k * 3, y - .06), (26 + k * 2, y - .035)],
               mix((84, 92, 100), (200, 200, 196), k * 0.12), 1.8, 0.35, 1.0)
    cx, cy = f.P(44, .8)
    f.cv.paint(f.cv.ellipse(cx, cy, 3, 3, blur=0.3), GOLD, 1.0)


def fur_collar(f):
    """毛領：頸肩一圈蓬鬆白毛，崑崙雪地的厚氅領子。"""
    cv = f.cv
    for x, y, r in ((-40, .81, 13), (-26, .835, 13), (-8, .845, 12), (12, .835, 12), (30, .815, 13), (44, .79, 11), (-46, .78, 10)):
        cx, cy = f.P(x, y)
        cv.paint(cv.ellipse(cx, cy + 2, r, r * 0.8, blur=2.0), (180, 176, 168), 1.0)
        cv.paint(cv.textured(cv.ellipse(cx - 1, cy - 1, r * 0.9, r * 0.72, blur=1.5), 0.8, "cloud", lo=0.5), (248, 246, 240), 1.0)
    for x, y in ((-36, .8), (-6, .825), (24, .805), (42, .78), (-18, .84), (8, .83)):
        f.line([(x, y + .02), (x + 4, y - .015)], 1.2, INK, 0.5, dry=0.6)


# 每套都照同一組「熱門仙俠造型」的層次去配（docs/design/character-style.md）：
# 內襯＋袍＋外罩三層明度、寬腰封＋長垂帶當視覺中心、袖口與衣緣鑲邊、一個強調色。
OUTFITS = {
    # 月白弟子袍：月白長袍外罩天青半臂，青腰封、白玉色回紋鑲邊——原本的主角，層次加滿
    "disciple": dict(robe=(240, 238, 230), trim=TEAL, sash=TEAL, collar=TEAL, cuff=TEAL,
                     overcoat=dict(color=(150, 194, 200), trim=TEAL, length=.36, sleeve="half", slit=True),
                     waist_wrap=dict(color=TEAL, trim=(232, 236, 228), tail=(104, 178, 178), tassel=VERMILION),
                     hem_band=(196, 222, 222), hem_pattern=TEAL, boots=(46, 52, 58)),
    # 外門短褐：短衣長褲、束袖護腕、綁腿，腰間粗布腰封打結
    "outer": dict(robe=(176, 188, 188), inner=(220, 220, 212), trim=(60, 92, 104), sash=(60, 92, 104), sleeve="tight",
                  short_robe=True, pants=(110, 122, 126), cuff=(96, 78, 60), leg_wraps=(214, 206, 188), collar=(60, 92, 104),
                  waist_wrap=dict(color=(60, 92, 104), trim=(214, 206, 188), tail=(60, 92, 104), tail_len=0.6),
                  boots=(60, 50, 42)),
    # 散修布衣：赭長衫開衩、繩腰帶繫葫蘆色流蘇、綁腿長靴，風塵感
    "wanderer": dict(robe=(150, 128, 96), inner=(204, 190, 162), trim=(90, 70, 50), sash=(90, 70, 50), sleeve="tight",
                     cuff=(80, 62, 46), split=True, pants=(96, 86, 72), collar=(110, 86, 60),
                     overcoat=dict(color=(118, 98, 72), trim=(80, 62, 46), length=.5, slit=True),
                     waist_wrap=dict(color=(88, 66, 46), trim=(196, 170, 120), tail=(196, 170, 120), tassel=(186, 140, 60)),
                     boots=(70, 56, 44)),
    # 內門青衫：天青衫、白鑲邊，外罩月白長褙子，銀邊腰封
    "inner": dict(robe=(160, 196, 214), trim=(36, 92, 130), sash=(36, 92, 130), hem_band=(232, 236, 232), hem_pattern=(36, 92, 130),
                  collar=(232, 236, 232), cuff=(232, 236, 232),
                  overcoat=dict(color=(236, 240, 238), trim=(36, 92, 130), length=.22, sleeve="half", slit=True),
                  waist_wrap=dict(color=(36, 92, 130), trim=SILVER, tail=(232, 236, 232), tassel=(104, 178, 178)),
                  boots=(40, 50, 62)),
    # 雲紋道袍：深青道袍罩金邊大氅、廣袖金緣，金腰封
    "cloud_daoist": dict(robe=(66, 84, 108), inner=(226, 222, 210), trim=GOLD, sash=GOLD, hem_band=(42, 56, 76), flare=1.08,
                         robe_marks=[cloud_marks((206, 176, 100))], collar=GOLD, cuff=GOLD, hem_pattern=GOLD,
                         overcoat=dict(color=(44, 58, 78), trim=GOLD, length=.1, sleeve="long", flare=1.12,
                                       marks=[cloud_marks((206, 176, 100))]),
                         waist_wrap=dict(color=GOLD, trim=(66, 84, 108), tail=(206, 176, 100), tassel=VERMILION)),
    # 照影墨衣：墨色勁裝、朱紅內襯開衩、護腕、朱紅長垂帶
    "mirror": dict(robe=(40, 38, 44), inner=(96, 32, 36), trim=(156, 34, 36), sash=(156, 34, 36), sleeve="tight",
                   shoes=(20, 18, 20), split=True, pants=(96, 32, 36), cuff=(70, 64, 72), collar=(156, 34, 36),
                   waist_wrap=dict(color=(30, 28, 32), trim=(156, 34, 36), tail=(156, 34, 36), tail_len=1.3),
                   boots=(24, 22, 26)),
    # 流雲仙裳：月白仙裳、三層天青薄紗下襬、淡金腰封與長垂帶
    "xian": dict(robe=(248, 246, 238), inner=(214, 232, 236), trim=(204, 172, 98), sash=(204, 172, 98), hem_band=(180, 210, 222),
                 flare=1.18, robe_marks=[cloud_marks((150, 190, 206))], collar=(204, 172, 98), cuff=(180, 210, 222),
                 skirt_layers=[(214, 232, 236), (190, 218, 228), (170, 204, 220)],
                 waist_wrap=dict(color=(204, 172, 98), trim=(248, 246, 238), tail=(214, 232, 236), tail_len=1.4, tassel=(120, 200, 210))),
    # 墨焰魔袍：墨袍外罩焰紋大氅、朱紅寬領、朱紅腰封
    "mo": dict(robe=(30, 24, 28), inner=(124, 22, 28), trim=(176, 32, 30), sash=(176, 32, 30), hem_band=(70, 18, 22), flare=1.1,
               robe_marks=[flame_marks((196, 40, 32))], shoes=(16, 12, 14), collar=(176, 32, 30), cuff=(176, 32, 30),
               overcoat=dict(color=(20, 16, 18), trim=(176, 32, 30), length=.08, sleeve="long", flare=1.15,
                             marks=[flame_marks((196, 40, 32))]),
               waist_wrap=dict(color=(176, 32, 30), trim=GOLD, tail=(124, 22, 28), tail_len=1.2),
               boots=(20, 16, 18)),
    # 青雲劍裝（新）：劍修勁裝，窄袖護腕、前開衩長擺、天青腰封長垂帶——青雲宗的戰鬥服
    "sword": dict(robe=(214, 230, 232), inner=(240, 238, 230), trim=TEAL, sash=TEAL, sleeve="tight", split=True,
                  pants=(54, 74, 84), cuff=(54, 74, 84), collar=TEAL, hem_band=TEAL, hem_pattern=(232, 236, 228),
                  waist_wrap=dict(color=(54, 74, 84), trim=(104, 178, 178), tail=TEAL, tail_len=1.3, tassel=(240, 238, 230)),
                  boots=(40, 46, 52)),
}

HEADWEAR = {
    "crown": partial(F.crown, color=SILVER),
    "headband": partial(F.headband, color=(30, 110, 120)),
    "weimao": weimao,
    "lotus_crown": lotus_crown,
    "demon_mask": demon_mask,
}
BACKS = {
    "ribbon_jade": F.ribbon(JADE),
    "ribbon_cloud": cloud_ribbon,
    "ink_cape": ink_cape,
}
SHOULDERS = {
    "cloud_collar": cloud_collar(),
    "pauldron": pauldron,
    "fur_collar": fur_collar,
}
WAISTS = {
    "gourd": F.gourd,
    "jade_pendant": jade_pendant,
    "talismans": partial(F.talismans, n=2),
    "fox_sachet": fox_sachet,
}


def jobs():
    """圖層 key -> (部位, spec)。key 就是 wardrobe_layers.json 的鍵，也是 wardrobe.gd 組 key 的規則。"""
    out = {"gear": ("back_items", {})}
    for fid in FACES:
        out[f"face/{fid}"] = ("face", {"face": fid})
    for eid in EYES:
        out[f"eyes/{eid}"] = ("eyes", {"eye_style": eid})
    for bid in BROWS:
        for cid, c in HAIR_COLORS.items():
            out[f"brows/{bid}/{cid}"] = ("brows", {"brow_style": bid, "brow_color": brow_color(c)})
    for hid in HAIRS:
        for cid, c in HAIR_COLORS.items():
            for part in ("hair_back", "hair_under", "hair_over"):
                out[f"{part}/{hid}/{cid}"] = (part, {"hair": hid, "hair_color": c})
    for oid, o in OUTFITS.items():
        for part in ("sleeve_back", "body", "sleeve_front"):
            out[f"{part}/{oid}"] = (part, o)
    for hid, fn in HEADWEAR.items():
        out[f"head/{hid}"] = ("head_items", {"head_items": [fn]})
    for bid, fn in BACKS.items():
        out[f"back/{bid}"] = ("behind", {"behind": [fn]})
    for wid, fn in WAISTS.items():
        out[f"waist/{wid}"] = ("belt", {"belt": [fn]})
    for sid, fn in SHOULDERS.items():
        out[f"shoulder/{sid}"] = ("shoulder", {"shoulder_items": [fn]})
    return out


def render_layer(key, part, extra):
    spec = dict(BASE, **extra)
    spec["only"] = {part}
    cv = Canvas(F.W, F.H, seed_of(f"wardrobe:{key}"))
    F.figure(cv, spec)
    return cv.image()


def crop(img):
    """裁掉透明邊；整張透明（例如短髮沒有後髮）回傳 None。"""
    box = img.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox()
    if box is None:
        return None, None
    return img.crop(box), box[:2]


def paint_all(art_root: Path, only=None):
    out_dir = art_root / "wardrobe"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"size": [F.W, F.H], "layers": {}}
    for key, (part, extra) in jobs().items():
        if only and not any(key.startswith(p) for p in only):
            continue
        img, pos = crop(render_layer(key, part, extra))
        if img is None:
            continue
        rel = "wardrobe/" + key.replace("/", "__") + ".png"
        img.save(art_root / rel, optimize=True)
        manifest["layers"][key] = {"file": rel, "x": pos[0], "y": pos[1]}
    manifest_path = art_root.parent / "content/wardrobe_layers.json"
    if only:
        old_path = manifest_path
        if old_path.exists():
            old = json.loads(old_path.read_text(encoding="utf-8"))
            old["layers"].update(manifest["layers"])
            manifest = old
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    # 主角的整張立繪（沒載入外觀前、心魔鏡像等地方用）＝預設外觀疊出來的樣子，兩邊才不會長得不一樣
    catalog = json.loads((art_root.parent / "content/wardrobe.json").read_text(encoding="utf-8"))
    compose(art_root, catalog["default"]).save(art_root / "sprites/player.disciple.png", optimize=True)
    return manifest


def compose(art_root: Path, look: dict):
    """照 wardrobe.gd 的規則把一套外觀疊成一張圖（總覽圖與測試用）。"""
    from PIL import Image
    manifest = json.loads((art_root.parent / "content/wardrobe_layers.json").read_text(encoding="utf-8"))
    canvas = Image.new("RGBA", tuple(manifest["size"]), (0, 0, 0, 0))
    for key in layer_keys(look):
        info = manifest["layers"].get(key)
        if info:
            layer = Image.open(art_root / info["file"]).convert("RGBA")
            canvas.alpha_composite(layer, (info["x"], info["y"]))
    return canvas


def layer_keys(look):
    keys = []
    for name, _part, field in ORDER:
        if field is None:
            keys.append(name)
        elif field in ("hair",):
            keys.append(f"{name}/{look['hair']}/{look['hair_color']}")
        elif field == "brows":
            keys.append(f"brows/{look['brows']}/{look['hair_color']}")
        elif field == "outfit":
            keys.append(f"{name}/{look['outfit']}")
        elif look.get(field):
            keys.append(f"{field}/{look[field]}")
    return keys
