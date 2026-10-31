"""典籍知識庫（content/lore/）的檢查與查詢。

  python tools/lore.py check                      # 格式、出處、引用、卦象一致性
  python tools/lore.py find --region region.qingyun_foothills --tier 築基
  python tools/lore.py find --tag 狐 --text 化形
  python tools/lore.py prompt --region region.heifeng_ridge --tier 築基 -k 6

prompt 印出給導演用的參考段落：依地區、境界、緣分、標籤挑出最相關的幾筆，附原文與出處。
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LORE = ROOT / "content" / "lore"
KINDS = {"beast", "plant", "god", "place", "realm", "concept", "trigram", "hexagram",
         "faction", "myth", "immortal"}
FATES = {"xian", "mo", "fo"}
# 常見簡體字。只查我們自己寫的文字（name、summary、hooks.idea），不查古籍引文
SIMPLIFIED = set("们这说时为么后发个来对会过还没门东车长马龙鸟鱼见头气灵剑贝听岁闻两谁问间开关难")


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load(lore_dir=LORE):
    """回傳 (sources, entries)。entries 以 id 為鍵，並記下來源檔名。"""
    sources = {k: v for k, v in load_json(lore_dir / "sources.json").items() if not k.startswith("_")}
    entries = {}
    dupes = []
    for path in sorted(lore_dir.glob("*.json")):
        if path.name == "sources.json":
            continue
        for key, entry in load_json(path).items():
            if key.startswith("_"):
                continue
            if key in entries:
                dupes.append(key)
            entries[key] = dict(entry, _file=path.name)
    return sources, entries, dupes


def game_data():
    ruleset = load_json(ROOT / "content" / "ruleset.json")
    regions = [k for k in load_json(ROOT / "content" / "regions.json") if not k.startswith("_")]
    actors = [k for k in load_json(ROOT / "content" / "actors.json") if not k.startswith("_")]
    return ruleset["tiers"], set(regions), set(actors)


def check(lore_dir=LORE):
    sources, entries, dupes = load(lore_dir)
    tiers, regions, actors = game_data()
    errors = [f"{k}: id 重複" for k in dupes]

    for sid, src in sources.items():
        for field in ("title", "era", "author", "text_url"):
            if not src.get(field):
                errors.append(f"{sid}: 缺 {field}")

    for key, e in entries.items():
        where = f"{e['_file']} {key}"
        if not key.startswith("lore."):
            errors.append(f"{where}: id 要以 lore. 開頭")
        for field in ("name", "kind", "summary"):
            if not e.get(field):
                errors.append(f"{where}: 缺 {field}")
        if e.get("kind") not in KINDS:
            errors.append(f"{where}: kind {e.get('kind')!r} 不在 {sorted(KINDS)}")
        if not e.get("tags"):
            errors.append(f"{where}: 至少要一個 tag")

        quote, basis = e.get("quote"), e.get("basis")
        if not quote and not basis:
            errors.append(f"{where}: 要有 quote（原文）或 basis（根據）")
        for label, ref in (("quote", quote), ("basis", basis)):
            if ref and ref.get("source") not in sources:
                errors.append(f"{where}: {label}.source {ref.get('source')!r} 不在 sources.json")
        if quote:
            if not quote.get("text"):
                errors.append(f"{where}: quote.text 是空的")
            if not isinstance(quote.get("verified"), bool):
                errors.append(f"{where}: quote.verified 要寫 true 或 false")
            elif quote["verified"]:
                checked = sources.get(quote.get("source"), {}).get("checked", {})
                if quote.get("chapter") not in checked:
                    errors.append(f"{where}: 標為已核對，但 {quote.get('source')} 的 checked 沒有篇章 {quote.get('chapter')!r}")
        if basis and not basis.get("note"):
            errors.append(f"{where}: basis.note 是空的")

        hooks = e.get("hooks", {})
        for r in hooks.get("regions", []):
            if r not in regions:
                errors.append(f"{where}: 地區 {r} 不在 content/regions.json（規劃中的請放 planned_regions）")
        for r in hooks.get("planned_regions", []):
            if not r.startswith("region."):
                errors.append(f"{where}: planned_regions {r} 要以 region. 開頭")
        for field in ("tier_min",):
            if field in hooks and hooks[field] not in tiers:
                errors.append(f"{where}: {field} {hooks[field]} 不在 ruleset 的境界")
        if "fate" in hooks and hooks["fate"] not in FATES:
            errors.append(f"{where}: fate 要是 {sorted(FATES)}")
        if "actor" in hooks and hooks["actor"] not in actors:
            errors.append(f"{where}: actor {hooks['actor']} 不在 content/actors.json")

        own_text = e.get("name", "") + e.get("summary", "") + hooks.get("idea", "")
        bad = sorted({c for c in own_text if c in SIMPLIFIED})
        if bad:
            errors.append(f"{where}: 有簡體字 {''.join(bad)}")

    errors += check_realms(entries, tiers)
    errors += check_yijing(entries)
    return errors


def check_realms(entries, tiers):
    covered = [e.get("tier") for e in entries.values() if e.get("kind") == "realm"]
    errors = [f"境界 {t} 沒有 realm 條目" for t in tiers if t not in covered]
    errors += [f"realm 條目的 tier {t} 不在 ruleset" for t in covered if t not in tiers]
    return errors


def flip(lines):
    return lines[::-1]


def complement(lines):
    return "".join("1" if c == "0" else "0" for c in lines)


def check_yijing(entries):
    errors = []
    trigrams = {k: e for k, e in entries.items() if e.get("kind") == "trigram"}
    hexagrams = {k: e for k, e in entries.items() if e.get("kind") == "hexagram"}
    if not trigrams and not hexagrams:
        return errors
    lines = [e.get("lines", "") for e in trigrams.values()]
    if len(trigrams) != 8 or len(set(lines)) != 8 or any(len(l) != 3 or set(l) - {"0", "1"} for l in lines):
        errors.append("八卦要剛好 8 個，卦畫是不重複的三位 0/1")
    if len(hexagrams) != 64:
        errors.append(f"六十四卦目前 {len(hexagrams)} 個")
    by_number = {}
    for key, e in hexagrams.items():
        up, lo = trigrams.get(e.get("upper")), trigrams.get(e.get("lower"))
        if not up or not lo:
            errors.append(f"{key}: upper/lower 要指向八卦條目")
            continue
        by_number[e.get("number")] = lo["lines"] + up["lines"]  # 由下往上
    if sorted(by_number) != list(range(1, 65)) and len(hexagrams) == 64:
        errors.append("六十四卦的 number 要是 1～64 各一次")
    if len(set(by_number.values())) != len(by_number):
        errors.append("有兩卦的卦畫相同")
    # 文王卦序：第 2n-1 與第 2n 卦互為顛倒（綜卦）；顛倒後不變的，則互為陰陽相反（錯卦）
    for n in range(1, 65, 2):
        a, b = by_number.get(n), by_number.get(n + 1)
        if not a or not b:
            continue
        expect = complement(a) if flip(a) == a else flip(a)
        if b != expect:
            errors.append(f"第 {n}、{n + 1} 卦不是綜卦或錯卦，上下卦可能填錯")
    return errors


def matches(e, region=None, tier=None, fate=None, tags=(), text=None, tiers=()):
    hooks = e.get("hooks", {})
    if region and region not in hooks.get("regions", []) + hooks.get("planned_regions", []):
        return False
    if tier and hooks.get("tier_min") and tiers.index(hooks["tier_min"]) > tiers.index(tier):
        return False
    if fate and hooks.get("fate") not in (None, fate):
        return False
    if any(t not in e.get("tags", []) for t in tags):
        return False
    if text:
        blob = json.dumps(e, ensure_ascii=False)
        if text not in blob:
            return False
    return True


def score(e, region=None, tier=None, fate=None, tags=()):
    """越相關分數越高：同地區、境界接近、緣分相同、標籤重疊、已核對原文。"""
    hooks = e.get("hooks", {})
    s = 0
    if region and region in hooks.get("regions", []):
        s += 4
    elif region and region in hooks.get("planned_regions", []):
        s += 2
    if fate and hooks.get("fate") == fate:
        s += 2
    s += len(set(tags) & set(e.get("tags", [])))
    if e.get("quote", {}).get("verified"):
        s += 1
    if e.get("kind") in ("beast", "god", "place", "plant"):
        s += 1
    return s


def select(region=None, tier=None, fate=None, tags=(), text=None, k=None, lore_dir=LORE):
    _, entries, _ = load(lore_dir)
    tiers, _, _ = game_data()
    found = [(key, e) for key, e in entries.items()
             if matches(e, region, tier, fate, tags, text, tiers)]
    found.sort(key=lambda kv: (-score(kv[1], region, tier, fate, tags), kv[0]))
    return found[:k] if k else found


def cite(e, sources):
    q = e.get("quote")
    if q:
        title = sources[q["source"]]["title"]
        chapter = f"·{q['chapter']}" if q.get("chapter") else ""
        mark = "" if q.get("verified") else "（未核對）"
        return f"「{q['text']}」——《{title}{chapter}》{mark}"
    b = e["basis"]
    return f"根據《{sources[b['source']]['title']}》：{b['note']}"


def prompt_text(items, lore_dir=LORE):
    sources, _, _ = load(lore_dir)
    lines = ["以下是典籍參考。可以借用名稱、形貌與典故，改編時保留原典的特徵；不要捏造出處。"]
    for key, e in items:
        lines.append(f"- {e['name']}（{key}）：{e['summary']}")
        lines.append(f"  {cite(e, sources)}")
        if e.get("hooks", {}).get("idea"):
            lines.append(f"  用法：{e['hooks']['idea']}")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    for name in ("find", "prompt"):
        p = sub.add_parser(name)
        p.add_argument("--region")
        p.add_argument("--tier")
        p.add_argument("--fate", choices=sorted(FATES))
        p.add_argument("--tag", action="append", default=[])
        p.add_argument("--text")
        p.add_argument("-k", type=int, default=8 if name == "prompt" else None)
    args = ap.parse_args(argv)

    if args.cmd == "check":
        errors = check()
        _, entries, _ = load()
        for err in errors:
            print("ERROR", err)
        verified = sum(1 for e in entries.values() if e.get("quote", {}).get("verified"))
        print(f"{len(entries)} 筆條目，{verified} 筆原文已核對，{len(errors)} 個錯誤")
        return 1 if errors else 0

    items = select(args.region, args.tier, args.fate, args.tag, args.text, args.k)
    if args.cmd == "find":
        for key, e in items:
            print(f"{key}\t{e['name']}\t{e['summary']}")
    else:
        print(prompt_text(items))
    return 0


if __name__ == "__main__":
    sys.exit(main())
