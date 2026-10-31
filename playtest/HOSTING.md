# 架設封閉測試用的導演

這份是給架設者的說明，不會打包給測試者。導演跑在你的電腦上，用的是你的 Claude API 額度。測試者靠存取碼連進來，每個人每天的生成次數都有上限。

要長時間開著給測試者用，建議改架在 VM 上的 k0s：見 [deploy/k8s/README.md](../deploy/k8s/README.md)。存取碼和上限的觀念跟這份一樣。

## 1. 準備

需要 Python 3.10 以上。

```sh
git clone --recurse-submodules https://github.com/clement10601/Zetas.git
cd Zetas/engine
pip install jsonschema anthropic
```

API 金鑰只放在環境變數裡，不要寫進任何檔案，也不要貼到聊天室：

```powershell
# Windows PowerShell（只對這個視窗有效）
$env:ZEWORLD_ANTHROPIC_API_KEY = "..."
# 選用：用 TypeSafe Jev 替候選事件評分（OpenRouter 金鑰）
$env:ZEWORLD_JUDGE_API_KEY = "..."
```

## 2. 發存取碼

每位測試者發一組。存取碼檔請放在 repo 外面，因為裡面只存雜湊，不能拿來還原存取碼：

```sh
python -m director.access add --file ../../zeworld-codes.json --name 阿明
python -m director.access add --file ../../zeworld-codes.json --name 小寶 --daily-packs 20
python -m director.access total --file ../../zeworld-codes.json --daily-packs 200
```

印出來的 `zw-…` 只會出現這一次。預設每人每天 40 個事件、800 句台詞，所有人合計每天 200 個事件。用量的日期以 UTC 計算，所以台灣時間早上 8 點換日。

依 2026-10-31 的實測，生成一個事件大約要輸出 5k token（Opus），讀取的輸入大多走提示快取；改寫一句台詞（Sonnet）很便宜。請依當時的 API 價格估算合計上限要設多少。

## 3. 啟動導演

```sh
python -m director serve --game ../zeworld.json --access-codes ../../zeworld-codes.json --out ../../zeworld-generated
```

**一定要加 `--access-codes`。** 導演綁在 127.0.0.1 時，沒有存取碼也能啟動（方便本機開發）。但下一步的通道會把它公開到網路上，忘了加存取碼等於讓任何人用你的額度。啟動訊息應該顯示「N 組存取碼」，看到「不驗存取碼」就停下來。

## 4. 開 HTTPS 通道

最簡單的做法是 Cloudflare Tunnel：不用開路由器的埠，也自帶 HTTPS。安裝 [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) 之後執行：

```sh
cloudflared tunnel --url http://127.0.0.1:8765
```

它會印出一個 `https://xxxx.trycloudflare.com` 網址。這個快速通道每次重開都會換網址；要固定網址，得有 Cloudflare 帳號和網域，改用具名通道。

## 5. 給測試者

到 GitHub Actions 手動執行 `build` workflow：`director_url` 預設是 https://zetas-director.fezone.tw，會寫進 `director_url.txt`；`release_tag` 填了（例如 `playtest-0.2.0`）就會把 `Zetas-windows.zip` 發佈成 GitHub Release，不填就只產出 artifact。

**網頁版**（勾 `web`）會發佈到 https://clement10601.github.io/Zetas/ ，導演網址用 `project.godot` 的 `zetas/web_director_url`。給測試者 `https://clement10601.github.io/Zetas/?code=<存取碼>` 就能直接玩，遊戲會記住存取碼並把它從網址列拿掉；不帶的話第一次開啟會請他輸入。導演要是 ZeWorld#17 以後的版本（支援 CORS）。

**Windows 版**的 `Zetas.exe` 旁邊要有兩個文字檔：

- `director_url.txt`：第 4 步的網址。所有人共用，workflow 會預填。
- `director_code.txt`：這位測試者自己的存取碼。

把 Release 連結給大家，存取碼則私下分別給每個人，請他們自己建 `director_code.txt`。

## 6. 測試期間

```sh
python -m director.access list --file ../../zeworld-codes.json      # 今天每個人用了多少
python -m director.access disable --file ../../zeworld-codes.json --name 阿明
```

- 導演的終端機會印出每個請求是哪位測試者送的。
- 用 `add`、`disable`、`enable`、`total` 改過存取碼檔之後，要重啟導演才會生效。
- 超過上限時，遊戲會照常進行，只是沒有新的 AI 事件。測試者的遊玩紀錄 `playlog.jsonl` 裡會記到 `director_fail`。
- 收回的遊玩紀錄用 `python tools/playlog_report.py *.jsonl > report.md` 彙整。
