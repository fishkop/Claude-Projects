"""Erzeugt die Tonspur (build/audio.wav) synthetisch aus build/sfx.json:
treibender Beat, Galopp-Hufschlaege, Whooshes auf den Blenden, Drum-Hits auf den Text-Einschlaegen.
Keine fremden Samples -> frei von Rechten Dritter."""
import json
import sys
import wave
import numpy as np

SR = 44100
cfg = json.load(open(sys.argv[1]))
out_path = sys.argv[2]
N = int(cfg["duration"] * SR)
mix = np.zeros((N, 2))
rng = np.random.default_rng(3)


def add(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N:
        return
    sig = sig[: N - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    mix[i:i + len(sig), 0] += sig * gain * l * 1.414
    mix[i:i + len(sig), 1] += sig * gain * r * 1.414


def env(n, attack=0.002, decay=0.2):
    t = np.arange(n) / SR
    return np.minimum(1, t / attack) * np.exp(-t / decay)


def lowpass(x, cutoff):
    """Einpoliger Tiefpass; cutoff darf ein Array sein (Filter-Sweep)."""
    cutoff = np.broadcast_to(cutoff, x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def kick(dur=0.45, f0=150, f1=42):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.16)


def hat(dur=0.06):
    n = int(dur * SR); x = rng.standard_normal(n)
    x = x - lowpass(x, 7000)
    return x * env(n, 0.0005, 0.018)


def clap():
    n = int(0.25 * SR); x = rng.standard_normal(n)
    x = lowpass(x - lowpass(x, 900), 5000)
    e = env(n, 0.001, 0.07)
    for d in (0.0, 0.011, 0.022):  # typische Mehrfach-Transiente
        k = int(d * SR); e[k:k + 200] += 0.6
    return x * e


def hoof():
    n = int(0.12 * SR); t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 95 * t) * env(n, 0.001, 0.035)
    click = lowpass(rng.standard_normal(n), 2500) * env(n, 0.0005, 0.012)
    return body * 0.9 + click * 1.4


def whoosh(dur=0.45):
    n = int(dur * SR); t = np.arange(n) / SR
    x = rng.standard_normal(n)
    sweep = 300 + 5000 * np.sin(np.pi * t / dur) ** 2
    y = lowpass(x, sweep) - lowpass(x, sweep * 0.25)
    return y * np.sin(np.pi * t / dur) ** 1.5


def impact():
    n = int(1.2 * SR)
    noise = lowpass(rng.standard_normal(n), 1800) * env(n, 0.001, 0.25)
    return kick(1.2, 180, 38) * 1.2 + noise * 0.5


def tock():  # Schlaeger trifft Ball
    n = int(0.08 * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 1050 * t) + 0.6 * np.sin(2 * np.pi * 1730 * t)) * env(n, 0.0003, 0.012)


# 1) Beat: 128 BPM, startet mit "POLO"-Einschlag, Pause unter der Endcard-Landung
beat = 60 / 128
t = cfg["slams"][0]["t"]
while t < cfg["duration"] - 0.3:
    if not (8.62 < t < 9.1):
        add(kick(), t, 0.55)
        add(hat(), t + beat / 2, 0.25, 0.3)
        if int(round((t - cfg["slams"][0]["t"]) / beat)) % 2 == 1:
            add(clap(), t, 0.22, -0.1)
    t += beat
# 16tel-Hats fuer Drive
t = cfg["slams"][0]["t"]
while t < cfg["duration"] - 0.3:
    add(hat(0.03), t + beat / 4, 0.08, -0.4)
    add(hat(0.03), t + 3 * beat / 4, 0.08, -0.4)
    t += beat

# 2) Bass-Puls auf Achteln (Grundton A, Wechsel auf F / G)
roots = {0: 55.0, 4: 43.65, 6: 49.0}
t, step = cfg["slams"][0]["t"], 0
while t < 8.62:
    bar = int(step / 8) % 8
    f = roots[max(k for k in roots if k <= bar)]
    n = int(beat / 2 * SR); tt = np.arange(n) / SR
    saw = 2 * ((tt * f) % 1) - 1
    add(lowpass(saw, 400) * env(n, 0.003, 0.12), t, 0.35)
    t += beat / 2; step += 1

# 3) Galopp (Dreitakt) waehrend der Reiterszenen
for a, b, g in cfg["gallop"]:
    stride = 1 / 2.3
    t = a
    while t < b:
        for k, d in enumerate((0.0, 0.07, 0.14)):
            add(hoof(), t + d, g * (0.55 + 0.15 * k), -0.2 + 0.2 * k)
        t += stride

# 4) Effekte
add(tock(), cfg["ballHit"], 0.9, -0.6)
add(whoosh(0.5), cfg["ballHit"], 0.5, 0.0)
for tc in cfg["cuts"]:
    add(whoosh(0.4), tc - 0.22, 0.55, 0.0)
for s in cfg["slams"]:
    add(impact(), s["t"], 0.75 * s["k"])

# Mastering: sanfte Saettigung, Normalisierung, Ein-/Ausblendung
mix = np.tanh(mix * 1.4)
mix /= np.abs(mix).max() / 0.89
fade = int(0.6 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
pcm = (mix * 32767).astype("<i2")
with wave.open(out_path, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("saved", out_path)
