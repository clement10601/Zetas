"""野怪立繪（地圖上的野生妖物）。面朝右、腳底貼齊畫布底邊，畫布大小同 figures.W×H。

狌狌、蠱雕取自 content/lore/beasts.json（山海經）；遊魂是民間的孤魂，用人形 figure 畫成半透明。
"""
import math

from . import figures as F
from .figures import FEET, hramp
from .ink import INK, chaikin, mix


def _jag(cv, pts, amp=3, n=9):
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


def _body(cv, pts, color, amp=3):
    p = _jag(cv, pts, amp)
    cv.paint(cv.poly(p, 0.6), color, 1.0)
    cv.paint(cv.textured(hramp(cv.poly(p, 0.6), min(x for x, _ in p), max(x for x, _ in p), 0, 1), 0.6, "cloud"), mix(color, INK, 0.5), 0.35)
    cv.stroke(p + [p[0]], 2.2, INK, 0.9, dry=0.4, smooth=0, taper=(0.02, 0.02))


def shengsheng(cv):
    """狌狌：像猴而耳白，半蹲半立、長臂垂地，手裡抓著偷來的果子。"""
    fur, face, dark, white = (122, 92, 64), (214, 176, 140), (70, 52, 38), (238, 234, 224)
    cx = 170
    # 尾巴高高捲起
    tail = chaikin([(cx - 40, 330), (cx - 100, 320), (cx - 130, 250), (cx - 104, 200), (cx - 76, 214)], 3)
    cv.stroke(tail, 14, fur, 1.0, taper=(0.2, 0.8), jitter=0.3, dry=0.25)
    cv.stroke(tail, 1.6, INK, 0.7, taper=(0.2, 0.8))
    # 後腿（蹲）
    _body(cv, [(cx - 50, 330), (cx - 10, 340), (cx, 400), (cx + 10, 474), (cx - 30, 474), (cx - 40, 410), (cx - 70, 380)], dark)
    _body(cv, [(cx - 6, 330), (cx + 40, 350), (cx + 40, 410), (cx + 60, 474), (cx + 22, 474), (cx + 10, 410), (cx - 16, 380)], fur)
    # 軀幹，駝背前傾
    _body(cv, [(cx - 60, 340), (cx - 56, 250), (cx - 20, 190), (cx + 40, 180), (cx + 70, 220), (cx + 60, 300), (cx + 30, 350)], fur, 4)
    cv.paint(cv.poly(chaikin([(cx + 10, 230), (cx + 54, 236), (cx + 46, 310), (cx + 14, 320)], 2), 2), face, 0.55)
    # 後臂垂地
    _body(cv, [(cx - 10, 210), (cx - 40, 280), (cx - 44, 380), (cx - 30, 440), (cx - 12, 440), (cx - 20, 380), (cx - 10, 290), (cx + 10, 230)], dark)
    # 頭：猴臉、白耳
    hx, hy = cx + 70, 170
    _body(cv, [(hx - 46, hy + 10), (hx - 40, hy - 40), (hx - 10, hy - 60), (hx + 26, hy - 54), (hx + 46, hy - 24), (hx + 44, hy + 16), (hx + 10, hy + 34), (hx - 30, hy + 30)], fur, 3)
    cv.paint(cv.poly(chaikin([(hx - 6, hy - 34), (hx + 36, hy - 30), (hx + 42, hy + 8), (hx + 14, hy + 26), (hx - 8, hy + 8)], 2), 1), face, 1.0)
    for ex, ey in ((hx - 34, hy - 30), (hx + 4, hy - 64)):
        cv.paint(cv.ellipse(ex, ey, 13, 17, angle=-0.4), white, 1.0)
        cv.stroke(chaikin([(ex - 12, ey), (ex - 4, ey - 17), (ex + 10, ey - 6)], 2), 1.6, INK, 0.8)
    cv.paint(cv.ellipse(hx + 18, hy - 14, 4, 4), INK, 1.0)
    cv.paint(cv.ellipse(hx + 19, hy - 15, 1.4, 1.4), (255, 220, 120), 1.0)
    cv.stroke([(hx + 14, hy + 10), (hx + 34, hy + 6)], 2, INK, 0.9)
    # 前臂伸出、抓果子
    _body(cv, [(cx + 40, 220), (cx + 90, 250), (cx + 130, 290), (cx + 140, 310), (cx + 120, 318), (cx + 80, 290), (cx + 34, 260)], fur)
    cv.paint(cv.ellipse(cx + 146, 314, 12, 11), (196, 58, 44), 1.0)
    cv.stroke([(cx + 146, 302), (cx + 150, 294)], 2, (60, 90, 50), 1.0)


