# 美術出處

## 古畫底圖（CC0）

戶外區塊的背景取自克里夫蘭美術館（Cleveland Museum of Art）開放典藏的中國手卷，館方以 CC0 釋出，可商用、可修改，不強制署名，我們照樣列出。裁切範圍見 `tools/inkpaint/paintings.py` 的 `SOURCES`。

| 典藏號 | 作品 | 用在 |
|---|---|---|
| [1970.3](https://www.clevelandart.org/art/1970.3) | 顧天植《仿黃公望山水》1649，紙本手卷 | 青雲山道、林間空地、山腳村落、荒廢山神廟、黑風嶺・斷魂谷、心魔幻境・青雲鎮 |
| [1975.75](https://www.clevelandart.org/art/1975.75) | 錢杜《夢遊天台圖》1814，紙本手卷 | 青雲密林、黑風嶺・山道 |
| [1997.95](https://www.clevelandart.org/art/1997.95) | 陳汝言、倪瓚（傳）《仙山圖》元，絹本青綠手卷 | 青雲宗・山門、演武場、傳功殿 |
| [1954.581](https://www.clevelandart.org/art/1954.581) | 文伯仁《潯陽送客圖》明，手卷 | 心魔幻境・入口、血月台 |

## 字型

- 霞鶩文楷 TC（LXGW WenKai TC），SIL Open Font License 1.1，子集放在 `tools/inkpaint/fonts/`，授權全文見 `OFL.txt`。

## 程式畫的部分

角色立繪、平台與機關、洞窟區塊、古畫上加的建築與陣紋，都是 `tools/paint_art.py` 用筆觸程式畫的，屬本專案原創。

## AI 重繪的角色立繪（AI 預先生成美術，上 Steam 要揭露）

`art/sprites/` 的角色立繪（`boss.demon_lord.png` 除外，仍是程式畫的原圖）是拿 `tools/paint_art.py` 畫的底稿，用 ComfyUI 做 img2img 重繪成水墨手繪風，再用底稿的 alpha 切回原尺寸。做法和重跑方式見 `tools/comfy/README.md`。屬 Steam 定義的「預先生成」AI 內容，上架時要在內容問卷揭露。

| 模型 | 來源 | 授權 |
|---|---|---|
| SDXL base 1.0 | [stabilityai/stable-diffusion-xl-base-1.0](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0) | CreativeML Open RAIL++-M（可商用，受授權的使用限制約束） |
| controlnet-union-sdxl-1.0 promax | [xinsir/controlnet-union-sdxl-1.0](https://huggingface.co/xinsir/controlnet-union-sdxl-1.0) | Apache-2.0 |
| XL - C_InkWashpainting v1.0 LoRA | [Civitai #137420](https://civitai.com/models/137420)，作者 Cinsdia | Civitai 授權欄：出圖可商用、可販售，不需署名 |

這些圖已經不是程式畫的了：**別再跑 `python tools/paint_art.py --all`**，會把它們蓋回底稿。
