"""Writes the game's sounds into data/audio/ (16-bit mono WAV, 22050 Hz), made from sine tones and
noise so that the repo carries no third-party audio and no licence to credit.
Run: python tools/make_audio.py
Replace any file with your own recording of the same name, or point data/audio.json elsewhere."""
import math, os, random, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "data", "audio")


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak) * 32767
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale)) for s in samples))


def n(sec):
    return int(sec * RATE)


def tone(freq, sec, vol=1.0, attack=0.01, decay=None, harm=(1.0,)):
    decay = decay if decay is not None else sec
    out = []
    for i in range(n(sec)):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-3.0 * t / decay)
        v = sum(h * math.sin(2 * math.pi * freq * (k + 1) * t) for k, h in enumerate(harm))
        out.append(v * env * vol)
    return out


def noise(sec, vol=1.0, decay=None, low=0.0, seed=1):
    rng = random.Random(seed)
    decay = decay if decay is not None else sec
    out, prev = [], 0.0
    for i in range(n(sec)):
        t = i / RATE
        x = rng.uniform(-1, 1)
        prev = low * prev + (1 - low) * x  # low pass: higher `low` is duller
        out.append(prev * math.exp(-3.0 * t / decay) * vol * min(1.0, t / 0.005))
    return out


def mix(*parts, at=None):
    at = at or [0.0] * len(parts)
    length = max(n(a) + len(p) for p, a in zip(parts, at))
    out = [0.0] * length
    for p, a in zip(parts, at):
        o = n(a)
        for i, s in enumerate(p):
            out[o + i] += s
    return out


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


os.makedirs(OUT, exist_ok=True)
write("click", tone(1400, 0.05, 1.0, 0.002, 0.03))
write("building", seq(tone(660, 0.12, 1.0, 0.005, 0.1), tone(880, 0.3, 1.0, 0.005, 0.25, (1.0, 0.3))))
write("unit", mix(tone(70, 0.3, 1.0, 0.003, 0.15, (1.0, 0.5)), noise(0.12, 0.35, 0.05, 0.7, 4)))
write("battle", mix(noise(0.9, 0.9, 0.5, 0.85, 7), tone(48, 0.7, 0.8, 0.003, 0.4, (1.0, 0.5))))
write("war", mix(tone(116, 1.2, 0.8, 0.1, 1.0, (1.0, 0.5, 0.3)), tone(87, 1.2, 0.8, 0.1, 1.0, (1.0, 0.5, 0.3))))
write("peace", mix(tone(523, 1.1, 0.6, 0.02, 0.9), tone(659, 1.1, 0.6, 0.02, 0.9), tone(784, 1.1, 0.6, 0.02, 0.9), at=[0.0, 0.12, 0.24]))
write("treaty", seq(tone(587, 0.15, 1.0, 0.005, 0.12), tone(740, 0.35, 1.0, 0.005, 0.3)))
write("join", seq(tone(988, 0.12, 1.0, 0.004, 0.08), tone(988, 0.12, 0.0), tone(988, 0.18, 1.0, 0.004, 0.12)))
write("collapse", mix(tone(220, 1.6, 0.8, 0.02, 1.4, (1.0, 0.4)), tone(110, 1.6, 0.8, 0.02, 1.4, (1.0, 0.4)), noise(1.4, 0.3, 1.0, 0.9, 9)))
write("ship_sunk", mix(tone(60, 1.0, 1.0, 0.003, 0.6, (1.0, 0.5)), noise(1.0, 0.5, 0.7, 0.92, 11)))
write("blockade", mix(tone(98, 1.4, 0.8, 0.3, 1.2, (1.0, 0.4)), tone(104, 1.4, 0.8, 0.3, 1.2, (1.0, 0.4))))
print("wrote", len(os.listdir(OUT)), "files")
