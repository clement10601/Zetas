"""把引擎 submodule 的 Godot addon 複製到 addons/zeworld。

用法（在 repo 根目錄）：
    git submodule update --init
    python tools/sync_engine.py

addons/zeworld 不進版控；引擎要改請到 ZeWorld repo 開 PR，再更新 submodule。
用複製而不是 symlink，Windows 上不需要管理員權限。
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "engine" / "godot" / "addons" / "zeworld"
DST = ROOT / "addons" / "zeworld"

if not SRC.is_dir():
    raise SystemExit(f"找不到 {SRC}，請先執行 git submodule update --init")
if DST.exists():
    shutil.rmtree(DST)
shutil.copytree(SRC, DST)
print(f"synced {SRC.relative_to(ROOT)} -> {DST.relative_to(ROOT)}")
