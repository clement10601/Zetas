"""用程式畫出 content/assets.json 列的素材（水墨風，見 art/STYLE.md），寫進 art/。

用法（在 repo 根目錄，需要 numpy、Pillow）：
  python tools/paint_art.py              # 只畫還沒有檔案的素材
  python tools/paint_art.py --all        # 全部重畫
  python tools/paint_art.py npc.fox_girl chunk.sect_gate   # 只畫這幾個
  python tools/paint_art.py --sheet out.png                # 另存一張總覽圖
  python tools/paint_art.py --wardrobe                     # 玩家換裝分層立繪（tools/inkpaint/wardrobe.py）

同一個素材 id 每次畫出同一張圖（亂數種子取自 id）。筆觸工具在 tools/inkpaint/。
手繪或其他來源的圖直接放進 art/ 蓋掉同名檔即可；之後別再用 --all，免得被重畫覆蓋。
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from inkpaint import chunks as C  # noqa: E402
from inkpaint import props as PR  # noqa: E402
from inkpaint import sprites as SP  # noqa: E402


def painters(manifest, chunk_data):
    """素材 id -> [(檔名, 畫圖函式)]，檔名照 assets.json 的 files。"""
    out = {}
    for aid, info in manifest["assets"].items():
        files = info.get("files", [])
        if aid in C.CHUNKS:
            c = chunk_data[aid]
            out[aid] = [(files[0], lambda aid=aid, c=c: C.CHUNKS[aid](aid, c["width"], c["name"]))]
        elif aid in SP.SPECS or aid in SP.SPECIAL:
            n = len(SP.SPECS.get(aid, [None]))
            if len(files) != n:
                raise SystemExit(f"{aid}: assets.json 有 {len(files)} 個檔，inkpaint/sprites.py 有 {n} 個變體")
            out[aid] = [(files[i], lambda aid=aid, i=i: SP.render(aid, i)) for i in range(n)]
        elif aid in PR.PROPS:
            out[aid] = [(files[0], lambda aid=aid: PR.PROPS[aid](aid))]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--all", action="store_true", help="已經有檔案的也重畫")
    ap.add_argument("--sheet", help="另存一張角色與場景的總覽圖")
    ap.add_argument("--wardrobe", action="store_true", help="重畫玩家換裝的分層立繪（art/wardrobe/）")
    args = ap.parse_args()

    manifest = json.loads((ROOT / "content/assets.json").read_text(encoding="utf-8"))
    chunk_data = json.loads((ROOT / "content/chunks.json").read_text(encoding="utf-8"))
    art_root = ROOT / manifest["root"].removeprefix("res://")
    if args.wardrobe:
        from inkpaint import wardrobe as WD
        n = len(WD.paint_all(art_root)["layers"])
        print(f"wardrobe: {n} layers painted")
        return
    jobs = painters(manifest, chunk_data)
    unknown = [a for a in args.ids if a not in jobs]
    if unknown:
        raise SystemExit(f"沒有畫法：{', '.join(unknown)}")
    done = []
    for aid in args.ids or jobs:
        for rel, paint in jobs[aid]:
            path = art_root / rel
            if path.exists() and not (args.all or args.ids):
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            paint().save(path, optimize=True)
            done.append(rel)
            print("painted", rel)
    print(f"{len(done)} files painted")
    if any(r.startswith("chunks/") for r in done):
        from inkpaint import skyline
        skyline.update_all()     # 天空遮罩與天色（content/sky.json）
        print("sky masks updated")
    if args.sheet:
        overview(art_root, manifest, args.sheet)


def overview(art_root, manifest, out):
    from PIL import Image
    sprites = [art_root / f for i in manifest["assets"].values() if i["type"] == "sprite" for f in i["files"]]
    chunks = [art_root / f for i in manifest["assets"].values() if i["type"] == "chunk" for f in i["files"]]
    sprites, chunks = [p for p in sprites if p.exists()], [p for p in chunks if p.exists()]
    cols, sw, sh = 12, 120, 160
    rows = (len(sprites) + cols - 1) // cols
    width, ch = cols * sw, 180
    tiles = []
    for p in chunks:
        im = Image.open(p).convert("RGBA")
        tiles.append(im.resize((int(im.width * ch / im.height), ch), Image.LANCZOS))
    lines, x = [[]], 0
    for t in tiles:
        if x + t.width > width and lines[-1]:
            lines.append([])
            x = 0
        lines[-1].append(t)
        x += t.width
    sheet = Image.new("RGBA", (width, rows * sh + len(lines) * ch), (226, 220, 204, 255))
    for k, p in enumerate(sprites):
        im = Image.open(p).convert("RGBA").resize((sw, sh), Image.LANCZOS)
        sheet.alpha_composite(im, ((k % cols) * sw, (k // cols) * sh))
    for r, line in enumerate(lines):
        x = 0
        for t in line:
            sheet.alpha_composite(t, (x, rows * sh + r * ch))
            x += t.width
    sheet.convert("RGB").save(out)
    print("overview ->", out)


if __name__ == "__main__":
    main()
