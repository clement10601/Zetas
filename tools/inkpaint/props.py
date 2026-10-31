"""平台、地面、繩梯、牆、寶匣的貼圖。都要能重複鋪：橫的左右接得起來、直的上下接得起來。"""
import math

import numpy as np
from PIL import Image

from .ink import INK, Canvas, seed_of


def tile_x(img, overlap):
    """把右端 overlap 像素淡入左端，再裁掉，得到左右無縫的圖。"""
    a = np.asarray(img, np.float32)
    w = a.shape[1] - overlap
    t = np.linspace(0, 1, overlap)[None, :, None]
    a[:, :overlap] = a[:, w:] * (1 - t) + a[:, :overlap] * t
    return Image.fromarray(a[:, :w].round().astype(np.uint8), "RGBA")


def tile_y(img, overlap):
    return tile_x(img.transpose(Image.Transpose.ROTATE_90), overlap).transpose(Image.Transpose.ROTATE_270)


def platform(aid):
    """木石平台：上緣一道粗墨線（art-direction.md 的墨線平台），下面是木板。"""
    w, h, ov = 288, 18, 32
    cv = Canvas(w, h, seed_of(aid))
    cv.paint(cv.rect(-4, 2, w + 4, h), (92, 70, 48), 1.0)
    cv.paint(cv.textured(cv.rect(-4, 2, w + 4, h), 1.0, "grain", lo=0.45), (60, 44, 30), 0.6)
    for x in range(20, w, 64):
        cv.stroke([(x + cv.rng.uniform(-6, 6), 5), (x + cv.rng.uniform(-6, 6), h)], 1.4, INK, 0.6, smooth=0, dry=0.4)
    cv.stroke([(-6, h - 1.5), (w + 6, h - 1.5)], 2, INK, 0.5, taper=(0.01, 0.01), smooth=0)
    cv.stroke([(-6, 3), (w / 2, 2.4), (w + 6, 3)], 5, INK, 0.95, taper=(0.01, 0.01), dry=0.3)
    return tile_x(cv.image(), ov)


def ground(aid):
    """地面：上緣墨線加草，往下是暗土。"""
    w, h, ov = 544, 160, 32
    cv = Canvas(w, h, seed_of(aid))
    cv.paint(cv.rect(-4, 0, w + 4, h), (44, 40, 34), 1.0)
    cv.paint(cv.textured(cv.rect(-4, 0, w + 4, h), 1.0, "cloud", lo=0.4), (70, 62, 50), 0.6)
    cv.paint(cv.vgrad(cv.rect(-4, 0, w + 4, h), 0, h, 0.0, 1.0), (20, 18, 16), 0.8)
    for _ in range(24):
        x, y = cv.rng.uniform(0, w), cv.rng.uniform(16, h - 10)
        cv.paint(cv.ellipse(x, y, cv.rng.uniform(4, 12), cv.rng.uniform(2, 5)), (90, 84, 72), 0.5)
    cv.stroke([(-6, 2), (w * 0.3, 3), (w * 0.7, 1.5), (w + 6, 2)], 6, INK, 0.95, taper=(0.01, 0.01), dry=0.3)
    return tile_x(cv.image(), ov)


def rope(aid):
    w, h, ov = 12, 80, 16
    cv = Canvas(w, h, seed_of(aid))
    for k in range(-2, 12):
        y = k * 8
        cv.stroke([(2, y), (10, y + 7)], 3.2, (150, 118, 80), 1.0, taper=(0.1, 0.1), smooth=0, dry=0.1)
        cv.stroke([(2, y + 1), (10, y + 8)], 1.0, INK, 0.6, smooth=0)
    return tile_y(cv.image(), ov)


