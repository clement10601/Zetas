"""程式合成 Zetas 的背景音樂與音效（本專案原創，無第三方素材）。

用法：python tools/compose_audio.py [--only music|sfx] [--seconds 96]
輸出：audio/music/*.ogg、audio/sfx/*.ogg（需要 ffmpeg 轉 Ogg Vorbis）。

樂器都是數學合成：
- 古琴／古箏：Karplus-Strong 撥弦，加一點滑音（吟猱）。
- 笛：正弦泛音＋氣聲雜訊＋顫音。
- 低音持續音、磬、鑼、手鼓、木魚。
曲子用五聲音階（宮商角徵羽），每首固定亂數種子，重跑會得到一樣的檔。
換成 ElevenLabs 等外部素材時，只要檔名不變，content/audio.json 不用改。
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np

SR = 32000
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "audio"


# ---------- 基本工具 ----------

def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    """a, d, r 單位秒；s 是持續音量。"""
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    """FFT 低通（柔和斜率）。"""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1 / np.sqrt(1 + (f / cutoff) ** 4)
    return np.fft.irfft(spec, len(x))


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= (1 / np.sqrt(1 + (f / hi) ** 4)) * (1 / np.sqrt(1 + (lo / np.maximum(f, 1)) ** 4))
    return np.fft.irfft(spec, len(x))


def reverb(x: np.ndarray, seconds: float, wet: float, rng: np.random.Generator, bright: float = 4000) -> np.ndarray:
    """合成脈衝響應（衰減雜訊）做 FFT 捲積，回傳立體聲 (n, 2)。"""
    n_ir = int(seconds * SR)
    t = np.arange(n_ir) / SR
    out = []
    for _ in range(2):
        ir = rng.standard_normal(n_ir) * np.exp(-6.9 * t / seconds)
        ir = lowpass(ir, bright)
        ir[: int(0.012 * SR)] = 0  # 預延遲
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        size = len(x) + n_ir
        nfft = 1 << (size - 1).bit_length()
        y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[: len(x)]
        out.append(x * (1 - wet) + y * wet * 1.6)
    return np.stack(out, axis=1)


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-9
    return x / peak * 10 ** (peak_db / 20)


def normalize_rms(x: np.ndarray, rms_db: float = -20.0) -> np.ndarray:
    """配樂統一響度：調到目標 RMS，再用 tanh 軟限幅壓住峰值。"""
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    y = x / rms * 10 ** (rms_db / 20)
    return np.tanh(y * 1.1) / np.tanh(1.1) * 0.92


def write_ogg(path: Path, x: np.ndarray, quality: int = 4) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if x.ndim == 1:
        x = x[:, None]
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "a.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(pcm.shape[1])
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis",
                        "-q:a", str(quality), str(path)], check=True)


# ---------- 樂器 ----------

def pluck(freq: float, dur: float, rng: np.random.Generator, bright: float = 0.5, decay: float = 0.996,
          slide: float = 0.0) -> np.ndarray:
    """Karplus-Strong 撥弦。slide：結尾往上滑幾個半音（古琴的上滑音）。"""
    n = int(dur * SR)
    period = SR / freq
    p = int(period)
    burst = rng.uniform(-1, 1, p)
    burst = lowpass(np.concatenate([burst, burst]), 600 + 5000 * bright)[:p]
    out = np.zeros(n + p + 1)
    out[:p] = burst
    # 分段向量化：每次算一個週期長
    i = p
    while i < n + 1:
        j = min(i + p, n + 1)
        prev = out[i - p: j - p]
        prev2 = out[i - p - 1: j - p - 1] if i - p - 1 >= 0 else np.concatenate([[0.0], out[i - p: j - p - 1]])
        out[i:j] = decay * 0.5 * (prev + prev2)
        i = j
    y = out[:n]
    if slide:
        # 重新取樣做滑音：後半段頻率漸升
        t = np.linspace(0, 1, n)
        rate = 2 ** (slide / 12 * np.clip((t - 0.35) / 0.65, 0, 1) ** 2)
        pos = np.cumsum(rate)
        pos = pos[pos < n - 1]
        y = np.interp(pos, np.arange(n), y)
        y = np.pad(y, (0, n - len(y)))
    # 撥弦的琴身共鳴：一點點低頻加厚
    body = np.sin(2 * np.pi * freq * np.arange(n) / SR) * np.exp(-np.arange(n) / (SR * 0.6)) * 0.15
    fade = np.ones(n)
    fade[-int(0.05 * SR):] = np.linspace(1, 0, int(0.05 * SR))
    return (y + body) * fade


def flute(freq: float, dur: float, rng: np.random.Generator, vib: float = 0.012) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib_amt = vib * np.clip(t / 0.5, 0, 1)  # 長音才慢慢加顫音
    f = freq * (1 + vib_amt * np.sin(2 * np.pi * 5.2 * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) + 0.28 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    breath = bandpass(rng.standard_normal(n), freq * 0.8, freq * 4) * 0.12
    e = env_adsr(n, 0.07, 0.15, 0.75, min(0.25, dur * 0.4))
    # 笛膜的嗡嗡聲：一點點高頻雜訊
    return (tone + breath) * e


def drone(freq: float, dur: float) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = sum(a * np.sin(2 * np.pi * freq * m * t + m) for m, a in [(1, 1.0), (1.5, 0.35), (2, 0.25), (3, 0.08)])
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.07 * t)
    return x * env_adsr(n, 3.0, 0.1, 1.0, 3.0)


def bell(freq: float, dur: float, partials=((1, 1), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)), tau: float = 1.2) -> np.ndarray:
    """磬／編鐘：非諧和泛音，高的衰減快。"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, amp in partials:
        x += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * ratio / tau)
    return x * env_adsr(n, 0.002, 0.0, 1.0, 0.05)


