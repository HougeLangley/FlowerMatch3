#!/usr/bin/env python3
"""合成花消消乐全套音效：FM 铃声 / 拨弦 / 噪声扫频 / 颗粒星光 / 轻混响。
全部代码合成，无版权问题；44.1kHz 单声道 16bit WAV。
用法：python3 tools/gen_sounds.py
"""
import os
import numpy as np
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")

# 音名频率（C 大调 + 五声音阶）
C5, D5, E5, G5, A5 = 523.25, 587.33, 659.26, 783.99, 880.00
C6, E6, G6, B6 = 1046.50, 1318.51, 1567.98, 1975.53
A4, F4, D4 = 440.00, 349.23, 293.66
PENTA = [C5, D5, E5, G5, A5, C6]


def _t(dur):
    return np.arange(int(SR * dur)) / SR


def _pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def _sum(*parts):
    """多段叠加（自动按最长对齐，避免长度不一致广播报错）"""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out += _pad_to(p, n)
    return out


def _mix_at(base, x, at):
    """把 x 叠加到 base 的 at 秒处（base 自动加长）"""
    n = int(SR * at)
    need = n + len(x)
    if len(base) < need:
        base = np.concatenate([base, np.zeros(need - len(base))])
    base[n:need] += x
    return base


def fm_bell(freq, dur, ratio=3.5, index=3.0, decay=6.0, index_decay=None):
    """FM 钟/马林巴：调制器指数衰减 → 通透的"叮"，ratio 决定音色明暗"""
    t = _t(dur)
    if index_decay is None:
        index_decay = decay * 1.3
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * np.exp(-index_decay * t)
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-decay * t)


def pluck(freq, dur, decay=5.0):
    """拨弦/木琴：高次泛音衰减更快 → 木质质感"""
    t = _t(dur)
    s = np.zeros_like(t)
    for h in range(1, 9):
        s += (1.0 / h ** 1.3) * np.sin(2 * np.pi * freq * h * t) \
            * np.exp(-decay * (1 + 0.55 * h) * t)
    return s


def chirp(f0, f1, dur, decay=16.0):
    """正弦扫频（上滑/下滑）"""
    t = _t(dur)
    phase = 2 * np.pi * (f0 * t + (f1 - f0) * t * t / (2 * dur))
    return np.sin(phase) * np.exp(-decay * t)


def noise_burst(dur, decay=40.0, seed=0, gain=1.0):
    rng = np.random.default_rng(seed)
    return rng.normal(0, 1, int(SR * dur)) * np.exp(-decay * _t(dur)) * gain


