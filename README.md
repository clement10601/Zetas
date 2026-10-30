# Zetas

仙俠題材的 2D 橫軸遊戲，使用 [ZeWorld](https://github.com/clement10601/ZeWorld) 引擎：事件與場景由內容包驅動，依玩家的選擇、因果與境界觸發。

## 開始

需要 Godot 4.4 與 Python 3。

```sh
git clone --recurse-submodules https://github.com/clement10601/Zetas.git
cd Zetas
python tools/sync_engine.py   # 把引擎 addon 複製到 addons/zeworld
```

用 Godot 開啟這個資料夾，執行主場景。

| 按鍵 | 動作 |
| --- | --- |
| ← → / A D | 移動 |
| ↑ / W | 跳 |
| J | 攻擊（近身） |
| 空白 / Enter | 下一句對話 |
| 1–4 | 選擇對話選項 |
| F1 | 除錯：放走受傷的白狐 |
| F2 | 除錯：過一天 |
| F3 | 除錯：換時辰（晨、午、暮、夜） |
| F4 | 除錯：突破境界 |

試玩：F1 放走白狐，F2 按三次，F3 換到「暮」，就會觸發「白狐報恩」。F4 突破築基會進入「築基心魔」。

## 目錄

| 路徑 | 內容 |
| --- | --- |
| `engine/` | ZeWorld 引擎（git submodule）。不要在這裡改，請到 ZeWorld 開 PR |
| `content/ruleset.json` | 境界、善惡軸、時辰名稱，提供給引擎 |
| `content/chunks.json` | 地圖區塊庫；內容包只能引用這裡的區塊與地點 |
| `content/loot.json` | 掉落表；引擎只傳 loot_table 與稀有度，物品由遊戲決定 |
| `content/packs/` | 內容包（白狐報恩、築基心魔） |
| `scripts/`、`scenes/` | 遊戲主控、玩家 |
| `tests/run_tests.gd` | 內容一致性與兩個內容包的完整流程測試 |

## 測試

```sh
python engine/content-pack/validate.py --ruleset content/ruleset.json content/packs/*.json
godot --headless --path . -s res://tests/run_tests.gd
```

## 現況（M0）

美術是色塊，戰鬥是近身按 J 打三下。台詞的 `live_rewrite` 目前用預寫台詞；導演、即時改寫與預生成池在 M1 接上。