def gong(freq: float, dur: float, rng: np.random.Generator) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(14):
        ratio = 1 + k * 0.37 + rng.uniform(-0.05, 0.05)
        sweep = 1 + 0.02 * np.exp(-t * 2)  # 鑼聲先低後揚
        x += np.sin(2 * np.pi * freq * ratio * sweep * t + rng.uniform(0, 6)) * np.exp(-t / (dur * 0.35)) / (1 + k * 0.4)
    x += lowpass(rng.standard_normal(n), 2500) * np.exp(-t * 18) * 0.6
    return x


def frame_drum(dur: float, rng: np.random.Generator, pitch: float = 70) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = pitch * (1 + 1.2 * np.exp(-t * 30))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    skin = lowpass(rng.standard_normal(n), 1800) * np.exp(-t * 45) * 0.5
    return body + skin


def woodblock(freq: float = 900, dur: float = 0.25) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 2.3 * t)) * np.exp(-t * 40)


def whoosh(dur: float, rng: np.random.Generator, lo: float, hi: float, rise: bool = True) -> np.ndarray:
    """帶通雜訊掃頻：衣袂風聲、劍風。"""
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    hop = 256
    out = np.zeros(n)
    win = np.hanning(hop * 2)
    for start in range(0, n - hop * 2, hop):
        k = start / max(1, n - hop * 2)
        k = k if rise else 1 - k
        centre = lo * (hi / lo) ** k
        seg = noise[start: start + hop * 2] * win
        out[start: start + hop * 2] += bandpass(seg, centre * 0.6, centre * 1.6)
    t = np.linspace(0, 1, n)
    return out * np.sin(np.pi * t) ** 1.5


# ---------- 曲式 ----------

A4 = 440.0


def midi(m: float) -> float:
    return A4 * 2 ** ((m - 69) / 12)


def pentatonic(tonic: int, mode: int, lo: int, hi: int) -> list[int]:
    """mode：0 宮 1 商 2 角 3 徵 4 羽（從第幾音起算主音）。回傳 lo..hi 之間的 MIDI 音。"""
    gong_steps = [0, 2, 4, 7, 9]
    base = tonic - gong_steps[mode]  # 宮音
    notes = []
    for octave in range(-2, 5):
        for s in gong_steps:
            m = base + 12 * octave + s
            if lo <= m <= hi:
                notes.append(m)
    return sorted(notes)


