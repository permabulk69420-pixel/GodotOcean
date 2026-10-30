"""Run with: python3 tools/make_sounds.py
Synthesises the two ambient loops that have no free source (underwater rumble and the thruster
motor) into world/audio/. Both are built from periodic components so they loop with no seam."""
import wave
from pathlib import Path
import numpy as np

OUT = Path(__file__).resolve().parents[1] / 'world' / 'audio'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(20261030)

def write(name, signal, rate):
    signal = signal / max(np.max(np.abs(signal)), 1e-9)
    data = (signal * 32000).astype('<i2')
    with wave.open(str(OUT / name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(data.tobytes())
    print(name, round(len(data) / rate, 2), 's', round(len(data) * 2 / 1e6, 2), 'MB')

def shaped_noise(n, rate, low, high, slope):
    """Periodic noise: random phases on a band-limited, power-law spectrum."""
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    amp = np.zeros_like(freqs)
    band = (freqs >= low) & (freqs <= high)
    amp[band] = (freqs[band] / low) ** (-slope)
    phase = rng.uniform(0, 2 * np.pi, len(freqs))
    return np.fft.irfft(amp * np.exp(1j * phase), n)

# Underwater: a deep, slowly breathing rumble with a faint watery hiss. 30 s at 22.05 kHz.
rate = 22050
n = rate * 30
t = np.arange(n) / rate
rumble = shaped_noise(n, rate, 25, 700, 1.4)
hiss = shaped_noise(n, rate, 900, 3500, 0.8) * 0.06
swell = 1.0 + 0.25 * np.sin(2 * np.pi * t / 7.5) + 0.15 * np.sin(2 * np.pi * t / 30.0 * 3 + 1.1)
write('underwater_loop.wav', (rumble / np.std(rumble) + hiss / np.std(hiss) * 0.12) * swell, rate)

# Thruster: a motor hum with blade-pass flutter and a soft whoosh. 2 s at 44.1 kHz.
rate = 44100
n = rate * 2
t = np.arange(n) / rate
hum = sum(a * np.sin(2 * np.pi * f * t + p) for f, a, p in [(110, 1.0, 0.0), (220, 0.55, 0.7), (330, 0.32, 1.9), (550, 0.16, 0.3), (880, 0.07, 2.4)])
flutter = 1.0 + 0.18 * np.sin(2 * np.pi * 16 * t) + 0.06 * np.sin(2 * np.pi * 7 * t + 0.5)
whoosh = shaped_noise(n, rate, 300, 2600, 0.6)
whoosh = whoosh / np.std(whoosh) * 0.35
write('thruster_loop.wav', (hum / np.std(hum) * flutter + whoosh) * 0.8, rate)
