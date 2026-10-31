"""彙整封閉測試的遊玩紀錄（user://playlog.jsonl），輸出 Markdown 報表。

用法：python tools/playlog_report.py 測試者A.jsonl 測試者B.jsonl ... > report.md
每個檔案算一位測試者（用檔名當代號）。

完成率：事件開始後以 complete 結束的比例；fail、abandon 各自列出；
沒有 pack_end 或以 quit 結束的算「中途離開」。
跳過率：所有顯示過的台詞裡，停留時間不到預估閱讀時間 30% 就翻頁的比例。
"""
import json
import sys
from collections import defaultdict
from pathlib import Path


def read(path):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            pass
    return rows


def pct(a, b):
    return f"{a / b:.0%}" if b else "-"


def report(paths):
    packs = defaultdict(lambda: {"title": "", "author": "", "tag": "", "starts": 0, "complete": 0, "fail": 0,
                                 "abandon": 0, "left": 0, "lines": 0, "skipped": 0, "seconds": 0.0, "testers": set()})
    testers, director = [], {"packs": 0, "fails": 0, "rewritten": 0}
    downs = 0
    for path in paths:
        name = Path(path).stem
        rows = read(path)
        open_packs = {}
        sessions = {r["session"] for r in rows}
        play = defaultdict(float)
        tier = ""
        for r in rows:
            play[r["session"]] = max(play[r["session"]], float(r.get("play", 0)))
            ev = r["event"]
            if ev == "pack_start":
                p = packs[r["pack"]]
                p.update(title=r.get("title", ""), author=r.get("author", ""), tag=r.get("request_tag", ""))
                p["starts"] += 1
                p["testers"].add(name)
                open_packs[(r["session"], r["pack"])] = True
            elif ev == "pack_end":
                p = packs[r["pack"]]
                key = r["result"] if r["result"] in ("complete", "fail", "abandon") else "left"
                p[key] += 1
                p["lines"] += r.get("lines", 0)
                p["skipped"] += r.get("skipped", 0)
                p["seconds"] += r.get("seconds", 0)
                director["rewritten"] += r.get("rewritten", 0)
                open_packs.pop((r["session"], r["pack"]), None)
            elif ev == "director_pack":
                director["packs"] += 1
            elif ev == "director_fail":
                director["fails"] += 1
            elif ev == "player_down":
                downs += 1
            elif ev in ("breakthrough", "session_start", "session_end"):
                tier = r.get("tier", tier)
        for (_, pid) in open_packs:
            packs[pid]["left"] += 1
        testers.append((name, len(sessions), sum(play.values()) / 60, tier))

    out = ["# 封閉測試報表", "", f"測試者 {len(testers)} 位。", "", "## 測試者", "",
           "| 代號 | 啟動次數 | 遊玩分鐘 | 最後境界 |", "| --- | --- | --- | --- |"]
    out += [f"| {n} | {s} | {m:.0f} | {t} |" for n, s, m, t in testers]
    total = {k: sum(p[k] for p in packs.values()) for k in ("starts", "complete", "lines", "skipped")}
    out += ["", "## 總覽", "",
            f"- 事件開始 {total['starts']} 次，完成率 {pct(total['complete'], total['starts'])}，台詞跳過率 {pct(total['skipped'], total['lines'])}",
            f"- 導演送來 {director['packs']} 個事件，失敗 {director['fails']} 次；即時改寫台詞 {director['rewritten']} 句",
            f"- 戰鬥倒地 {downs} 次", "",
            "## 各事件", "",
            "| 事件 | 來源 | 測試者 | 開始 | 完成率 | 失敗 | 放棄 | 中途離開 | 跳過率 | 平均秒數 |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for pid, p in sorted(packs.items(), key=lambda kv: -kv[1]["starts"]):
        src = "導演" + (f"（{p['tag']}）" if p["tag"] else "") if p["author"] == "director" else "手寫"
        ended = p["complete"] + p["fail"] + p["abandon"] + p["left"]
        out.append(f"| {p['title'] or pid} | {src} | {len(p['testers'])} | {p['starts']} | {pct(p['complete'], p['starts'])} "
                   f"| {p['fail']} | {p['abandon']} | {p['left']} | {pct(p['skipped'], p['lines'])} "
                   f"| {p['seconds'] / ended:.0f} |" if ended else "| - |")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.stdout.write(report(sys.argv[1:]))
