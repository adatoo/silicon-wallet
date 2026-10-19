"""Draws the lock screen's backdrop: a blurred close-up of a circuit board in the icon's colours.

Original artwork, made only from shapes here, then blurred like a shallow-focus photograph. Run
through `task backdrop`; it rewrites App/Resources/Assets.xcassets/LockBackdrop.imageset.
Needs Pillow and NumPy.

    python3 scripts/make-backdrop.py <imageset directory>
"""

import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 2000
OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "."


def rgb(hex_value):
    return np.array([(hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255], float) / 255


# Colours from the app icon (scripts/make-icon.swift).
NAVY, BLUE, TEAL, GLOW = rgb(0x15213F), rgb(0x1C3F6E), rgb(0x2A8FA8), rgb(0x7FE3F0)

ys, xs = np.mgrid[0:SIZE, 0:SIZE] / SIZE
rows, columns = np.mgrid[0:SIZE, 0:SIZE]


def to_image(pixels):
    return Image.fromarray((np.clip(pixels, 0, 1) * 255).astype(np.uint8))


def to_pixels(image):
    return np.asarray(image, float) / 255


def blurred(pixels, radius):
    return to_pixels(to_image(pixels).filter(ImageFilter.GaussianBlur(radius)))


def depth_of_field(pixels, depth, radii):
    """Blends more and more blurred copies by a 0...1 depth map, like a shallow-focus lens."""
    layers = np.stack([blurred(pixels, radius) for radius in radii])
    index = np.clip(depth, 0, 1) * (len(radii) - 1)
    low = np.floor(index).astype(int)
    high = np.minimum(low + 1, len(radii) - 1)
    weight = (index - low)[..., None]
    return layers[low, rows, columns] * (1 - weight) + layers[high, rows, columns] * weight


def bokeh(pixels, spots):
    """Adds soft out-of-focus discs of light, each with a slightly brighter rim."""
    light = np.zeros_like(pixels)
    for x, y, radius, strength in spots:
        mask = Image.new("L", (SIZE, SIZE))
        draw = ImageDraw.Draw(mask)
        box = [x - radius, y - radius, x + radius, y + radius]
        draw.ellipse(box, fill=int(150 * strength))
        draw.ellipse(box, outline=int(220 * strength), width=max(2, int(radius * 0.06)))
        mask = to_pixels(mask.filter(ImageFilter.GaussianBlur(max(1.5, radius * 0.04))))
        light += mask[..., None] * (GLOW * 0.7 + 0.3)
    return pixels + light * 0.55


def focus_distance(x, y):
    """How far a point (0...1) lies from the tilted plane of focus through the large chip."""
    return abs((y - 0.58) * 0.9 + (x - 0.6) * 0.35) * 2.6


def main():
    random.seed(7)
    noise = np.random.default_rng(7)

    board = NAVY * (1 - xs[..., None]) + BLUE * xs[..., None]
    board = board * 0.8 + TEAL * 0.18 * (1 - ys[..., None])
    image = to_image(board)
    draw = ImageDraw.Draw(image)

    trace = tuple(int(c * 255) for c in TEAL * 0.35 + GLOW * 0.65)
    pads = []
    step = 50
    for _ in range(260):
        x, y = random.randrange(0, SIZE, step), random.randrange(0, SIZE, step)
        width = random.choice([6, 8, 8, 12, 16])
        points = [(x, y)]
        for _ in range(random.randint(2, 6)):
            dx, dy = random.choice([(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (1, -1)])
            length = step * random.randint(1, 6)
            x, y = x + dx * length, y + dy * length
            points.append((x, y))
        draw.line(points, fill=trace, width=width, joint="curve")
        for px, py in (points[0], points[-1]):
            radius = width * 1.4
            draw.ellipse([px - radius, py - radius, px + radius, py + radius], fill=(200, 215, 220))
            pads.append((px, py))

    # Chips: dark packages with silver pins on every side.
    for cx, cy, side in [(1250, 1150, 520), (420, 520, 240), (1650, 380, 200), (520, 1600, 300)]:
        for index in range(12):
            offset = -side / 2 + side * (index + 0.5) / 12
            for px, py, w, h in [
                (cx + offset, cy - side / 2 - 18, 8, 36), (cx + offset, cy + side / 2 + 18, 8, 36),
                (cx - side / 2 - 18, cy + offset, 36, 8), (cx + side / 2 + 18, cy + offset, 36, 8),
            ]:
                draw.rectangle([px - w / 2, py - h / 2, px + w / 2, py + h / 2], fill=(185, 195, 200))
        half = side / 2
        draw.rounded_rectangle([cx - half, cy - half, cx + half, cy + half], radius=side * 0.04, fill=(14, 20, 32))
        inner = side * 0.42
        draw.rounded_rectangle(
            [cx - inner, cy - inner, cx + inner, cy + inner], radius=side * 0.03, outline=(34, 48, 70), width=3)

    # Small surface-mount parts.
    for _ in range(120):
        x, y = random.randrange(SIZE), random.randrange(SIZE)
        colour = random.choice([(170, 150, 110), (60, 64, 70), (190, 196, 200)])
        draw.rectangle([x, y, x + 34, y + 16], fill=colour)

    pixels = to_pixels(image)
    key_light = np.exp(-((xs - 0.25) ** 2 + (ys - 0.2) ** 2) / 0.08)[..., None]
    pixels = pixels * (0.75 + 0.5 * key_light)
    pixels = depth_of_field(pixels, focus_distance(xs, ys), [5, 12, 26, 46])

    spots = []
    for px, py in random.sample(pads, 30):
        distance = focus_distance(px / SIZE, py / SIZE)
        if distance > 0.35:
            spots.append((px, py, 14 + distance * 60, 0.25 + 0.3 * noise.random()))
    pixels = bokeh(pixels, spots)

    vignette = 1 - 0.7 * ((xs - 0.5) ** 2 + (ys - 0.5) ** 2)
    pixels = pixels * vignette[..., None] + noise.normal(0, 0.012, pixels.shape)
    to_image(pixels).save(f"{OUTPUT}/lock-backdrop.jpg", quality=86, optimize=True, progressive=True)


if __name__ == "__main__":
    main()