def band_noise(dur, fc, bw, seed=0):
    """带通噪声（FFT 高斯窗）"""
    n = int(SR * dur)
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.normal(0, 1, n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spectrum *= np.exp(-((freqs - fc) / bw) ** 2)
    return np.fft.irfft(spectrum, n)


def noise_sweep(dur, f0, f1, decay=5.0, seed=0):
    """滤波噪声扫频（whoosh）：5ms 分块逐段带通，中心频率指数插值"""
    n = int(SR * dur)
    seg = int(SR * 0.005)
    rng = np.random.default_rng(seed)
    noise = rng.normal(0, 1, n)
    out = np.zeros(n)
    freqs = np.fft.rfftfreq(seg, 1 / SR)
    for i in range(0, n - seg + 1, seg):
        prog = i / max(n - 1, 1)
        fc = f0 * (f1 / f0) ** prog
        spectrum = np.fft.rfft(noise[i:i + seg]) * np.exp(-((freqs - fc) / (fc * 0.6)) ** 2)
        out[i:i + seg] = np.fft.irfft(spectrum, seg)
    return out * np.exp(-decay * _t(dur))


def sparkle(dur, base=3000.0, count=16, seed=1):
    """星光颗粒：随机稀疏的高频小铃"""
    n = int(SR * dur)
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    gl = int(SR * 0.07)
    t_g = _t(0.07)
    for _ in range(count):
        f = base * rng.uniform(0.65, 1.7)
        start = int(SR * rng.uniform(0.0, dur * 0.55))
        tone = np.sin(2 * np.pi * f * t_g) * np.exp(-22.0 * t_g) * rng.uniform(0.25, 0.7)
        out[start:start + gl] += tone[:max(0, n - start)]
    return out


def reverb(x, mix=0.3, rt=0.16, seed=5):
    """轻混响：衰减噪声脉冲响应卷积（房间感，高频压暗更暖）"""
    n_ir = int(SR * rt * 3)
    rng = np.random.default_rng(seed)
    t_ir = np.arange(n_ir) / SR
    ir = rng.normal(0, 1, n_ir) * np.exp(-t_ir / rt)
    spectrum = np.fft.rfft(ir)
    freqs = np.fft.rfftfreq(n_ir, 1 / SR)
    spectrum *= np.exp(-(freqs / 5000.0) ** 2)
    ir = np.fft.irfft(spectrum, n_ir)
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9  # 单位能量，湿声与干声量级相当
    wet = np.convolve(x, ir, mode="full")[:len(x)]
    return x + mix * wet


def save(name, samples, peak):
    """归一化到目标峰值 + 首尾 4ms 淡入淡出（防爆音）"""
    x = np.nan_to_num(np.asarray(samples, dtype=float))
    x = x / max(np.abs(x).max(), 1e-9) * peak
    fade = min(int(SR * 0.004), len(x) // 4)
    if fade > 1:
        x[:fade] *= np.linspace(0.0, 1.0, fade)
        x[-fade:] *= np.linspace(1.0, 0.0, fade)
    pcm = np.clip(x * 32767, -32768, 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name:14s} {len(x) / SR * 1000:5.0f}ms  peak={peak}")


def main():
    # ---- 消除：三款"绽放"音色变体（同一音高不同瞬态，连续消除不重复）----
    save("pop_a.wav",
         _sum(fm_bell(C6, 0.32, ratio=3.5, index=2.6, decay=7.0),
              0.25 * sparkle(0.30, 3600, 12, seed=11)), 0.80)
    save("pop_b.wav",
         _sum(fm_bell(C6, 0.36, ratio=2.0, index=4.0, decay=6.0),
              0.30 * pluck(E6, 0.30, decay=8.0)), 0.78)
    save("pop_c.wav",
         _sum(0.85 * pluck(C6, 0.34, decay=5.0),
              0.50 * fm_bell(E6, 0.28, ratio=1.5, index=1.8, decay=9.0),
              0.20 * sparkle(0.26, 4200, 10, seed=13)), 0.80)

    # ---- 交换：轻快上滑"啵" + 极轻木击 ----
    save("swap.wav",
         _sum(chirp(520, 900, 0.11, decay=14.0) * 0.9,
              noise_burst(0.11, decay=70.0, seed=3, gain=0.18)), 0.50)

    # ---- 无效交换：两声柔和下行音（礼貌的"不行哦"，不刺耳）----
    inv = np.zeros(int(SR * 0.26))
    inv = _mix_at(inv, fm_bell(A4, 0.20, ratio=2.0, index=1.2, decay=10.0), 0.0)
    inv = _mix_at(inv, fm_bell(F4, 0.20, ratio=2.0, index=1.2, decay=9.0), 0.09)
    save("invalid.wav", inv, 0.50)

    # ---- 魔力花：C 大调琶音 + 星光 + 混响（清盘时刻的魔法感）----
    mag = np.zeros(int(SR * 1.0))
    for i, f in enumerate(PENTA):
        mag = _mix_at(mag, fm_bell(f, 0.55, ratio=3.0, index=2.2, decay=6.5), 0.085 * i)
    mag = _sum(mag, 0.25 * sparkle(0.9, 3200, 18, seed=21))
    save("magic.wav", reverb(mag, mix=0.30), 0.72)

    # ---- 行列花：噪声扫频 whoosh + 钟声点缀 ----
    lin = noise_sweep(0.40, 3600, 350, decay=6.0, seed=31) * 0.9
    lin = _mix_at(lin, fm_bell(C6, 0.30, ratio=2.8, index=2.0, decay=8.0), 0.04)
    lin = _sum(lin, 0.2 * sparkle(0.30, 3000, 8, seed=33))
    save("line.wav", reverb(lin, mix=0.18), 0.62)

    # ---- 爆炸花：低频砰 + 隆隆噪声 + 碎屑，短混响增加体量 ----
    t = _t(0.60)
    thud = np.sin(2 * np.pi * (150 * t - (150 - 36) * t * t / (2 * 0.60))) * np.exp(-7.0 * t)
    low = band_noise(0.60, 200, 220, seed=41) * np.exp(-9.0 * t)
    crack = noise_burst(0.50, decay=26.0, seed=43, gain=0.5) * 0.4
    boom = _sum(thud * 1.1, low * 0.9, crack, 0.25 * sparkle(0.50, 900, 10, seed=45))
    save("boom.wav", reverb(boom, mix=0.28), 0.85)

    # ---- 特殊花生成：三连上行闪亮小铃（"升级啦"）----
    sp = np.zeros(int(SR * 0.55))
    for i, f in enumerate((E6, G6, B6)):
        sp = _mix_at(sp, fm_bell(f, 0.42, ratio=4.2, index=2.6, decay=8.0), 0.055 * i)
    sp = _sum(sp, 0.35 * sparkle(0.50, 4200, 20, seed=51))
    save("special.wav", reverb(sp, mix=0.25), 0.70)

    # ---- 雪块破碎：冰裂（带通噪声 + 玻璃质感小叮 + 数粒碎裂）----
    br = band_noise(0.30, 3400, 1800, seed=61) * np.exp(-18.0 * _t(0.30)) * 0.8
    br = _sum(br, 0.5 * sparkle(0.28, 2600, 10, seed=63))
    rng = np.random.default_rng(65)
    for _ in range(4):
        br = _mix_at(br, noise_burst(0.03, decay=90.0, seed=int(rng.integers(1000)), gain=0.5),
                     float(rng.uniform(0.0, 0.10)))
    save("break.wav", br, 0.60)

    # ---- 重排：柔和旋风（噪声上扫）+ 轻铃点缀（死局自救反馈）----
    sw = noise_sweep(0.45, 600, 3000, decay=4.5, seed=91) * 0.8
    for i, f in enumerate((G5, A5, C6)):
        sw = _mix_at(sw, fm_bell(f, 0.35, ratio=3.0, index=2.0, decay=8.0) * 0.5, 0.06 * i)
    save("shuffle.wav", reverb(sw, mix=0.22), 0.62)

    # ---- 点选：极轻的"嗒"（短促、低音量）----
    save("select.wav", np.sin(2 * np.pi * 880 * _t(0.08)) * np.exp(-30.0 * _t(0.08)), 0.30)

    # ---- 过关：上行音阶 + 和弦收束 + 星光 + 混响 ----
    win = np.zeros(int(SR * 1.5))
    for i, f in enumerate((C5, E5, G5, A5, C6)):
        win = _mix_at(win, fm_bell(f, 0.70, ratio=3.0, index=2.4, decay=5.0), 0.15 * i)
    for f in (C6, E6, G6):
        win = _mix_at(win, fm_bell(f, 1.00, ratio=3.2, index=2.2, decay=4.0) * 0.8, 0.72)
    win = _sum(win, 0.30 * sparkle(1.4, 3600, 26, seed=71))
    save("win.wav", reverb(win, mix=0.35), 0.80)

    # ---- 星级：单颗清亮"叮"（实时跨过星级门槛时）----
    star = _sum(fm_bell(E6, 0.45, ratio=4.2, index=2.8, decay=7.0),
                0.30 * sparkle(0.45, 5200, 12, seed=81))
    save("star.wav", reverb(star, mix=0.22), 0.70)

    # ---- 未过关：柔和三音下行（遗憾但不沮丧）----
    lose = np.zeros(int(SR * 0.95))
    for i, f in enumerate((A4, F4, D4)):
        lose = _mix_at(lose, fm_bell(f, 0.50, ratio=2.0, index=1.4, decay=6.0), 0.13 * i)
    save("lose.wav", reverb(lose, mix=0.30), 0.55)


if __name__ == "__main__":
    print(f"生成音效到 {os.path.normpath(OUT)}")
    main()