def melody(rng: np.random.Generator, scale: list[int], tonic: int, bars: int, beats_per_bar: int,
           rhythm: list[list[float]], motif: list[tuple[int, float]], leap: float = 0.25) -> list[tuple[float, float, int]]:
    """隨機漫步旋律，句尾回到主音或五度；每 8 小節的開頭奏一次地區動機。回傳 [(起拍, 拍長, midi)]。"""
    notes = []
    home = min(range(len(scale)), key=lambda i: abs(scale[i] - tonic))
    idx = home
    beat = 0.0
    for bar in range(bars):
        if bar % 8 == 0:
            # 地區動機（M4）：從主音起算的音階級數與拍長
            for step, length in motif:
                idx = int(np.clip(home + step, 0, len(scale) - 1))
                notes.append((beat, length, scale[idx]))
                beat += length
            beat = (bar + 1) * beats_per_bar
            continue
        pattern = rhythm[rng.integers(len(rhythm))]
        phrase_end = bar % 4 == 3
        for k, length in enumerate(pattern):
            last = k == len(pattern) - 1
            if phrase_end and last:
                targets = [i for i, m in enumerate(scale) if (m - tonic) % 12 in (0, 7)]
                idx = min(targets, key=lambda i: abs(i - idx))
            else:
                step = rng.choice([-1, 1, -1, 1, 0]) if rng.random() > leap else rng.choice([-3, -2, 2, 3])
                idx = int(np.clip(idx + step, 0, len(scale) - 1))
            if rng.random() < 0.12 and not last:
                beat += length  # 留白
                continue
            notes.append((beat, length, scale[idx]))
            beat += length
        beat = (bar + 1) * beats_per_bar
    return notes


def motif_notes(spec: dict, motif: list[tuple[int, float]]) -> list[tuple[float, float, int]]:
    """把動機換成 [(起拍, 拍長, midi)]，用在短樂句。"""
    scale = pentatonic(spec["tonic"], spec["mode"], spec["tonic"] - 12, spec["tonic"] + 24)
    home = scale.index(spec["tonic"])
    out, beat = [], 0.0
    for step, length in motif:
        out.append((beat, length, scale[int(np.clip(home + step, 0, len(scale) - 1))]))
        beat += length
    return out


def render(events, total: int) -> np.ndarray:
    out = np.zeros(total)
    for start, sig in events:
        s = int(start * SR)
        if s >= total:
            continue
        e = min(total, s + len(sig))
        out[s:e] += sig[: e - s]
    return out


def loop_fade(x: np.ndarray, seconds: float = 2.5) -> np.ndarray:
    """讓循環接縫不突兀：尾巴淡出，開頭短淡入。"""
    n = int(seconds * SR)
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)[:, None] if x.ndim == 2 else np.linspace(1, 0, n)
    m = int(0.4 * SR)
    x[:m] *= np.linspace(0, 1, m)[:, None] if x.ndim == 2 else np.linspace(0, 1, m)
    return x


def crossfade_loop(x: np.ndarray, seconds: float = 3.0) -> np.ndarray:
    """環境音無縫循環：尾巴疊回開頭再截掉。"""
    n = int(seconds * SR)
    body, tail = x[:-n].copy(), x[-n:]
    ramp = np.linspace(0, 1, n)
    body[:n] = body[:n] * ramp + tail * (1 - ramp)
    return body


