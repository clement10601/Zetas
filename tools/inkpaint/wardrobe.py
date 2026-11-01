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
]

BASE = dict(inner=(238, 236, 228), back_items=[F.sword_back])

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


OUTFITS = {
    "disciple": dict(robe=(240, 238, 230), trim=(30, 110, 120), sash=(30, 110, 120)),
    "outer": dict(robe=(176, 188, 188), inner=(220, 220, 212), trim=(60, 92, 104), sash=(60, 92, 104), sleeve="tight",
                  short_robe=True, pants=(110, 122, 126)),
    "wanderer": dict(robe=(150, 128, 96), inner=(204, 190, 162), trim=(90, 70, 50), sash=(90, 70, 50), sleeve="tight"),
    "inner": dict(robe=(160, 196, 214), trim=(36, 92, 130), sash=(36, 92, 130), hem_band=(232, 236, 232)),
    "cloud_daoist": dict(robe=(66, 84, 108), inner=(226, 222, 210), trim=GOLD, sash=GOLD, hem_band=(42, 56, 76), flare=1.08,
                         robe_marks=[cloud_marks((206, 176, 100))]),
    "mirror": dict(robe=(40, 38, 44), inner=(96, 32, 36), trim=(156, 34, 36), sash=(156, 34, 36), sleeve="tight",
                   shoes=(20, 18, 20)),
    "xian": dict(robe=(248, 246, 238), inner=(214, 232, 236), trim=(204, 172, 98), sash=(204, 172, 98), hem_band=(180, 210, 222),
                 flare=1.18, robe_marks=[cloud_marks((150, 190, 206))]),
    "mo": dict(robe=(30, 24, 28), inner=(124, 22, 28), trim=(176, 32, 30), sash=(176, 32, 30), hem_band=(70, 18, 22), flare=1.1,
               robe_marks=[flame_marks((196, 40, 32))], shoes=(16, 12, 14)),
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
