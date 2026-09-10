#!/usr/bin/env python3
"""合成音效：消除/交换/魔力花。正弦+泛音+指数衰减，无版权问题。"""
import os
import numpy as np
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    samples = samples / max(np.abs(samples).max(), 1e-6) * 0.85
    pcm = (samples * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name} saved")


def tone(freq, dur, decay=6.0, harmonics=((1, 1.0), (2, 0.35), (3, 0.12))):
    t = np.arange(int(SR * dur)) / SR
    s = sum(a * np.sin(2 * np.pi * freq * h * t) for h, a in harmonics)
    return s * np.exp(-decay * t)


def chirp(f0, f1, dur, decay=18.0):
    t = np.arange(int(SR * dur)) / SR
    phase = 2 * np.pi * (f0 * t + (f1 - f0) * t * t / (2 * dur))
    return np.sin(phase) * np.exp(-decay * t)


def main():
    # pop.wav：清亮的"绽放"钟声 (E6)，连锁时用 pitch_scale 升调
    write_wav("pop.wav", tone(1318.5, 0.3, decay=9.0))

    # swap.wav：短促上滑音 + 轻噪声
    t = np.arange(int(SR * 0.1)) / SR
    noise = np.random.default_rng(7).normal(0, 0.25, len(t)) * np.exp(-40 * t)
    write_wav("swap.wav", chirp(500, 900, 0.1) * 0.6 + noise)

    # magic.wav：上行琶音 C5-E5-G5-C6 星光感
    arp = np.concatenate([tone(f, 0.28, decay=5.0) for f in
                          (523.3, 659.3, 784.0, 1046.5)])
    write_wav("magic.wav", arp)

    # line.wav：行列消除的"扫过"音 (下滑 chirp + 钟)
    write_wav("line.wav", chirp(1400, 500, 0.18, decay=10.0) * 0.7
              + np.pad(tone(1046.5, 0.15, decay=8.0), (int(SR * 0.08), 0))[:int(SR * 0.18)])

    # boom.wav：范围爆炸的低频砰 + 噪声冲击
    t = np.arange(int(SR * 0.35)) / SR
    thud = np.sin(2 * np.pi * (90 - 45 * t) * t) * np.exp(-9 * t)
    noise = np.random.default_rng(3).normal(0, 0.5, len(t)) * np.exp(-14 * t)
    write_wav("boom.wav", thud * 1.2 + noise)


if __name__ == "__main__":
    main()