def ambience(kind: str, seconds: float, rng: np.random.Generator) -> np.ndarray:
    """底層環境：風、溪水、鳥、蟲。"""
    n = int((seconds + 3) * SR)
    t = np.arange(n) / SR
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 11 + 1) * np.sin(2 * np.pi * t / 4.3)
    wind = lowpass(rng.standard_normal(n), 380 if kind != "heifeng" else 260) * gust
    x = wind * (1.6 if kind == "heifeng" else 0.8)
    if kind in ("foothills", "sect"):
        # 遠處的鳥：短促上揚的口哨音
        for _ in range(int(seconds / 5)):
            s = rng.uniform(0, seconds)
            d = rng.uniform(0.08, 0.18)
            m = int(d * SR)
            tt = np.arange(m) / SR
            f = rng.uniform(2600, 3800) * (1 + 0.25 * tt / d)
            chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / d) * 0.05
            for rep in range(rng.integers(1, 4)):
                k = int((s + rep * d * 1.6) * SR)
                if k + m < n:
                    x[k:k + m] += chirp
    if kind == "foothills":
        x += bandpass(rng.standard_normal(n), 900, 5000) * 0.18 * (0.8 + 0.2 * np.sin(2 * np.pi * t / 3.1))
    if kind == "illusion":
        # 不穩的低鳴
        x += np.sin(2 * np.pi * 55 * t * (1 + 0.004 * np.sin(2 * np.pi * 0.13 * t))) * 0.15
    if kind == "heifeng":
        x += bandpass(rng.standard_normal(n), 1800, 4000) * 0.05 * (np.sin(2 * np.pi * t / 7) > 0.6)
    return crossfade_loop(x)


## 各區設定：主音、調式、速度、動機（音階級數, 拍長）。各區主音都在 D 宮系的五聲音裡，短樂句不打架。
REGIONS = {
    "qingyun_sect": dict(name="青雲宗", seed=11, bpm=62, tonic=62, mode=0, lead="pluck", rhythm="SLOW",
                         drone=38, accompany="sparse", bells=True, drums=False, reverb_s=4.5, wet=0.42,
                         ambience="sect", motif=[(0, 1), (2, 1), (3, 2), (2, 2)]),
    "qingyun_foothills": dict(name="青雲山腳", seed=23, bpm=84, tonic=67, mode=3, lead="flute", rhythm="FLOWING",
                              drone=None, accompany="arpeggio", bells=False, drums=False, reverb_s=3.0, wet=0.3,
                              ambience="foothills", motif=[(0, 0.5), (1, 0.5), (2, 1), (4, 1), (3, 1)]),
    "heifeng_ridge": dict(name="黑風嶺", seed=37, bpm=72, tonic=57, mode=4, lead="pluck", rhythm="TENSE",
                          drone=33, accompany="pulse", bells=False, drums=True, reverb_s=3.0, wet=0.3,
                          ambience="heifeng", motif=[(0, 1.5), (-1, 0.5), (-3, 1), (-2, 1)]),
}
ILLUSION = dict(name="心魔幻境", seed=53, bpm=54, tonic=64, mode=4, lead="flute", rhythm="SLOW", drone=40,
                accompany="sparse", bells=True, drums=True, reverb_s=6.0, wet=0.55, ambience="illusion")
RHYTHMS = {
    "SLOW": [[2, 2], [1, 1, 2], [3, 1], [1.5, 0.5, 2], [4]],
    "FLOWING": [[1, 1, 1, 1], [0.5, 0.5, 1, 2], [1, 0.5, 0.5, 2], [2, 1, 1], [1.5, 0.5, 1, 1]],
    "TENSE": [[1, 1, 2], [0.5, 0.5, 0.5, 0.5, 2], [3, 1], [2, 0.5, 0.5, 1]],
}
GAP_SECONDS = 12.0   # 每圈結尾只剩環境的留白（M2）


def inverted(motif):
    """心魔幻境：所在地區動機的倒影（音程上下翻轉）。"""
    return [(-step, length) for step, length in motif]


