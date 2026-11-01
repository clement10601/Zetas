# 音樂與音效出處

目前所有配樂、短樂句與音效都是 `tools/compose_audio.py` 用數學合成（Karplus-Strong 撥弦模擬古琴／古箏、正弦泛音加氣聲模擬笛、磬、鑼、手鼓、木魚、風與溪水雜訊），沒有取樣或第三方素材，屬本專案原創，可商用。

重新產生：`python tools/compose_audio.py`（需要 numpy 與 ffmpeg；固定亂數種子，結果相同）。可用 `--only music|sfx|stingers` 只產一部分。

## 配樂（分三層，見 scripts/audio.gd）

每區三個檔：`<區>_base.ogg`（環境＋持續音，48 秒循環）、`<區>_melody.ogg`（琴笛，96 秒，最後 12 秒留白）、`<區>_rhythm.ogg`（鼓、鑼、木魚，跟旋律同長同步）。

| 區 | 調式 | 主題動機（音階級數） |
|---|---|---|
| 青雲宗 qingyun_sect | D 宮調，古琴慢板、磬 | 宮 角 徵 角 |
| 青雲山腳 qingyun_foothills | G 徵調，笛子領奏、古箏分解和弦、溪水鳥鳴 | 上行五音 |
| 黑風嶺 heifeng_ridge | A 羽調，低音持續、手鼓、鑼、強風 | 下行四音 |
| 心魔幻境 illusion | E 羽調，笛、長殘響 | 所在地區動機的倒影（`illusion_melody_<區>.ogg`） |

## 地圖與事件曲（audio/music/scene）

整首曲，不分層，48 秒循環。玩家走進有這些標籤的區塊、或事件進行中時切換（`scripts/main.gd` 的 `music_choice()`）：

| 檔案 | 用在 |
|---|---|
| map_cave / map_village / map_shrine / map_den / map_hall | 山洞、村落、山神廟、妖窟、傳功殿區塊 |
| event_story | 事件進行中（會擋住移動的那種） |
| event_combat | 事件裡有敵人在附近 |
| event_heart_demon | 心魔事件裡的對決 |

目前是合成版；預定換成 ElevenLabs Music 生成的版本（2026-11-01 帳號點數用完，等補點），換的時候保留檔名。

## 短樂句（audio/stingers）

每區 `event_start`、`event_end`、`breakthrough`、`motif`，另有共用的 `heart_demon`。遊戲裡等到配樂下一拍才播。

音效清單與音量在 `content/audio.json`。換成外部素材（例如 ElevenLabs 生成）時保留檔名即可，並在這裡註明來源與授權。
