# 角色立繪水墨重繪（ComfyUI）

`art/sprites/` 的角色立繪（`boss.demon_lord`、`player.disciple` 除外）是 `tools/inkpaint` 程式畫的底稿，經 ComfyUI img2img 重繪成水墨手繪風，再用底稿的 alpha 切回 360×480。授權與揭露見 [art/CREDITS.md](../../art/CREDITS.md)。

**別再跑 `python tools/paint_art.py --all`**，會把這些圖蓋回底稿。改了 `inkpaint/sprites.py` 的某個角色，就用這裡重跑那一張。

## 需要

一台跑著 ComfyUI 的機器（只綁 127.0.0.1 即可），`models/` 底下放：

| 檔案 | 資料夾 | 來源 |
|---|---|---|
| `sd_xl_base_1.0.safetensors` | `checkpoints/` | https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0 |
| `controlnet-union-sdxl-1.0-promax.safetensors` | `controlnet/` | https://huggingface.co/xinsir/controlnet-union-sdxl-1.0 的 `diffusion_pytorch_model_promax.safetensors`，改這個名字 |
| `InkWashpainting_civitai137420.safetensors` | `loras/` | https://civitai.com/models/137420 |

模型檔不放進 repo。只用 ComfyUI 內建節點（Canny、SetUnionControlNetType），不用裝自訂節點。16 GB 顯存夠用，RTX 4080 SUPER 一張約 7 秒。

## 重跑

在 repo 根目錄（要 numpy、Pillow）：

```bash
python tools/comfy/render_all.py --only npc.fox_girl             # 出 0.5／0.55 兩版到 build/comfy/ 比較
python tools/comfy/render_all.py --only npc.fox_girl --apply     # 照 PICK 把選定的版本寫進 art/sprites/
python tools/comfy/render_all.py --apply                         # 全部重跑並寫回
```

ComfyUI 不在本機就加 `--url http://主機:8188`。設定：SDXL base + ControlNet union（canny，強度 0.7）+ 水墨 LoRA 0.8，30 步 dpmpp_2m karras，cfg 6；denoise 0.5 用 seed 202、0.55 用 seed 303，同樣的模型會出同樣的圖。每個角色的英文描述在 `SUBJECTS`，進遊戲用哪一版在 `PICK`（沒列的用 0.55）。新增角色要在 `SUBJECTS` 補一行。

魂體（`npc.memory_echo`、`mob.wandering_ghost`）重繪後身體變實，`content/assets.json` 給它們設了 `"alpha": 0.6`，遊戲載入時乘在立繪上。