def layered_track(spec: dict, seconds: float, motif) -> dict:
    """回傳三層 stem：melody（旋律＋伴奏）、rhythm（鼓、鑼、磬），長度一樣、同步播放；base 另外算。"""
    rng = np.random.default_rng(spec["seed"])
    beat_s = 60 / spec["bpm"]
    tonic, mode = spec["tonic"], spec["mode"]
    music_s = seconds - GAP_SECONDS
    bars = int(music_s / (beat_s * 4))
    total = int(seconds * SR)
    hi_scale = pentatonic(tonic, mode, tonic - 5, tonic + 17)
    lo_scale = pentatonic(tonic - 12, mode, tonic - 17, tonic + 2)
    ev_lead, ev_acc, ev_perc = [], [], []

    for b, length, m in melody(rng, hi_scale, tonic, bars - 1, 4, RHYTHMS[spec["rhythm"]], motif):
        t = b * beat_s
        d = length * beat_s
        if spec["lead"] == "flute":
            ev_lead.append((t, flute(midi(m), d * 0.95 + 0.15, rng) * 0.5))
        else:
            slide = 2.0 if (rng.random() < 0.2 and d > beat_s * 1.4) else 0.0
            ev_lead.append((t, pluck(midi(m), max(d, 1.2) + 1.5, rng, bright=0.45, decay=0.998, slide=slide) * 0.7))

    chord_roots = [0, 0, -5, -3] if mode in (0, 3) else [0, -2, -5, 0]
    for bar in range(bars):
        root = min(lo_scale, key=lambda m: abs(m - (tonic - 12 + chord_roots[bar % 4])))
        bar_t = bar * 4 * beat_s
        acc = spec["accompany"]
        if acc == "arpeggio":
            for k, m in enumerate([root, root + 7, root + 12, root + 14, root + 12, root + 7]):
                m = min(lo_scale + hi_scale, key=lambda x: abs(x - m))
                ev_acc.append((bar_t + k * beat_s * 2 / 3, pluck(midi(m), 2.2, rng, bright=0.3, decay=0.997) * 0.28))
        elif acc == "sparse":
            ev_acc.append((bar_t, pluck(midi(root), 4.0, rng, bright=0.25, decay=0.999) * 0.4))
            if rng.random() < 0.6:
                ev_acc.append((bar_t + 2 * beat_s, pluck(midi(root + 7), 3.0, rng, bright=0.25, decay=0.999) * 0.25))
        elif acc == "pulse":
            for k in range(4):
                if k == 0 or rng.random() < 0.4:
                    ev_acc.append((bar_t + k * beat_s, pluck(midi(root), 1.8, rng, bright=0.2, decay=0.995) * 0.35))
        if spec["drums"]:
            ev_perc.append((bar_t, frame_drum(1.2, rng, 62) * 0.8))
            ev_perc.append((bar_t + 2.5 * beat_s, frame_drum(1.0, rng, 70) * 0.45))
            if bar % 2 == 1:
                ev_perc.append((bar_t + 3.5 * beat_s, frame_drum(0.8, rng, 78) * 0.35))
            if bar % 8 == 0:
                ev_perc.append((bar_t, gong(110, 6.0, rng) * 0.25))
        else:
            # 沒有鼓的地區：節奏層用木魚與輕手鼓，危險時才進來
            ev_perc.append((bar_t, frame_drum(0.9, rng, 75) * 0.35))
            ev_perc.append((bar_t + 2 * beat_s, woodblock(700) * 0.25))
            if bar % 2 == 1:
                ev_perc.append((bar_t + 3 * beat_s, woodblock(820) * 0.18))
        if spec["bells"] and bar % 4 == 0:
            ev_perc.append((bar_t + beat_s * rng.integers(0, 3), bell(midi(tonic + 12), 4.0) * 0.18))

    stems = {
        "melody": render(ev_lead, total) + render(ev_acc, total),
        "rhythm": render(ev_perc, total),
    }
    out = {}
    for name, x in stems.items():
        st = reverb(x, spec["reverb_s"], spec["wet"], np.random.default_rng(spec["seed"] + 1))
        out[name] = loop_fade(st)
    return out


def base_layer(spec: dict, seconds: float) -> np.ndarray:
    rng = np.random.default_rng(spec["seed"] + 7)
    x = ambience(spec["ambience"], seconds, rng)
    if spec["drone"] is not None:
        t = np.arange(len(x)) / SR
        d = sum(a * np.sin(2 * np.pi * midi(spec["drone"]) * m * t + m) for m, a in [(1, 1.0), (1.5, 0.35), (2, 0.25)])
        x = x + d * (0.85 + 0.15 * np.sin(2 * np.pi * t / seconds * 3)) * 0.35
    return reverb(x, 2.0, 0.2, rng)


