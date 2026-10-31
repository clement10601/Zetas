"""tools/lore.py 的測試：python -m unittest discover -s tests -p "test_*.py" """
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import lore  # noqa: E402


class LoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        shutil.copytree(lore.LORE, self.tmp, dirs_exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def edit(self, name, fn):
        path = self.tmp / name
        data = json.loads(path.read_text(encoding="utf-8"))
        fn(data)
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    def test_real_data_passes(self):
        self.assertEqual(lore.check(), [])

    def test_swapped_hexagram_is_caught(self):
        def swap(d):
            e = d["lore.hexagram.03"]
            e["upper"], e["lower"] = e["lower"], e["upper"]
        self.edit("yijing.json", swap)
        self.assertTrue(any("第 3、4 卦" in err for err in lore.check(self.tmp)))

    def test_verified_needs_checked_chapter(self):
        self.edit("cosmology.json", lambda d: d["lore.god.siming"]["quote"].update(verified=True))
        self.assertTrue(any("lore.god.siming" in err and "checked" in err for err in lore.check(self.tmp)))

    def test_unknown_region_and_simplified_text(self):
        def bad(d):
            d["lore.beast.tiangou"]["hooks"]["regions"] = ["region.nowhere"]
            d["lore.beast.tiangou"]["summary"] = "这是天狗"
        self.edit("beasts.json", bad)
        errors = lore.check(self.tmp)
        self.assertTrue(any("region.nowhere" in err for err in errors))
        self.assertTrue(any("簡體字" in err for err in errors))

    def test_entry_needs_quote_or_basis(self):
        self.edit("cosmology.json", lambda d: d["lore.faction.xian"].pop("basis"))
        self.assertTrue(any("lore.faction.xian" in err and "basis" in err for err in lore.check(self.tmp)))

    def test_select_prefers_region_and_respects_tier(self):
        items = lore.select(region="region.qingyun_foothills", tier="煉氣")
        keys = [k for k, _ in items]
        self.assertIn("lore.beast.jiuwei_hu", keys)
        self.assertNotIn("lore.beast.lushu", keys)  # 築基才出現
        top = items[0][1]
        self.assertIn("region.qingyun_foothills", top["hooks"]["regions"])

    def test_prompt_cites_source(self):
        text = lore.prompt_text(lore.select(tags=["狐"], k=3))
        self.assertIn("《山海經·南山經》", text)


if __name__ == "__main__":
    unittest.main()
