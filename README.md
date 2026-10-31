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
| F5 / F9 | 存檔 / 讀檔（`user://save.json`，啟動時自動讀） |
| F6 | 請導演生成一個新事件 |

試玩：F1 放走白狐，F2 按三次，F3 換到「暮」，就會觸發「白狐報恩」。F4 突破築基會進入「築基心魔」。

## 接上導演（AI 生成事件與即時台詞）

導演是 ZeWorld 的 Python 服務，遊戲連 `http://127.0.0.1:8765`（可用環境變數 `ZEWORLD_DIRECTOR_URL` 改）。沒開導演時遊戲照常，只是不會有新事件、台詞用預寫版本。

```sh
cd engine
pip install jsonschema
export ZEWORLD_LLM_BASE_URL=http://your-litellm:4000/v1   # OpenAI 相容端點
export ZEWORLD_LLM_API_KEY=...                            # 只放環境變數，不要寫進檔案
export ZEWORLD_DIRECTOR_MODEL=your-director-model
export ZEWORLD_DIALOGUE_MODEL=your-local-model
python -m director serve --game ../zeworld.json
```

沒有模型也能試流程：`python -m director serve --game ../zeworld.json --fake-pack ../tests/fixtures/director_zhenyao_grudge.json --fake-line "恩公，又見面了。"`

- 事件結局的 `request_followup` 會送給導演；導演產出的內容包通過驗證後存到 `user://generated`，等滿 `after_days` 天、條件成立就觸發。
- 標了 `live_rewrite` 的台詞先顯示預寫版，導演改寫好就替換；玩家已翻頁就不換。
- 導演只能用 `zeworld.json` 列出的資料：`content/chunks.json`、`content/actors.json`、`content/loot.json`、`content/ruleset.json`，風格依 `content/style.md`。

## 目錄

| 路徑 | 內容 |
| --- | --- |
| `engine/` | ZeWorld 引擎（git submodule）。不要在這裡改，請到 ZeWorld 開 PR |
| `zeworld.json` | 給引擎與導演的遊戲清單 |
| `content/ruleset.json` | 境界、善惡軸（含傾向名稱）、時辰名稱，提供給引擎 |
| `content/actors.json` | 角色與怪物模板；導演只能用這些 |
| `content/style.md` | 給導演的題材與文風說明 |
| `content/chunks.json` | 地圖區塊庫；內容包只能引用這裡的區塊與地點 |
| `content/loot.json` | 掉落表；引擎只傳 loot_table 與稀有度，物品由遊戲決定 |
| `content/packs/` | 內容包（白狐報恩、築基心魔） |
| `scripts/`、`scenes/` | 遊戲主控、玩家 |
| `tests/run_tests.gd` | 內容一致性、兩個內容包的完整流程、導演生成事件、即時台詞、存讀檔測試 |
| `tests/fixtures/` | 假導演回覆與一份導演產出的內容包 |

## 測試

```sh
python engine/content-pack/validate.py --game zeworld.json
godot --headless --path . -s res://tests/run_tests.gd
```

## 現況（M1）

美術是色塊，戰鬥是近身按 J 打三下。導演、預生成池、即時台詞與存檔已接上；還沒用真模型調過提示詞（需要 LLM 端點）。
