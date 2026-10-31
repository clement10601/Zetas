# 音樂與音效出處

目前所有配樂與音效都是 `tools/compose_audio.py` 用數學合成（Karplus-Strong 撥弦模擬古琴／古箏、正弦泛音加氣聲模擬笛、磬、鑼、手鼓、木魚），沒有取樣或第三方素材，屬本專案原創，可商用。

重新產生：`python tools/compose_audio.py`（需要 numpy 與 ffmpeg；每首固定亂數種子，結果相同）。

| 檔案 | 用在 | 調式 |
|---|---|---|
| music/qingyun_sect.ogg | 青雲宗 | D 宮調，古琴慢板、磬 |
| music/qingyun_foothills.ogg | 青雲山腳 | G 徵調，笛子領奏、古箏分解和弦 |
| music/heifeng_ridge.ogg | 黑風嶺 | A 羽調，低音持續、手鼓、鑼 |
| music/illusion.ogg | 心魔幻境（地圖標籤 illusion） | E 羽調，笛、長殘響 |

音效清單與音量在 `content/audio.json`。換成外部素材（例如 ElevenLabs 生成）時保留檔名即可，並在這裡註明來源與授權。
