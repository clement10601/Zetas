"""導演實測情境的 hint 要跟遊戲真正送出的一樣：python -m unittest discover -s tests -p "test_*.py" """
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def gd_const(name):
    m = re.search(rf'^const {name} := "(.*)"$', (ROOT / "scripts" / "main.gd").read_text(encoding="utf-8"), re.M)
    return m.group(1)


class M2ScenariosTest(unittest.TestCase):
    def test_hints_match_main_gd(self):
        scenarios = json.loads((ROOT / "tests" / "director" / "m2_scenarios.json").read_text(encoding="utf-8"))["scenarios"]
        heart = gd_const("HEART_DEMON_HINT").replace("%s", "{}")
        encounter = gd_const("ENCOUNTER_HINT")
        tiers = json.loads((ROOT / "content" / "ruleset.json").read_text(encoding="utf-8"))["tiers"]
        for sc in scenarios:
            tag = sc["request"]["tag"]
            if tag == "heart_demon":
                nxt = sc["request"]["gate"][0]["to"]
                cur = tiers[sc["state"]["tier_index"]]
                self.assertEqual(sc["hint"], heart.format(nxt, cur, nxt, nxt), sc["name"])
            else:
                self.assertEqual(tag, "encounter")
                self.assertEqual(sc["hint"], encounter, sc["name"])
                self.assertEqual(sc["request"]["region"], sc["state"]["region"], sc["name"])


if __name__ == "__main__":
    unittest.main()
