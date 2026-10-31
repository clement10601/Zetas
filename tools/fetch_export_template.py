"""只下載 Godot 匯出模板包（.tpz，約 1.2 GB）裡需要的那一個檔案，用 HTTP Range 讀 zip 目錄。

用法：python tools/fetch_export_template.py 4.4.1 windows_release_x86_64.exe
檔案放到 Godot 的匯出模板資料夾（Linux：~/.local/share/godot/export_templates/<版本>.stable/）。
"""
import os
import struct
import sys
import urllib.request
import zlib
from pathlib import Path


def fetch(version, want):
    url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/Godot_v{version}-stable_export_templates.tpz"

    def get(a, b):
        return urllib.request.urlopen(urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}"})).read()

    size = int(urllib.request.urlopen(urllib.request.Request(url, method="HEAD")).headers["Content-Length"])
    tail = get(size - 65536, size - 1)
    i = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", tail[i + 12:i + 20])
    cd = get(cd_off, cd_off + cd_size - 1)
    p = 0
    while p < len(cd):
        fields = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
        method, csize, nlen, elen, clen, off = fields[4], fields[8], fields[10], fields[11], fields[12], fields[16]
        name = cd[p + 46:p + 46 + nlen].decode()
        if name == "templates/" + want:
            h = get(off, off + 29)
            n2, e2 = struct.unpack("<HH", h[26:30])
            start = off + 30 + n2 + e2
            data = get(start, start + csize - 1)
            return zlib.decompress(data, -15) if method == 8 else data
        p += 46 + nlen + elen + clen
    raise SystemExit(f"{want} not found in {url}")


if __name__ == "__main__":
    version, want = sys.argv[1], sys.argv[2]
    dest = Path(os.environ.get("GODOT_TEMPLATES", Path.home() / ".local/share/godot/export_templates")) / f"{version}.stable"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / want).write_bytes(fetch(version, want))
    (dest / "version.txt").write_text(f"{version}.stable\n")
    print(f"{want} -> {dest}")
