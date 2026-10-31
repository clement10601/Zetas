"""每個角色模板的立繪設定。同一模板多張就是變體（檔名 _a、_b…，見 content/assets.json）。"""
from functools import partial

from . import figures as F
from .ink import Canvas, seed_of

QING = (176, 196, 204)      # 青雲宗服色：月白帶青
QING_TRIM = (54, 86, 112)


def disciple(robe=QING, trim=QING_TRIM, hair="bun", **kw):
    return dict(robe=robe, inner=(238, 236, 228), sash=trim, trim=trim, hair=hair, back_items=[F.sword_back], **kw)


SPECS = {
    # 玩家本人：月白袍的青雲宗弟子，心魔是他的墨色鏡像
    "player.disciple": [disciple(robe=(232, 230, 220), hair="long_bun")],
    "npc.fellow_disciple": [
        disciple(),
        disciple(hair="long_bun", pin=(150, 40, 40)),
        disciple(robe=(200, 210, 212), hair="ponytail", height=410, pose="clasp"),
    ],
    "npc.sect_master": [
        dict(robe=(70, 86, 104), inner=(226, 222, 210), sash=(196, 160, 80), trim=(196, 160, 80), hair="topknot",
             hair_color=(236, 236, 230), head_items=[F.crown, F.beard, F.white_brows], front=[F.whisk], height=440, girth=1.08),
    ],
    "npc.fox_girl": [
        dict(robe=(240, 236, 228), inner=(200, 60, 60), sash=(190, 50, 50), trim=(190, 50, 50), hair="long", hair_color=(70, 50, 44),
             head_items=[F.fox_ears], behind=[F.fox_tails(3)], front=[F.foxfire], height=405, flare=0.9, pose="clasp", dx=20),
    ],
    "npc.memory_echo": [
        dict(robe=(190, 210, 226), inner=(220, 230, 236), sash=(120, 150, 180), trim=(120, 150, 180), hair="long_bun",
             ink=(90, 110, 130), hair_color=(80, 96, 116), skin=(226, 230, 236), pose="clasp", behind=[F.aura((170, 210, 240), 110, 200, 0.35)]),
    ],
    "npc.villager": [
        dict(robe=(150, 128, 96), inner=(200, 186, 160), sash=(90, 70, 50), trim=(90, 70, 50), hair="topknot", sleeve="tight",
             short_robe=True, pants=(110, 96, 76), height=400, front=[F.basket]),
        dict(robe=(120, 140, 120), inner=(200, 190, 170), sash=(160, 70, 60), trim=(160, 70, 60), hair="bun", sleeve="tight",
             height=390, head_items=[F.scarf_hood], pose="clasp"),
        dict(robe=(130, 110, 90), inner=(190, 180, 160), sash=(70, 60, 50), trim=(70, 60, 50), hair="topknot", hair_color=(200, 200, 196),
             sleeve="tight", height=380, lean=0.15, head_items=[F.beard], front=[partial(F.staff, top=None)]),
    ],
    "npc.cultivator": [
        dict(robe=(120, 100, 140), inner=(230, 226, 220), sash=(196, 160, 80), trim=(196, 160, 80), hair="topknot",
             head_items=[F.crown], back_items=[F.sword_back], belt=[F.gourd]),
        dict(robe=(214, 206, 186), inner=(150, 60, 50), sash=(150, 60, 50), trim=(150, 60, 50), hair="long_bun", pin=(80, 140, 150),
             pose="clasp", height=415),
        dict(robe=(80, 100, 90), inner=(220, 218, 206), sash=(40, 40, 40), trim=(40, 40, 40), hair="long", head_items=[F.beard],
             front=[partial(F.staff, color=(90, 70, 50))], belt=[F.gourd]),
    ],
    "npc.merchant": [
        dict(robe=(160, 120, 70), inner=(220, 206, 176), sash=(100, 60, 40), trim=(100, 60, 40), hair="topknot", sleeve="tight",
             short_robe=True, pants=(110, 90, 66), head_items=[F.douli], back_items=[F.book_box], lean=0.12, height=410),
        dict(robe=(110, 120, 90), inner=(210, 200, 176), sash=(140, 50, 40), trim=(140, 50, 40), hair="bun", sleeve="tight",
             pose="clasp", head_items=[F.headband], front=[F.basket], belt=[F.gourd], height=405),
    ],
    "npc.generic": [
        dict(robe=(170, 164, 150), inner=(220, 214, 200), sash=(90, 80, 70), trim=(90, 80, 70), hair="topknot"),
    ],
    "mob.bandit": [
        dict(robe=(110, 86, 62), inner=(150, 130, 100), sash=(150, 40, 36), trim=(60, 40, 30), hair="topknot", sleeve="tight",
             short_robe=True, pants=(70, 60, 50), head_items=[F.headband], lean=0.35, pose="forward",
             front=[partial(F.blade, length=120, angle=-0.6, width=12, color=(170, 170, 174), curve=10)]),
        dict(robe=(80, 76, 70), inner=(130, 120, 106), sash=(40, 36, 32), trim=(40, 36, 32), hair="long", sleeve="tight",
             short_robe=True, pants=(60, 56, 52), head_items=[F.beard], lean=0.3, pose="forward", girth=1.15,
             front=[partial(F.blade, length=130, angle=-0.2, width=13, color=(160, 160, 164), curve=14)]),
    ],
    "mob.demon_hunter": [
        dict(robe=(46, 50, 58), inner=(90, 90, 96), sash=(150, 30, 30), trim=(150, 30, 30), hair="topknot", sleeve="tight",
             head_items=[F.douli], belt=[F.talismans], lean=0.28, pose="forward", back_items=[F.sword_back], front=[F.chain]),
    ],
    "mob.generic": [
        dict(robe=(70, 60, 60), inner=(110, 96, 90), sash=(150, 40, 36), trim=(150, 40, 36), hair="long", sleeve="tight",
             short_robe=True, pants=(50, 46, 44), lean=0.3, pose="forward",
             front=[partial(F.blade, length=130, angle=-0.35, width=8, color=(180, 184, 190))]),
    ],
    "boss.heart_demon_mirror": [
        dict(robe=(30, 26, 30), inner=(70, 16, 22), sash=(160, 26, 30), trim=(160, 26, 30), hair="long_bun", hair_color=(12, 10, 12),
             skin=(150, 140, 146), ink=(10, 8, 10), glow_eyes=(255, 40, 30), pin=(160, 26, 30), lean=0.2, pose="forward",
             behind=[F.aura((200, 20, 30), 130, 230, 0.55)], back_items=[F.sword_back],
             front=[partial(F.blade, length=150, angle=-0.3, width=7, color=(60, 20, 24), glow=(255, 40, 40)), F.smoke((20, 6, 10), 0.85, 0.22)]),
    ],
}

SPECIAL = {"mob.wolf_demon": F.wolf_demon, "boss.demon_lord": F.demon_lord}



def files_for(aid):
    n = len(SPECS[aid]) if aid in SPECS else 1
    if n == 1:
        return [f"sprites/{aid}.png"]
    return [f"sprites/{aid}_{chr(97 + i)}.png" for i in range(n)]


def render(aid, index=0, spec=None):
    cv = Canvas(F.W, F.H, seed_of(f"{aid}#{index}"))
    if aid in SPECIAL:
        SPECIAL[aid](cv)
    else:
        spec = spec or SPECS[aid][index]
        F.figure(cv, spec)
        if aid == "npc.memory_echo":
            F.fade_bottom(cv, 0.5, 0.97)
            cv.prgb *= 0.8
            cv.a *= 0.8
    return cv.image()
