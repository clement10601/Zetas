"""重做 fonts/Zetas-Kai.ttf：只留 inkpaint 程式碼與區塊名稱用到的字。用法見 fonts/README.md。"""
import json
import sys
from pathlib import Path

from fontTools import subset

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def main(full_font):
    chars = set()
    for f in HERE.glob("*.py"):
        chars |= set(f.read_text(encoding="utf-8"))
    for v in json.loads((ROOT / "content/chunks.json").read_text(encoding="utf-8")).values():
        if isinstance(v, dict):
            chars |= set(v.get("name", ""))
    text = "".join(sorted(c for c in chars if ord(c) > 0x2000))
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    font = subset.load_font(full_font, opts)
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    subset.save_font(font, str(HERE / "fonts" / "Zetas-Kai.ttf"), opts)
    print(f"{len(text)} glyphs -> fonts/Zetas-Kai.ttf")


if __name__ == "__main__":
    main(sys.argv[1])
