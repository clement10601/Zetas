# 字型

`Zetas-Kai.ttf` 是 [霞鶩文楷 TC（LXGW WenKai TC）](https://github.com/lxgw/LxgwWenkaiTC) Bold 的子集，只留 `tools/inkpaint/` 程式碼與 `content/chunks.json` 區塊名稱用到的字，授權是 SIL Open Font License 1.1（見 OFL.txt）。

新的區塊名稱或題字用到子集沒有的字時，從 Google Fonts 下載完整字型重做子集：

```
curl -LO https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/lxgwwenkaitc/LXGWWenKaiTC-Bold.ttf
pip install fonttools
python tools/inkpaint/subset_font.py LXGWWenKaiTC-Bold.ttf
```
