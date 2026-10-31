# 把導演架到 k0s

封閉測試前期把導演伺服器放在 VM 上的 k0s。和 [playtest/HOSTING.md](../../playtest/HOSTING.md) 在自己電腦上跑是同一個導演，差別是：

- 導演跑在容器裡，映像由 GitHub Actions 自動建好，推到 `ghcr.io/clement10601/zetas-director`。
- Claude／OpenRouter 金鑰和存取碼檔（只有雜湊）放在 Kubernetes Secret，不進 repo。
- 每日用量和導演生成的內容包寫在 PVC，重開 Pod 不會歸零。
- HTTPS 有兩種做法：Cloudflare 具名通道（建議，和 Re:Fantasy 一樣），或叢集自己的 Ingress＋cert-manager。

```
deploy/
  director/Dockerfile      導演映像（engine/director + Zetas 遊戲資料）
  k8s/base/                Namespace zetas、Deployment、Service、PVC
  k8s/tunnel/              base + cloudflared（建議）
  k8s/ingress/             base + Ingress
  k8s/fezone/              Kc 的 k0s：tunnel + PVC 用 rustfs-nfs（實際部署用這個）
```

以下指令都在 VM（或任何連得到叢集的電腦）上執行，`kubectl` 指的是 `k0s kubectl` 或設好 kubeconfig 的 kubectl。

## 0. 先確認兩件事

**映像拉得到。** 第一次推到 GHCR 的套件預設是私有的。到 GitHub 的 Packages → `zetas-director` → Package settings，把 visibility 改成 Public（repo 本身是公開的，映像裡沒有金鑰）。不想公開的話，就建一個 `imagePullSecret` 加進 Deployment。

**叢集有預設的 StorageClass。** k0s 沒有內建儲存，PVC 會一直 Pending：

```sh
kubectl get storageclass
```

如果沒有任何一行標著 `(default)`，可以裝 Rancher 的 local-path-provisioner，把資料放在 VM 本機磁碟（請先看過它的 manifest 再套用）：

```sh
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## 1. 放金鑰

金鑰用 `read -s` 輸入，不會留在 shell 歷史裡，也不要貼到聊天室：

```sh
kubectl create namespace zetas
read -rs ANTHROPIC_KEY && read -rs JUDGE_KEY
kubectl -n zetas create secret generic zetas-director-keys \
  --from-literal=ZEWORLD_ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
  --from-literal=ZEWORLD_JUDGE_API_KEY="$JUDGE_KEY"
unset ANTHROPIC_KEY JUDGE_KEY
```

- `ZEWORLD_JUDGE_API_KEY`（OpenRouter，給 TypeSafe Jev 評分）是選填，不用就拿掉那一行。
- 這個 Secret 的每個欄位都會變成導演的環境變數，所以也可以放 `ZEWORLD_DIRECTOR_MODEL`、`ZEWORLD_DIALOGUE_MODEL` 換模型。
- 想讓導演改走 k0s 上的 LiteLLM：不放 `ZEWORLD_ANTHROPIC_API_KEY`，改放 `ZEWORLD_LLM_BASE_URL`（例如 `http://litellm.<namespace>.svc.cluster.local:4000/v1`）、`ZEWORLD_LLM_API_KEY`、`ZEWORLD_DIRECTOR_MODEL`。

## 2. 發存取碼

存取碼檔在自己電腦上建（需要 Python 和 Zetas repo），只存雜湊，再整份放進 Secret：

```sh
cd Zetas/engine
python -m director.access add   --file ~/zeworld-codes.json --name 阿明
python -m director.access add   --file ~/zeworld-codes.json --name 小寶 --daily-packs 20
python -m director.access total --file ~/zeworld-codes.json --daily-packs 200

kubectl -n zetas create secret generic zetas-director-codes --from-file=codes.json=$HOME/zeworld-codes.json
```

印出來的 `zw-…` 只出現這一次，直接交給測試者。上限的意義見 [HOSTING.md](../../playtest/HOSTING.md) 第 2 節。

之後新增、停用或改上限，一樣改本機的 `~/zeworld-codes.json`，再更新 Secret 並重啟導演：