def gudiao(cv):
    """蠱雕：像鵰而頭上有角，雙翼半張、爪踞地，鳴聲如嬰兒。"""
    feather, light, dark = (88, 80, 70), (170, 156, 130), (40, 36, 32)
    cx = 168
    # 後翼
    _body(cv, [(cx - 10, 200), (cx - 90, 120), (cx - 160, 110), (cx - 150, 160), (cx - 170, 200), (cx - 130, 230), (cx - 150, 270), (cx - 80, 280), (cx - 20, 270)], dark, 5)
    for k in range(5):
        x = cx - 150 + k * 26
        cv.stroke([(x, 160 + k * 8), (x + 10, 250 - k * 4)], 1.4, INK, 0.5, dry=0.6)
    # 尾羽
    _body(cv, [(cx - 50, 330), (cx - 120, 380), (cx - 140, 420), (cx - 100, 410), (cx - 40, 370)], feather, 4)
    # 腿與爪
    for lx in (cx - 10, cx + 30):
        cv.stroke([(lx, 360), (lx + 4, 430), (lx + 2, FEET - 6)], 9, (190, 150, 70), 1.0, taper=(0.1, 0.1))
        for d in (-18, 0, 18):
            cv.stroke([(lx + 2, FEET - 6), (lx + 2 + d, FEET)], 3, INK, 1.0, taper=(0.1, 0.8))
    # 軀幹
    _body(cv, [(cx - 60, 350), (cx - 50, 250), (cx - 10, 200), (cx + 50, 190), (cx + 76, 240), (cx + 60, 330), (cx + 10, 370)], feather, 4)
    cv.paint(cv.poly(chaikin([(cx + 10, 230), (cx + 60, 240), (cx + 50, 330), (cx + 10, 350)], 2), 2), light, 0.75)
    for k in range(4):
        y = 250 + k * 22
        cv.stroke([(cx + 18, y), (cx + 30, y + 6), (cx + 44, y)], 1.4, INK, 0.55)
    # 前翼半張
    _body(cv, [(cx + 10, 220), (cx - 20, 160), (cx - 30, 90), (cx + 10, 60), (cx + 30, 110), (cx + 50, 170), (cx + 40, 230)], feather, 5)
    for k in range(4):
        cv.stroke([(cx - 20 + k * 10, 100 + k * 10), (cx - 4 + k * 12, 200)], 1.4, INK, 0.5, dry=0.6)
    # 頭、鉤喙、角
    hx, hy = cx + 80, 160
    _body(cv, [(hx - 40, hy + 40), (hx - 34, hy - 6), (hx - 6, hy - 26), (hx + 26, hy - 20), (hx + 40, hy), (hx + 24, hy + 26), (hx - 6, hy + 46)], light, 3)
    cv.paint(cv.poly([(hx + 34, hy - 6), (hx + 66, hy + 4), (hx + 62, hy + 22), (hx + 46, hy + 14), (hx + 30, hy + 12)], 0.5), (200, 160, 60), 1.0)
    cv.stroke([(hx + 34, hy - 6), (hx + 66, hy + 4), (hx + 58, hy + 24)], 2, INK, 0.9, smooth=0)
    cv.stroke(chaikin([(hx - 10, hy - 22), (hx - 18, hy - 58), (hx - 4, hy - 86)], 3), 9, (60, 50, 44), 1.0, taper=(0.1, 1.0))
    cv.paint(cv.ellipse(hx + 14, hy - 4, 6, 5, blur=3), (255, 120, 30), 0.9)
    cv.paint(cv.ellipse(hx + 15, hy - 4, 2.5, 2.5), INK, 1.0)


GHOST = dict(robe=(150, 176, 160), inner=(190, 206, 196), sash=(90, 110, 100), trim=(90, 110, 100), hair="long",
             ink=(60, 80, 70), hair_color=(50, 64, 58), skin=(200, 214, 206), sleeve="wide", pose="forward", lean=0.25,
             behind=[F.aura((120, 210, 170), 120, 210, 0.4)], front=[F.smoke((40, 70, 60), 0.6, 0.2)])


def wandering_ghost(cv):
    """遊魂：荒廟夜裡飄出的孤魂，青綠半透明、披髮前伸雙手，腳下散成霧。"""
    F.figure(cv, GHOST)
    F.fade_bottom(cv, 0.42, 0.9)
    cv.prgb *= 0.85
    cv.a *= 0.82
