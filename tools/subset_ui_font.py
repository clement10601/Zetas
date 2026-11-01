"""重做 art/fonts/ZetasUI.ttf（遊戲介面與對話字型）：霞鶩文楷 TC Regular 的子集。

留下 Big5 全部字（約 1.3 萬字，導演生成的台詞也幾乎都涵蓋）、ASCII、全形標點，
再加上 content/、scripts/ 裡出現的所有字。網頁版沒有系統中文字型，一定要內建。

用法：
  curl -LO https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/lxgwwenkaitc/LXGWWenKaiTC-Regular.ttf
  pip install fonttools
  python tools/subset_ui_font.py LXGWWenKaiTC-Regular.ttf
"""
import sys
from pathlib import Path

from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent


def big5_chars():
    out = set()
    for hi in range(0xA1, 0xFA):
        for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            try:
                out.add(bytes([hi, lo]).decode("big5"))
            except UnicodeDecodeError:
                pass
    return out


def main(full_font):
    chars = big5_chars() | {chr(c) for c in range(0x20, 0x7F)} | {chr(c) for c in range(0x3000, 0x3040)}
    chars |= {chr(c) for c in range(0xFF00, 0xFFF0)}
    for d in ("content", "scripts", "playtest"):
        for f in (ROOT / d).rglob("*"):
            if f.suffix in (".json", ".gd", ".md", ".txt"):
                chars |= set(f.read_text(encoding="utf-8"))
    text = "".join(sorted(c for c in chars if c.isprintable()))
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    font = subset.load_font(full_font, opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    out = ROOT / "art/fonts/ZetasUI.ttf"
    subset.save_font(font, str(out), opts)
    print(f"{len(font.getBestCmap())} glyphs -> {out.relative_to(ROOT)} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main(sys.argv[1])
