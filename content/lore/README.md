# 典籍知識庫

仙俠題材的異獸、神山、境界、卦象與仙魔佛設定，整理自公有領域古籍。給兩種人用：

- **設計**：做地圖、技能樹、任務時查有沒有古典根據，例如雲夢澤該放什麼水怪、五行法訣怎麼相剋、狐族的境界怎麼分。
- **導演**：生成事件前，依地區、境界、緣分挑幾筆放進 prompt，讓生成的妖怪和典故有出處，不憑空捏造。

## 檔案

| 檔案 | 內容 | 筆數 |
| --- | --- | --- |
| `sources.json` | 典籍目錄：書名、年代、作者、原文網址、已核對的篇章 | 16 部 |
| `beasts.json` | 《山海經》異獸、神祇、靈草 | 43 |
| `places.json` | 神山與仙島：青丘、崑崙、不周山、峚山、蓬萊… | 16 |
| `cultivation.json` | 八個境界的來歷，與三尸、辟穀、五行、精氣神等觀念 | 15 |
| `yijing.json` | 八卦、六十四卦（卦畫與上下卦）、選錄卦辭與繫辭 | 76 |
| `cosmology.json` | 仙、魔、佛、狐修、鬼、女媧補天、闡截二教、司命 | 12 |

收錄的書：山海經、周易、道德經、莊子、列子、尚書、淮南子、列仙傳、抱朴子內篇、玄中記、搜神記、悟真篇、太上感應篇、心經、金剛經、封神演義。

## 一筆條目

```json
"lore.beast.jiuwei_hu": {
  "name": "九尾狐",
  "kind": "beast",
  "summary": "白話整理",
  "quote": {"text": "原文", "source": "src.shanhaijing", "chapter": "南山經", "verified": true},
  "tags": ["狐", "青丘"],
  "hooks": {
    "regions": ["region.qingyun_foothills"],
    "planned_regions": [],
    "tier_min": "煉氣",
    "fate": "xian",
    "actor": "npc.fox_girl",
    "uses": ["事件", "角色"],
    "idea": "給設計和導演的用法建議"
  }
}
```

- `quote` 是原文，`basis` 是沒有直接引文時的根據說明。每筆至少要有一個。
- `verified: true` 表示引文已對照 `sources.json` 裡 `checked` 列出的版本逐字核對過（只刪去郭璞注）。目前《山海經》南山經、西山經、北山經、大荒北經的 57 筆已核對；其他書的引文是憑記憶引錄，標 `false`，用之前要再對一次原文。
- `hooks` 是遊戲用法，不是原典內容。`regions` 必須是 `content/regions.json` 已有的地區；還沒做的地區放 `planned_regions`（id 照 `docs/design/world-map.md`）。`fate` 是仙緣 `xian`、魔緣 `mo`、佛緣 `fo`。
- 卦畫 `lines` 由下往上，1 是陽爻。

## 改編原則

1. 原典特徵要留著：九尾狐的嬰兒聲、畢方的一足、天狗是辟邪小獸而不是食月凶物。玩家查得到原文，留著才有味道。
2. 後世設定要標明。合體、大乘、渡劫這些境界古書沒有，`basis` 寫清楚是小說的借用。
3. 不要捏造出處。導演寫的典故如果知識庫沒有，就當作遊戲裡的傳說，不要掛古書的名字。
4. 現代整理本、譯注本、網路小說的設定有著作權，不收；只收古籍原文和我們自己寫的白話。

## 工具

```sh
python tools/lore.py check                                     # 檢查格式、出處、地區、卦序
python tools/lore.py find --tag 狐                              # 列出條目
python tools/lore.py prompt --region region.heifeng_ridge --tier 築基 -k 6   # 給導演的參考段落
python -m unittest discover -s tests -p "test_*.py"             # 工具本身的測試
```

`check` 會驗證：id 不重複、出處存在、已核對的篇章有登記、地區與角色模板存在、八個境界都有條目、我們自己寫的文字沒有簡體字，以及六十四卦依文王卦序兩兩互為綜卦或錯卦（上下卦填錯會被抓到）。

## 之後

- 補核對：用 `sources.json` 的網址把 `verified: false` 的引文逐一對過，對完在 `checked` 登記篇章。
- 擴充：《山海經》東山經、中山經、海外四經、海內四經；《搜神記》報恩與報仇的故事；《抱朴子》入山、登涉篇的入山禁忌與符。
- 導演接法：`zeworld.json` 的 `lore` 指向這個資料夾，由引擎決定怎麼挑選放進 prompt（在 ZeWorld 開 PR）。
