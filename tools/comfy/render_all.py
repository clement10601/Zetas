#!/usr/bin/env python3
"""把程式畫的角色底稿（tools/inkpaint）丟進 ComfyUI 重繪成水墨手繪版，切回原尺寸寫進 art/sprites/。

用法（在 repo 根目錄，需要 numpy、Pillow，和一台跑著 ComfyUI 的機器，見 tools/comfy/README.md）：
  python tools/comfy/render_all.py                       # 全部角色，各出 0.5／0.55 兩版到 build/comfy/
  python tools/comfy/render_all.py --only npc.fox_girl   # 只跑這幾張（檔名，不含 .png）
  python tools/comfy/render_all.py --apply               # 跑完照 PICK 把選定的版本寫進 art/sprites/

底稿每次都從 inkpaint 重畫（跟 paint_art.py 同一張），不讀 art/sprites/，所以可以重跑。
seed 固定，同樣的模型與設定會出同樣的圖。別再跑 paint_art.py --all，會把重繪過的立繪蓋回底稿。
"""
import argparse, json, os, shutil, sys, time, urllib.request, uuid
from pathlib import Path
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from inkpaint import sprites as SP  # noqa: E402

CKPT = "sd_xl_base_1.0.safetensors"
LORA = "InkWashpainting_civitai137420.safetensors"
CN = "controlnet-union-sdxl-1.0-promax.safetensors"
W, H = 864, 1152
PAPER = (237, 231, 216, 255)
STYLE_PRE = "traditional Chinese ink wash painting, hand-drawn brush strokes, xianxia, "
STYLE_POST = (", full body, standing, side view facing right, light ink wash colors, visible brushwork, "
              "xuan rice paper texture, plain off-white paper background, generous negative space")
NEG = ("photo, realistic, 3d render, anime, cel shading, thick black outline, cartoon, text, watermark, signature, seal, "
       "lowres, blurry, bad anatomy, extra limbs, extra fingers, deformed, two heads, scenery, landscape, mountains, busy background")
