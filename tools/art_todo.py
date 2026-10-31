"""列出還沒有圖的素材，依出場次數排序，寫到 art/TODO.md。

用法（在 repo 根目錄）：python tools/art_todo.py
出場次數只算手寫內容包；導演生成的事件也會用同一批模板與區塊。
"""
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def main():
    manifest = load("content/assets.json")
    art_root = ROOT / manifest["root"].removeprefix("res://")
    actors, chunks = load("content/actors.json"), load("content/chunks.json")
    uses = Counter()
    for f in sorted((ROOT / "content" / "packs").glob("*.json")):
        pack = json.loads(f.read_text(encoding="utf-8"))
        uses.update(a["template"] for a in pack.get("actors", []))
        uses.update(c["chunk"] for c in pack.get("map", {}).get("chunks", []))
    for r in load("content/regions.json").values():
        if isinstance(r, dict):
            uses.update(r.get("home", []))

    rows = []
    for aid, info in manifest["assets"].items():
        if any((art_root / f).exists() for f in info.get("files", [])):
            continue
        src = actors.get(aid) or chunks.get(aid) or {}
        desc = src.get("description") or ", ".join(src.get("tags", []))
        size = {"sprite": f"高 {info.get('height')}（畫布 480）", "chunk": f"{src.get('width', '?')}×600"}.get(info["type"], "可重複鋪")
        rows.append((-uses[aid], aid, info["type"], src.get("name", ""), desc, size, info["files"][0]))
    rows.sort()
    lines = ["# 美術待辦", "", "由 `python tools/art_todo.py` 產生，規格見 [STYLE.md](STYLE.md)。出場次數越多越先做。",
             "程式畫的水墨版本用 `python tools/paint_art.py` 補上；清單是空的代表每個素材至少有一張圖。", "",
             "| 出場 | 素材 id | 類型 | 名稱 | 說明 | 尺寸 | 檔案 |", "| --- | --- | --- | --- | --- | --- | --- |"]
    lines += [f"| {-u} | `{aid}` | {t} | {n} | {d} | {s} | `{f}` |" for u, aid, t, n, d, s, f in rows]
    (ROOT / "art" / "TODO.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(rows)} assets missing -> art/TODO.md")


if __name__ == "__main__":
    main()
