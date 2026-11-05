"""介面字型缺字檢查：python -m unittest discover -s tests -p "test_*.py"

art/fonts/ZetasUI.ttf 是霞鶩文楷的子集，網頁版沒有系統字型可以補，缺的字會顯示成方框或亂碼
（例如衣櫃左右鍵原本用的 ◀▶，霞鶩文楷本身就沒有）。這裡掃 scripts/ 的程式碼（略過整行註解）
和 content/ 的資料（略過只給人看的 content/lore/ 典籍），確定遊戲會顯示的字字型裡都有。
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    from fontTools.ttLib import TTFont
except ImportError:  # pragma: no cover
    TTFont = None


def game_text():
    for f in sorted((ROOT / "scripts").rglob("*.gd")):
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if not line.lstrip().startswith("#"):
                yield f, i, line
    for f in sorted((ROOT / "content").rglob("*.json")):
        if "lore" in f.relative_to(ROOT / "content").parts:
            continue
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            yield f, i, line


@unittest.skipIf(TTFont is None, "pip install fonttools")
class FontCoverageTest(unittest.TestCase):
    def test_every_shown_char_is_in_ui_font(self):
        cmap = TTFont(ROOT / "art/fonts/ZetasUI.ttf").getBestCmap()
        missing = {}
        for f, i, line in game_text():
            for c in line:
                if c.isprintable() and not c.isspace() and ord(c) not in cmap:
                    missing.setdefault(c, f"{f.relative_to(ROOT)}:{i}")
        self.assertEqual(missing, {}, "字型缺這些字（第一次出現的位置），換成字型裡有的字或重做子集")


if __name__ == "__main__":
    unittest.main()