def mix_level(stems: dict) -> float:
    """三層合起來調到 -20 dB RMS 要乘的倍數，三層一起乘，比例不變。"""
    n = min(len(s) for s in stems.values())
    full = sum(s[:n] for s in stems.values())
    return 10 ** (-20 / 20) / (np.sqrt(np.mean(full ** 2)) + 1e-9)


def limit(x: np.ndarray) -> np.ndarray:
    return np.tanh(x * 1.1) / np.tanh(1.1) * 0.92


def make_music(seconds: float) -> None:
    print("配樂（三層：base 環境＋持續音、melody 琴笛、rhythm 鼓鑼）：")
    out = OUT / "music"
    for key, spec in REGIONS.items():
        stems = layered_track(spec, seconds, spec["motif"])
        base = base_layer(spec, seconds / 2)
        g = mix_level({"base": base, **stems})
        write_ogg(out / f"{key}_base.ogg", limit(base * g), quality=3)
        for name, x in stems.items():
            # 節奏層單聲道就夠，檔案小一半
            write_ogg(out / f"{key}_{name}.ogg", limit((x.mean(axis=1) if name == "rhythm" else x) * g), quality=3)
        print(f"  {spec['name']}")
    # 心魔幻境：底層與節奏層共用，旋律用所在地區動機的倒影，各區一版
    seconds_ill = seconds * 0.75
    first = None
    for key, spec in REGIONS.items():
        stems = layered_track({**ILLUSION, "seed": ILLUSION["seed"] + len(first or {})}, seconds_ill, inverted(spec["motif"]))
        if first is None:
            first = stems
            base = base_layer(ILLUSION, seconds_ill / 2)
            g = mix_level({"base": base, **stems})
            write_ogg(out / "illusion_base.ogg", limit(base * g), quality=3)
            write_ogg(out / "illusion_rhythm.ogg", limit(stems["rhythm"].mean(axis=1) * g), quality=3)
        write_ogg(out / f"illusion_melody_{key}.ogg", limit(stems["melody"] * g), quality=3)
    print("  心魔幻境（旋律三版：各區動機倒影）")


def make_stingers() -> None:
    """短樂句（M3）與動機音（M4）：每區用自己的調與動機。遊戲裡對齊配樂拍點再播。"""
    print("短樂句：")
    out = OUT / "stingers"
    specs = {**REGIONS, "illusion": {**ILLUSION, "motif": inverted(REGIONS["qingyun_sect"]["motif"])}}
    for key, spec in specs.items():
        rng = np.random.default_rng(spec["seed"] + 100)
        beat = 60 / spec["bpm"]
        motif = motif_notes(spec, spec["motif"])
        lead = (lambda f, d: flute(f, d, rng) * 0.6) if spec["lead"] == "flute" else (lambda f, d: pluck(f, d + 1.5, rng, bright=0.5, decay=0.998))

        def phrase(notes, speed=1.0, octave=0):
            return [(b * beat * speed, lead(midi(m + octave), max(0.25, l * beat * speed))) for b, l, m in notes]

        def finish(events, seconds, wet=0.4):
            x = render(events, int(seconds * SR))
            return normalize(loop_fade(reverb(x, spec["reverb_s"], wet, rng), 0.8), -2.0)

        root = midi(spec["tonic"] - 12)
        # 事件開始：刮奏上行接動機
        gl = [(k * 0.04, pluck(midi(m), 1.4, rng, bright=0.6) * 0.4)
              for k, m in enumerate(pentatonic(spec["tonic"], spec["mode"], spec["tonic"] - 12, spec["tonic"] + 7))]
        write_ogg(out / f"{key}_event_start.ogg", finish(gl + [(0.45 + s, x) for s, x in phrase(motif, 0.6)], 3.5))
        # 事件完成：動機慢一點＋主音磬
        end_t = sum(l for _, l, _ in motif) * beat * 0.8
        write_ogg(out / f"{key}_event_end.ogg", finish(phrase(motif, 0.8) + [(end_t, bell(midi(spec["tonic"] + 12), 2.5) * 0.6),
                                                                          (end_t, pluck(root, 3.0, rng, decay=0.999) * 0.6)], end_t + 3.0))
        # 突破：鑼＋動機高八度＋上行鐘
        ev = [(0, gong(root, 4.0, rng) * 0.5)] + [(0.3 + s, x) for s, x in phrase(motif, 0.5, 12)]
        ev += [(1.4 + k * 0.1, bell(midi(m), 2.0, tau=0.9) * 0.35)
               for k, m in enumerate(pentatonic(spec["tonic"] + 12, spec["mode"], spec["tonic"] + 12, spec["tonic"] + 26))]
        write_ogg(out / f"{key}_breakthrough.ogg", finish(ev, 4.0))
        # 傳送／NPC 開口：只奏動機（M4）
        write_ogg(out / f"{key}_motif.ogg", finish(phrase(motif, 0.5), sum(l for _, l, _ in motif) * beat * 0.5 + 1.8, 0.3))
    # 心魔現身：低鑼＋倒影動機＋不協和磬
    spec = specs["illusion"]
    rng = np.random.default_rng(999)
    beat = 60 / spec["bpm"]
    ev = [(0, gong(midi(spec["tonic"] - 24), 4.5, rng) * 0.7), (0, frame_drum(1.5, rng, 50))]
    ev += [(0.6 + b * beat * 0.6, flute(midi(m - 12), l * beat * 0.6 + 0.2, rng) * 0.5) for b, l, m in motif_notes(spec, spec["motif"])]
    ev += [(1.8, bell(midi(spec["tonic"] + 1), 2.5) * 0.3)]
    x = render(ev, int(4.5 * SR))
    write_ogg(out / "heart_demon.ogg", normalize(loop_fade(reverb(x, 5.0, 0.5, rng), 0.8), -2.0))
    print("  各區 event_start、event_end、breakthrough、motif；heart_demon")