```sh
kubectl -n zetas create secret generic zetas-director-codes --from-file=codes.json=$HOME/zeworld-codes.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n zetas rollout restart deploy/zetas-director
```

本機的存取碼檔要保管好：它是唯一的原稿，Secret 裡那份是唯讀的。

## 3. HTTPS 入口（二選一）

導演只認存取碼（`Authorization: Bearer`），遊戲過不了登入頁。**這個網址不能套 SSO 或 Cloudflare Access**，即使其他 `*.service.fezone.tw` 服務有套。

### A. Cloudflare 具名通道（建議）

不用在 VM 開埠，HTTPS 由 Cloudflare 處理，網址固定。

1. Cloudflare 控制台 → Zero Trust → Networks → Tunnels → Create a tunnel（類型選 Cloudflared），取名例如 `zetas-director`，複製安裝指令裡的 token。
2. 把 token 放進 Secret：

   ```sh
   read -rs CF_TOKEN
   kubectl -n zetas create secret generic zetas-cloudflared --from-literal=token="$CF_TOKEN"
   unset CF_TOKEN
   ```

3. 在通道的 Public Hostname 新增一筆：網域選 `fezone.tw`、子網域例如 `zetas-director`；Service 類型 `HTTP`，URL 填 `zetas-director.zetas.svc.cluster.local:8765`。
4. 部署：

   ```sh
   kubectl apply -k deploy/k8s/tunnel
   # Kc 的 k0s（沒有預設 StorageClass，用 rustfs-nfs）：
   kubectl apply -k deploy/k8s/fezone
   ```

Cloudflare 對單一請求最多等 100 秒；生成一個事件約 45–55 秒，遊戲端等 90 秒就放棄，所以不會撞到。

### B. Ingress＋cert-manager

叢集已經有 ingress-nginx 和 cert-manager（`ClusterIssuer`）時用。先改 [ingress/ingress.yaml](ingress/ingress.yaml) 裡的主機名稱、`ingressClassName`、`cert-manager.io/cluster-issuer`，DNS 指到 VM，再：

```sh
kubectl apply -k deploy/k8s/ingress
```

用的不是 ingress-nginx 的話，記得把代理逾時調到 120 秒以上（nginx 預設 60 秒，生成事件會被切斷）。

## 4. 確認

```sh
kubectl -n zetas get pods
kubectl -n zetas logs deploy/zetas-director
```

啟動訊息要看到 `serving zetas on http://0.0.0.0:8765，N 組存取碼`。存取碼檔是空的或沒掛上時，導演會直接結束，不會在沒驗證的情況下對外服務。

從外面測：

```sh
curl https://zetas-director.fezone.tw/v1/health                       # {"ok": true, ..., "auth": true}
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://zetas-director.fezone.tw/v1/dialogue/rewrite -d '{}'   # 401
```

## 5. 給測試者

和 HOSTING.md 第 5 節一樣：`Zetas.exe` 旁邊放 `director_url.txt`（第 3 步的 https 網址）和 `director_code.txt`（那位測試者的存取碼）。

## 6. 測試期間

```sh
# 今天每個人用了多少
kubectl -n zetas exec deploy/zetas-director -- python -m director.access list --file /secrets/codes.json
# 每個請求是哪位測試者送的
kubectl -n zetas logs -f deploy/zetas-director
```

- **更新導演**：main 有新的引擎或遊戲資料時，`director-image` workflow 會推新的 `:main` 映像。執行 `kubectl -n zetas rollout restart deploy/zetas-director` 就會拉新版。想固定版本，把 [base/kustomization.yaml](base/kustomization.yaml) 的 `newTag` 改成 `sha-<commit>`。
- **重啟會中斷正在生成的請求**，遊戲那邊當成導演失敗、照常玩手寫內容，不會壞檔。
- **用量**存在 PVC 的 `/data/usage.json`，以 UTC 日期分天（台灣時間早上 8 點換日）。生成的內容包在 `/data/generated/`，可以 `kubectl cp` 出來挑好的收進 `content/packs`。
- **停掉**：`kubectl -n zetas scale deploy/zetas-director --replicas=0`。整個拆掉：`kubectl delete -k deploy/k8s/tunnel`（連同 namespace 裡的 Secret 和 PVC 一起刪，要留用量先 `kubectl cp`）。