def vine(aid):
    w, h, ov = 40, 112, 16
    cv = Canvas(w, h, seed_of(aid))
    pts = [(20 + 4 * math.sin(y / 14), y) for y in range(-10, h + 10, 4)]
    cv.stroke(pts, 4, (60, 90, 50), 1.0, taper=(0.01, 0.01), dry=0.2)
    for y in range(6, h, 22):
        side = 1 if (y // 22) % 2 else -1
        x = 20 + 4 * math.sin(y / 14)
        leaf = [(x, y), (x + side * 8, y - 6), (x + side * 16, y + 1), (x + side * 8, y + 6)]
        cv.paint(cv.poly(leaf, 0.4), (78, 120, 64), 1.0)
        cv.stroke(leaf + leaf[:1], 1.0, INK, 0.7, smooth=0)
    return tile_y(cv.image(), ov)


def ladder(aid):
    w, h, ov = 28, 54, 18
    cv = Canvas(w, h, seed_of(aid))
    wood = (120, 88, 58)
    for x in (4, 23):
        cv.stroke([(x, -4), (x, h + 4)], 4, wood, 1.0, taper=(0.01, 0.01), smooth=0, dry=0.15)
        cv.stroke([(x - 2, -4), (x - 2, h + 4)], 1.0, INK, 0.7, smooth=0)
    for y in (8, 26, 44):
        cv.stroke([(3, y), (25, y + 1)], 3.4, wood, 1.0, taper=(0.02, 0.02), smooth=0, dry=0.15)
        cv.stroke([(3, y + 1.6), (25, y + 2.6)], 1.0, INK, 0.6, smooth=0)
    return tile_y(cv.image(), ov)


def cliff(aid):
    w, h, ov = 24, 160, 32
    cv = Canvas(w, h, seed_of(aid))
    cv.paint(cv.rect(-2, -2, w + 2, h + 2), (40, 38, 34), 1.0)
    cv.paint(cv.textured(cv.rect(-2, -2, w + 2, h + 2), 1.0, "cloud", lo=0.4), (70, 66, 58), 0.7)
    for _ in range(8):
        y = cv.rng.uniform(0, h)
        cv.stroke([(4, y), (12, y + 10), (16, y + 24)], 1.6, INK, 0.6, dry=0.5)
    return tile_y(cv.image(), ov)


def thin_wall(aid):
    """薄牆（土遁穿得過）：夯土牆，看得出是土。"""
    w, h, ov = 24, 96, 24
    cv = Canvas(w, h, seed_of(aid))
    cv.paint(cv.rect(-2, -2, w + 2, h + 2), (122, 90, 58), 1.0)
    cv.paint(cv.textured(cv.rect(-2, -2, w + 2, h + 2), 1.0, "grain", lo=0.5), (90, 64, 40), 0.7)
    for y in range(0, h + 12, 12):
        cv.stroke([(-2, y), (w + 2, y + 1)], 1.2, (70, 50, 32), 0.8, smooth=0, taper=(0.01, 0.01))
    cv.stroke([(8, 20), (12, 34), (9, 48)], 1.2, INK, 0.6)
    return tile_y(cv.image(), ov)


def cache(aid):
    """寶匣：小木匣，金色包角，透一點光。"""
    w, h = 40, 32
    cv = Canvas(w, h, seed_of(aid))
    cv.paint(cv.ellipse(20, 18, 20, 14, blur=6), (255, 220, 140), 0.4)
    cv.paint(cv.rect(6, 12, 34, 30, blur=0.3), (130, 80, 40), 1.0)
    cv.paint(cv.poly([(5, 13), (35, 13), (33, 6), (7, 6)], 0.3), (150, 96, 50), 1.0)
    for x in (6, 31):
        cv.paint(cv.rect(x, 6, x + 3, 30), (210, 170, 80), 1.0)
    cv.paint(cv.rect(17, 12, 23, 18), (220, 180, 90), 1.0)
    cv.stroke([(6, 30), (6, 12), (34, 12), (34, 30), (6, 30)], 1.6, INK, 0.9, smooth=0, taper=(0.01, 0.01))
    return cv.image()


PROPS = {
    "prop.platform": platform,
    "prop.ground": ground,
    "prop.rope": rope,
    "prop.vine": vine,
    "prop.ladder": ladder,
    "prop.cliff": cliff,
    "prop.thin_wall": thin_wall,
    "prop.cache": cache,
}