ROBE = "wide sleeves, long robe"
# 檔名 -> 外觀描述（照底稿寫的英文）
SUBJECTS = {
    "player.disciple": f"a young male sect disciple, black hair in a high topknot, long teal silk ribbon flowing behind him, white sect robe with teal sash, {ROBE}, sword on his back, calm determined face",
    "npc.fellow_disciple_a": f"a young male sect disciple, black hair in a topknot with gold band, pale blue sect robe, dark blue sash, {ROBE}, sword on his back",
    "npc.fellow_disciple_b": f"a young female sword cultivator disciple, long black hair tied in a high bun, red hairpin, long pale blue silk ribbon flowing behind her, pale cyan-blue sect robe, dark blue sash, {ROBE}, sword on her back, calm stern face",
    "npc.fellow_disciple_c": f"a young sect disciple, black hair in a ponytail, pale grey-blue sect robe, dark blue sash, {ROBE}, sword on the back, hands clasped",
    "npc.cultivator_a": f"a wandering cultivator, black hair in a topknot with small crown, purple robe, gold sash, gourd at waist, {ROBE}",
    "npc.cultivator_b": f"a young wandering cultivator, black hair in a high ponytail, beige robe, red sash, {ROBE}",
    "npc.cultivator_c": f"an old wandering cultivator, long white beard, black hair in a topknot, dark green robe, black sash, gourd at waist, holding a tall wooden staff, {ROBE}",
    "npc.sect_master": f"an elderly sect master, white hair and long white beard, small hair crown, dark slate-blue robe, gold sash, holding a white horsetail whisk, {ROBE}, dignified",
    "npc.fox_girl": f"a fox spirit girl, long brown hair, fox ears, fluffy white fox tail, white robe with red sash and red hem, {ROBE}, small blue spirit flames floating around her",
    "npc.generic": f"a plain sect disciple, black hair in a topknot, grey-brown robe, dark sash, {ROBE}",
    "npc.memory_echo": f"a translucent ghostly memory of a young female disciple, long black hair in a bun, faded pale blue robe, {ROBE}, fading into mist, soft blue glow",
    "npc.merchant_a": "a travelling peddler, conical straw hat, long black beard, brown tunic and trousers, large wooden backpack frame with a small banner",
    "npc.merchant_b": f"a herb merchant, black hair in a topknot with red headband, black beard, olive green robe, red sash, holding a small basket of herbs, {ROBE}",
    "npc.villager_a": "a village man, black hair in a topknot, brown short tunic and trousers, carrying a small basket of vegetables",
    "npc.villager_b": f"a village woman, black hair in a bun, sage green robe, red sash, {ROBE}",
    "npc.villager_c": "an old village man, grey hair and grey beard, brown robe, leaning on a wooden walking stick",
    "mob.bandit_a": "a mountain bandit, black hair, red headband, brown short tunic and dark trousers, red sash, holding a sabre",
    "mob.bandit_b": "a mountain bandit, black hair, long white beard, dark grey tunic and trousers, holding a broad sabre",
    "mob.generic": "a bandit, black hair in a ponytail, dark grey-brown tunic, red sash, holding a sabre",
    "mob.demon_hunter": f"a demon hunter, wide conical bamboo hat, black robe, red sash, yellow talisman papers at the waist, chain whip, {ROBE}",
    "mob.wolf_demon": "a wolf demon, grey furred wolf head with glowing orange eyes, hunched upright posture, clawed hands reaching forward, long bushy tail, red cloth belt",
    "mob.shengsheng": "a small ape-like mountain spirit, shaggy brown fur, hunched, long thin tail, holding a red fruit",
    "mob.gudiao": "a mythical horned eagle demon, dark brown feathers, spread wings, single horn, sharp yellow beak, long thin legs with talons",
    "mob.wandering_ghost": f"a translucent wandering ghost, pale grey-green robe, long black hair, {ROBE}, fading into mist, faint green glow",
    "boss.heart_demon_mirror": f"a dark mirror double of a sect disciple, black robe, red sash, glowing red eyes, holding a crimson glowing sword, {ROBE}, red mist aura, scattered falling leaves",
}
# boss.demon_lord 不重繪：輪廓被改太多（長角、潑墨），留程式原圖
# player.disciple 只出圖比較、不寫回：遊戲裡主角由衣櫃分層疊出，這張是 test_wardrobe 對齊用的底稿
NO_APPLY = {"player.disciple"}
VARIANTS = {"d50": (202, 0.50), "d55": (303, 0.55)}
# 進遊戲的版本；沒列的用 d55。d50 那幾張是 0.55 會轉臉或糊掉
PICK = {n: "d50" for n in ["npc.villager_b", "npc.villager_c", "npc.merchant_a", "npc.memory_echo",
                           "mob.wandering_ghost", "boss.heart_demon_mirror"]}


def base_sprites():
    """檔名 -> (asset id, 變體序號)，照 assets.json 的 files。"""
    manifest = json.loads((ROOT / "content/assets.json").read_text(encoding="utf-8"))
    out = {}
    for aid, info in manifest["assets"].items():
        for i, f in enumerate(info.get("files", [])):
            out[Path(f).stem] = (aid, i)
    return out


