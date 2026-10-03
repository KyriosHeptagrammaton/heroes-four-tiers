"""Builds the button sounds from Kenney's CC0 packs (Impact Sounds, RPG Audio).
Usage: python3 tools/build_kenney_sfx.py <folder with the unzipped packs>
Writes sfx/button_<style>_<n>.ogg. Needs numpy, scipy and ffmpeg."""
import glob, os, subprocess, sys, tempfile
import numpy as np
from scipy.io import wavfile

SR = 44100
SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(os.path.dirname(__file__), "..", "sfx")

def load(name):
    path = glob.glob(os.path.join(SRC, "**", name + ".ogg"), recursive=True)[0]
    with tempfile.NamedTemporaryFile(suffix=".wav") as t:
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR), t.name], check=True)
        sr, x = wavfile.read(t.name)
    x = x.astype(np.float64)
    return x / (np.max(np.abs(x)) + 1e-9)

def pitch(x, factor):
    """resample: factor < 1 lowers pitch (and lengthens)"""
    n = int(len(x) / factor)
    return np.interp(np.arange(n) * factor, np.arange(len(x)), x)

def trim(x, lead=0.15, tail=0.02):
    """cut the silence (and faint pre-noise) before the hit so the button answers at once"""
    a = np.where(np.abs(x) > lead)[0]
    b = np.where(np.abs(x) > tail)[0]
    return x[max(0, a[0] - 40): b[-1] + 1] if len(a) else x

def soften(x, cutoff=1800.0):
    """muffle: a gentle zero-phase low-pass that removes the sharp, high ping"""
    from scipy.signal import butter, sosfiltfilt
    sos = butter(4, cutoff, btype="low", fs=SR, output="sos")
    return sosfiltfilt(sos, x)

def finish(x, peak_db=-7.0, fade_ms=25, attack_ms=4, cutoff=1800.0):
    x = soften(trim(x), cutoff)
    a = int(attack_ms / 1000 * SR)
    x[:a] *= np.linspace(0, 1, a)          # no instant click at the very start
    f = int(fade_ms / 1000 * SR)
    x[-f:] *= np.linspace(1, 0, f)
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)

def mix(*parts):
    """parts: (signal, start seconds, gain)"""
    n = max(int(at * SR) + len(s) for s, at, g in parts)
    out = np.zeros(n)
    for s, at, g in parts:
        i = int(at * SR)
        out[i:i + len(s)] += s * g
    return out

def save(name, x):
    with tempfile.NamedTemporaryFile(suffix=".wav") as t:
        wavfile.write(t.name, SR, (x * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", t.name, "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, name)], check=True)

# "stone": a pick-on-rock knock ("ba") and a deep lowered wooden thud ("DOOM") just after
for i, (m, w) in enumerate([("000", "001"), ("003", "003"), ("004", "004")]):
    ba = load("impactMining_" + m)
    doom = pitch(load("impactWood_heavy_" + w), 0.8)
    save(f"button_stone_{i + 1}.ogg", finish(mix((ba, 0.0, 0.75), (doom, 0.085, 1.0))))
# "pick": the rock knock on its own
for i, m in enumerate(["000", "003", "004"]):
    save(f"button_pick_{i + 1}.ogg", finish(load("impactMining_" + m)))
# "door": a heavy door swung shut
for i, d in enumerate(["4", "2"]):
    save(f"button_door_{i + 1}.ogg", finish(load("doorClose_" + d)))
print("ok")
