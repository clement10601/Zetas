# Q 版主角 ComfyUI 精修（第一輪）

底稿：`../q_base_paper.png`（720×960）先 LANCZOS 放大到 1024×1368 當 img2img 輸入；`*_alpha.png` 是把輸出縮回 720×960，再用 `../q_base_alpha.png` 的 alpha（MaxFilter 5 + GaussianBlur 1，略外擴）切回透明底。

`contact_sheet.jpg`：第一列 = 底稿、ink08 四張；第二列 = ink05 四張（順序同下表）。

## 共通參數

| 項目 | 值 |
|---|---|
| Checkpoint | sd_xl_base_1.0.safetensors |
| LoRA | InkWashpainting_civitai137420（model/clip 同強度，見下表） |
| ControlNet | controlnet-union-sdxl-1.0-promax，type canny/lineart，strength 0.7，0→0.8 |
| Canny | low 0.2 / high 0.5 |
| Sampler | dpmpp_2m karras，30 步，cfg 6 |
| 尺寸 | 1024×1368 |

正向：chibi, super deformed, 2.5 heads tall, cute young xianxia cultivator, big round head, large teal eyes, small mouth, long black hair with top bun and gold hairpin with dangling jade beads, white hanfu robe with jade-green half-sleeve vest, teal sash, long jade ribbon floating, sword on back, chinese ink wash painting, soft watercolor, clean lineart, full body, plain paper background

負向：realistic, tall, adult proportions, extra limbs, extra fingers, deformed face, blurry, text, watermark

## 每張

| 檔名 | LoRA | denoise | seed | 耗時 (s) | 備註 |
|---|---|---|---|---|---|
| ink08_d45_s202 | 0.8 | 0.45 | 202 | 105.1* | 嘴角多一顆小虎牙狀筆觸；背後劍柄變成金色細棍 |
| ink08_d45_s303 | 0.8 | 0.45 | 303 | 15.9 | 乾淨；嘴略偏紅點 |
| ink08_d55_s202 | 0.8 | 0.55 | 202 | 16.4 | 頭髮暈染最明顯、水墨味最重；嘴角同樣有小虎牙筆觸 |
| ink08_d55_s303 | 0.8 | 0.55 | 303 | 16.9 | 背心/裙擺水彩暈開最多；嘴變成小噘嘴；頭髮筆觸較雜 |
| ink05_d45_s202 | 0.5 | 0.45 | 202 | 23.9 | 最接近底稿、臉最乾淨 |
| ink05_d45_s303 | 0.5 | 0.45 | 303 | 16.9 | 唯一保留棕色劍鞘的一張；臉乾淨 |
| ink05_d55_s202 | 0.5 | 0.55 | 202 | 18.0 | 腰帶變深綠、背心線條變細 |
| ink05_d55_s303 | 0.5 | 0.55 | 303 | 16.0 | 飄帶大半消失、劍柄也沒了；右側瀏海多一個金色髮夾 |

\* 第一張包含模型載入時間。總計 229 s（RTX，ubt015 Docker ComfyUI）。

沒有臉崩或比例跑掉的；2.5 頭身與輪廓都被 canny 鎖住。alpha 版邊緣有一圈很細的宣紙色描邊（alpha 外擴 2–3 px 造成），疊在深色背景上看得到。

產生腳本：ubt015 `~/claude_workspace/comfy-test/scripts/render_chibi.py`（沿用 render_shijie.py 的 workflow）。