def workflow(image, pos, seed, denoise, prefix):
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "2": {"class_type": "LoraLoader", "inputs": {"model": ["1", 0], "clip": ["1", 1], "lora_name": LORA,
                                                       "strength_model": 0.8, "strength_clip": 0.8}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": pos, "clip": ["2", 1]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["2", 1]}},
        "5": {"class_type": "LoadImage", "inputs": {"image": image}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "Canny", "inputs": {"image": ["5", 0], "low_threshold": 0.2, "high_threshold": 0.5}},
        "8": {"class_type": "ControlNetLoader", "inputs": {"control_net_name": CN}},
        "9": {"class_type": "SetUnionControlNetType", "inputs": {"control_net": ["8", 0],
                                                                 "type": "canny/lineart/anime_lineart/mlsd"}},
        "10": {"class_type": "ControlNetApplyAdvanced", "inputs": {
            "positive": ["3", 0], "negative": ["4", 0], "control_net": ["9", 0], "image": ["7", 0],
            "strength": 0.7, "start_percent": 0.0, "end_percent": 0.8, "vae": ["1", 2]}},
        "11": {"class_type": "KSampler", "inputs": {
            "model": ["2", 0], "positive": ["10", 0], "negative": ["10", 1], "latent_image": ["6", 0],
            "seed": seed, "steps": 30, "cfg": 6.0, "sampler_name": "dpmpp_2m", "scheduler": "karras",
            "denoise": denoise}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["1", 2]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": prefix}},
    }


def call(url, path, body=None, raw=False):
    req = urllib.request.Request(url + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return data if raw else json.loads(data)


def upload(url, name, png_path):
    """用 ComfyUI 的 /upload/image 送底稿，不用碰 ComfyUI 的 input 資料夾。"""
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + png_path.read_bytes() + \
           (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"subfolder\"\r\n\r\nzetas\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--{boundary}--\r\n").encode()
    req = urllib.request.Request(url + "/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        info = json.loads(r.read())
    return f"{info['subfolder']}/{info['name']}"


def render(url, client, image, pos, seed, denoise, prefix):
    pid = call(url, "/prompt", {"prompt": workflow(image, pos, seed, denoise, prefix), "client_id": client})["prompt_id"]
    while True:
        hist = call(url, f"/history/{pid}")
        st = hist.get(pid, {}).get("status", {})
        if st.get("status_str") == "error":
            raise SystemExit(json.dumps(st, indent=1))
        if st.get("completed"):
            img = next(v for v in hist[pid]["outputs"].values() if "images" in v)["images"][0]
            q = f"/view?filename={img['filename']}&subfolder={img['subfolder']}&type={img['type']}"
            return call(url, q, raw=True)
        time.sleep(0.5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8188")
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=str(ROOT / "build/comfy"))
    ap.add_argument("--apply", action="store_true", help="把 PICK 選的版本寫進 art/sprites/")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    only = set(filter(None, a.only.split(",")))
    bases = base_sprites()
    client = str(uuid.uuid4())
    t_all = time.time()
    for name, subj in SUBJECTS.items():
        if only and name not in only:
            continue
        aid, idx = bases[name]
        src = SP.render(aid, idx).convert("RGBA")
        big = src.resize((W, H), Image.LANCZOS)
        bg = Image.new("RGBA", (W, H), PAPER)
        bg.alpha_composite(big)
        bg.convert("RGB").save(out / f"{name}_in.png")
        image = upload(a.url, f"{name}_in.png", out / f"{name}_in.png")
        alpha = big.getchannel("A").filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(2))
        for tag, (seed, dn) in VARIANTS.items():
            t0 = time.time()
            raw = out / f"{name}_{tag}.png"
            raw.write_bytes(render(a.url, client, image, STYLE_PRE + subj + STYLE_POST, seed, dn, f"zetas/{name}_{tag}"))
            cut = Image.open(raw).convert("RGBA")
            cut.putalpha(alpha)
            cut.resize(src.size, Image.LANCZOS).save(out / f"{name}_{tag}_alpha.png")
            print(f"{name}\t{tag}\t{time.time() - t0:.1f}s", flush=True)
        if a.apply and name not in NO_APPLY:
            shutil.copy(out / f"{name}_{PICK.get(name, 'd55')}_alpha.png", ROOT / "art/sprites" / f"{name}.png")
    print(f"total {time.time() - t_all:.1f}s")


if __name__ == "__main__":
    main()
