"""Run with: python3 tools/make_caustics.py
Builds world/ocean/caustics.png: a looping animation of underwater caustics (the bright, moving
net of light that sunlight makes on the seabed after passing through waves), packed as a grid of
frames that Godot imports as one texture array.

Each frame is made the physical way: light falls straight down through a wavy surface, bends at
every point by Snell's law and lands on a floor below; counting where it lands gives the bright
lines. The surface is a sum of waves that repeat across the tile and complete whole cycles over
the loop, so the result tiles seamlessly in space and loops seamlessly in time."""
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / 'world' / 'ocean' / 'caustics.png'
SIZE = 512            # pixels per frame side
FRAMES = 32           # frames in one loop
COLUMNS = 4           # frames per row in the packed image (rows = FRAMES / COLUMNS)
RAYS = 1536           # light rays per frame side (RAYS^2 rays per frame)
FOCUS = 6.0             # floor distance relative to where the strongest waves would focus light to a point
RANGE = 6.0             # stored value = brightness / RANGE (mean brightness is 1)
rng = np.random.default_rng(73129)

# Waves: integer wave vectors (cycles per tile) so the surface repeats exactly across the tile, and
# an integer number of cycles per loop so the animation repeats exactly. Speed rises with the root
# of the wave number, like real water waves.
waves = []
while len(waves) < 22:
    k = rng.integers(-9, 10, 2)
    length = float(np.hypot(*k))
    if length < 2.0 or length > 9.5 or any(np.array_equal(k, w[0]) or np.array_equal(k, -w[0]) for w in waves):
        continue
    amplitude = length ** -1.7 * rng.uniform(0.6, 1.0)
    cycles = max(1, int(round(0.75 * np.sqrt(length))))
    waves.append((k.astype(float), amplitude, cycles * (1 if rng.random() < 0.5 else -1), rng.uniform(0, 2 * np.pi)))


def surface_slope(x, y, t):
    gx = np.zeros_like(x); gy = np.zeros_like(x); curvature = 0.0
    for k, a, cycles, phase in waves:
        arg = 2 * np.pi * (k[0] * x + k[1] * y) - 2 * np.pi * cycles * t + phase
        c = np.cos(arg) * a * 2 * np.pi
        gx += c * k[0]; gy += c * k[1]
        curvature += a * (2 * np.pi * np.hypot(*k)) ** 2
    return gx, gy, curvature


def frame(t):
    s = (np.arange(RAYS) + 0.5) / RAYS
    x, y = np.meshgrid(s, s, indexing='xy')
    gx, gy, curvature = surface_slope(x, y, t)
    # Refract a vertical ray (0, 0, -1) at the surface normal (-gx, -gy, 1) from air (1.0) into water (1.333).
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    eta = 1.0 / 1.333
    cos_i = n[..., 2]
    k = 1.0 - eta * eta * (1.0 - cos_i * cos_i)
    d = eta * np.array([0.0, 0.0, -1.0]) + (eta * cos_i - np.sqrt(k))[..., None] * n
    # Floor depth set relative to the focal distance of the strongest curvature.
    depth = FOCUS / ((1.0 - eta) * curvature)
    lx = (x + d[..., 0] / -d[..., 2] * depth) % 1.0
    ly = (y + d[..., 1] / -d[..., 2] * depth) % 1.0
    # Bilinear splat of every ray into the frame (wrapping at the edges).
    fx = lx * SIZE - 0.5; fy = ly * SIZE - 0.5
    x0 = np.floor(fx).astype(np.int64); y0 = np.floor(fy).astype(np.int64)
    wx = fx - x0; wy = fy - y0
    image = np.zeros(SIZE * SIZE)
    for ox, oy, w in ((0, 0, (1 - wx) * (1 - wy)), (1, 0, wx * (1 - wy)), (0, 1, (1 - wx) * wy), (1, 1, wx * wy)):
        index = ((y0 + oy) % SIZE) * SIZE + (x0 + ox) % SIZE
        image += np.bincount(index.ravel(), weights=w.ravel(), minlength=SIZE * SIZE)
    image = image.reshape(SIZE, SIZE)
    # Gentle blur (wrapping) removes the grain of counting individual rays.
    spectrum = np.fft.fft2(image)
    f = np.fft.fftfreq(SIZE)
    blur = np.exp(-2 * (np.pi * 0.8) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    image = np.real(np.fft.ifft2(spectrum * blur))
    return image / image.mean()


frames = [frame(i / FRAMES) for i in range(FRAMES)]
rows = FRAMES // COLUMNS
packed = np.zeros((rows * SIZE, COLUMNS * SIZE), np.uint8)
for i, f in enumerate(frames):
    r, c = divmod(i, COLUMNS)
    packed[r * SIZE:(r + 1) * SIZE, c * SIZE:(c + 1) * SIZE] = np.clip(f / RANGE * 255.0 + 0.5, 0, 255).astype(np.uint8)
OUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(packed, 'L').save(OUT, optimize=True)
stack = np.stack(frames)
print(OUT.name, packed.shape, round(OUT.stat().st_size / 1e6, 2), 'MB; brightness mean', round(float(stack.mean()), 2),
      'p99', round(float(np.percentile(stack, 99)), 2), 'max', round(float(stack.max()), 2),
      'clipped', round(float((stack > RANGE).mean()) * 100, 2), '%')