# ---------- 音效 ----------

def sfx_variants(name: str, count: int, make) -> None:
    for i in range(count):
        rng = np.random.default_rng(zlib.crc32(name.encode()) % 10000 + i * 7919)
        x = make(rng, i)
        x = x - np.mean(x)
        write_ogg(OUT / "sfx" / f"{name}_{i + 1}.ogg", normalize(x, -2.0), quality=5)


def make_sfx() -> None:
    print("音效：")

    def jump(rng, i):
        return whoosh(0.22, rng, 300 + 60 * i, 1500 + 200 * i)

    def double_jump(rng, i):  # 輕身術：風聲＋清亮一點
        x = whoosh(0.32, rng, 500, 3500) * 0.8
        return x + np.pad(bell(midi(84 + 2 * i), 0.3, tau=0.4) * 0.25, (int(0.03 * SR), 0))[: len(x)]

    def wall_jump(rng, i):  # 踏葉：一下輕踏＋葉聲
        n = int(0.28 * SR)
        t = np.arange(n) / SR
        tap = lowpass(rng.standard_normal(n), 900) * np.exp(-t * 60)
        leaves = bandpass(rng.standard_normal(n), 2500, 8000) * np.exp(-t * 14) * 0.35 * (rng.random(n) > 0.6)
        return tap + leaves + whoosh(0.28, rng, 400, 2000) * 0.5

    def flight(rng, i):  # 御劍：劍鳴＋破風
        n = int(0.9 * SR)
        t = np.arange(n) / SR
        ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(1320 + 40 * i, 1), (2640, 0.3), (3700, 0.15)])
        ring *= np.exp(-t * 3.5) * (1 + 0.3 * np.sin(2 * np.pi * 9 * t))
        return ring * 0.35 + whoosh(0.9, rng, 250, 2500) * 0.9

    def land(rng, i):
        n = int(0.15 * SR)
        t = np.arange(n) / SR
        return lowpass(rng.standard_normal(n), 500) * np.exp(-t * 45)

    def attack(rng, i):  # 劍風：快速下掃
        x = whoosh(0.2 + 0.03 * i, rng, 3500, 700, rise=True)
        return x + whoosh(0.2 + 0.03 * i, rng, 6000, 2000) * 0.3

    def hit(rng, i):  # 擊中：悶擊＋短促金屬
        n = int(0.3 * SR)
        t = np.arange(n) / SR
        thud = np.sin(2 * np.pi * (110 + 25 * i) * t * (1 + np.exp(-t * 40))) * np.exp(-t * 18)
        crack = bandpass(rng.standard_normal(n), 1500, 6000) * np.exp(-t * 70)
        return thud + crack * 0.7

    def hurt(rng, i):
        n = int(0.4 * SR)
        t = np.arange(n) / SR
        thud = np.sin(2 * np.pi * 70 * t * (1 + 0.8 * np.exp(-t * 25))) * np.exp(-t * 10)
        return thud + lowpass(rng.standard_normal(n), 800) * np.exp(-t * 30) * 0.5

    def defeat(rng, i):  # 敵人消散：下滑的氣聲
        return whoosh(0.6, rng, 2500, 200, rise=True) + bell(midi(57), 0.6, tau=0.5)[: int(0.6 * SR)] * 0.2

    def event_start(rng, i):  # 事件觸發：古箏刮奏上行
        notes = pentatonic(62 + 2 * i, 0, 62, 86)
        ev = [(k * 0.045, pluck(midi(m), 1.6, rng, bright=0.6) * 0.5) for k, m in enumerate(notes)]
        x = render(ev, int(2.2 * SR))
        return reverb(x, 2.5, 0.35, rng).mean(axis=1)

    def event_end(rng, i):  # 事件結束：兩聲磬
        x = render([(0, bell(midi(74), 2.5)), (0.35, bell(midi(81), 2.2) * 0.7)], int(2.8 * SR))
        return reverb(x, 2.5, 0.3, rng).mean(axis=1)

    def reward(rng, i):  # 得寶：三聲上行小鐘
        base = [72, 76, 79][i % 3]
        ev = [(k * 0.09, bell(midi(m), 1.2, tau=0.6) * (0.8 - 0.15 * k))
              for k, m in enumerate(pentatonic(base, 0, base, base + 12)[:3])]
        return render(ev, int(1.5 * SR))

    def breakthrough(rng, i):  # 突破：鑼＋上行鐘聲
        x = gong(98, 4.0, rng) * 0.6
        ev = [(0.4 + k * 0.12, bell(midi(m), 2.0, tau=0.9) * 0.4) for k, m in enumerate([62, 67, 69, 74, 79, 81, 86])]
        x = x + render(ev, len(x))
        return reverb(x, 3.5, 0.35, rng).mean(axis=1)

    def meditate(rng, i):  # 打坐：頌缽
        return bell(midi(57), 3.5, partials=((1, 1), (2.71, 0.5), (5.15, 0.2)), tau=2.5) * (
            1 + 0.15 * np.sin(2 * np.pi * 4 * np.arange(int(3.5 * SR)) / SR))

    def travel(rng, i):  # 傳送：風＋一聲磬
        x = whoosh(1.0, rng, 300, 3000)
        return x * 0.8 + render([(0.45, bell(midi(79), 0.55) * 0.4)], len(x))

    def ui_tick(rng, i):  # 翻頁、選項
        return woodblock(820 + 80 * i, 0.15)

    for name, count, fn in [("jump", 2, jump), ("double_jump", 2, double_jump), ("wall_jump", 2, wall_jump),
                            ("flight", 2, flight), ("land", 2, land), ("attack", 3, attack), ("hit", 3, hit),
                            ("hurt", 2, hurt), ("defeat", 1, defeat), ("event_start", 1, event_start),
                            ("event_end", 1, event_end), ("reward", 2, reward), ("breakthrough", 1, breakthrough),
                            ("meditate", 1, meditate), ("travel", 1, travel), ("ui_tick", 2, ui_tick)]:
        sfx_variants(name, count, fn)
        print(f"  {name} ×{count}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["music", "sfx", "stingers"])
    ap.add_argument("--seconds", type=float, default=96)
    args = ap.parse_args()
    if args.only in (None, "music"):
        make_music(args.seconds)
    if args.only in (None, "sfx"):
        make_sfx()
    if args.only is None or args.only == "stingers":
        make_stingers()


if __name__ == "__main__":
    main()
