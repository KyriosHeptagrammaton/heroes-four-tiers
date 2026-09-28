"""Build the game logo: α β γ δ fused into a 2x2 monogram.
Writes icon.png (512) and icon.ico (16..256) at the project root."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
FONT = "fonts/DejaVuSerif-Bold.ttf"
LETTERS = [("α", "#d0543f"), ("β", "#3f7fd0"), ("γ", "#3fa64f"), ("δ", "#9a52c9")]
PULL = 0.33          # how far letters sit from centre (fraction of S): smaller = more fused

def letter_mask(ch, size):
    f = ImageFont.truetype(FONT, size)
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    l, t, r, b = d.textbbox((0, 0), ch, font=f)
    return im, f, (l, t, r, b)

def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

# ---- letter masks, each pushed into its quadrant, all touching the centre
masks = []
CELL = S * 0.40      # each glyph is fitted into a CELL x CELL box
OVER = S * 0.025     # boxes overlap the centre by this much, so strokes fuse
for i, (ch, col) in enumerate(LETTERS):
    qx, qy = (i % 2) * 2 - 1, (i // 2) * 2 - 1       # -1 / +1
    f = ImageFont.truetype(FONT, 600)
    g = Image.new("L", (1000, 1000), 0)
    d = ImageDraw.Draw(g)
    d.text((200, 100), ch, font=f, fill=255)
    g = g.crop(g.getbbox())
    w, h = g.size
    # fit to the cell; allow a little stretch so thin letters fill their quadrant
    sx, sy = CELL / w, CELL / h
    k = min(sx, sy)
    sx, sy = min(sx, k * 1.3), min(sy, k * 1.3)
    g = g.resize((max(1, int(w * sx)), max(1, int(h * sy))), Image.LANCZOS)
    w, h = g.size
    # anchor the glyph's inner corner at the centre (plus overlap)
    x = S / 2 - w + OVER if qx < 0 else S / 2 - OVER
    y = S / 2 - h + OVER if qy < 0 else S / 2 - OVER
    im = Image.new("L", (S, S), 0)
    im.paste(g, (int(x), int(y)))
    masks.append((np.array(im, np.float32) / 255.0, hexrgb(col)))

union = np.clip(sum(m for m, _ in masks), 0, 1)

def dilate(a, r):
    im = Image.fromarray((a * 255).astype(np.uint8))
    return np.array(im.filter(ImageFilter.MaxFilter(r * 2 + 1)), np.float32) / 255.0

# ---- stone tile background with bevel
rng = np.random.default_rng(7)
bg = np.zeros((S, S, 3), np.float32)
base = np.array([46, 44, 42], np.float32)
noise = np.array(Image.fromarray((rng.random((S // 8, S // 8)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), np.float32) / 255.0
fine = rng.random((S, S)).astype(np.float32)
bg[:] = base
bg += ((noise - 0.5) * 22 + (fine - 0.5) * 10)[..., None]
yy, xx = np.mgrid[0:S, 0:S]
m = 36   # bevel width
edge = np.minimum.reduce([xx, yy, S - 1 - xx, S - 1 - yy])
light = ((xx < m) | (yy < m)) & (edge < m) & ~((S - 1 - xx < m) & (xx > yy)) & ~((S - 1 - yy < m) & (yy > xx))
dark = (edge < m) & ~light
bg[light] += 30
bg[dark] -= 22
# gold trim line inside bevel
trim = (edge >= m) & (edge < m + 10)
bg[trim] = [196, 160, 78]
bg[(edge >= m + 10) & (edge < m + 14)] = [30, 26, 22]
# vignette + central halo
r = np.hypot(xx - S / 2, yy - S / 2) / (S / 2)
bg *= (1.0 - 0.25 * np.clip(r - 0.4, 0, 1))[..., None]
bg += (np.clip(1 - r, 0, 1) ** 2 * 26)[..., None] * np.array([1.0, 0.85, 0.5])

out = bg.copy()

# ---- drop shadow of the fused shape
sh = np.array(Image.fromarray((dilate(union, 10) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255.0
sh = np.roll(np.roll(sh, 14, 0), 14, 1)
out *= (1 - 0.65 * sh)[..., None]

# ---- thick gold outline around the union -> fuses the four letters into one sigil
outer = dilate(union, 26)
inner = dilate(union, 18)
gold_dark = np.array([110, 78, 30], np.float32)
gold = np.array([222, 184, 92], np.float32)
out = out * (1 - outer[..., None]) + gold_dark * outer[..., None]
# gold ring with a vertical sheen
sheen = (1 - yy / S)[..., None] * 0.35 + 0.8
out = out * (1 - inner[..., None]) + np.clip(gold * sheen, 0, 255) * inner[..., None]
dk = dilate(union, 7)
out = out * (1 - dk[..., None]) + np.array([24, 20, 16], np.float32) * dk[..., None]

# ---- letters in faction colours; later letters drawn over earlier where they overlap
for a, col in masks:
    c = np.array(col, np.float32)
    ol = dilate(a, 6)
    out = out * (1 - ol[..., None]) + np.array([24, 20, 16], np.float32) * ol[..., None]
    # simple top-lit gradient on each glyph
    shade = c * (1.15 - 0.35 * yy / S)[..., None]
    out = out * (1 - a[..., None]) + np.clip(shade, 0, 255) * a[..., None]
# thin highlight on letter tops
hl = np.clip(union - np.roll(union, 5, 0), 0, 1)
out += (hl * 60)[..., None]

img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")
img.resize((512, 512), Image.LANCZOS).save("icon.png")
img.save("/tmp/logo_full.png")
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
img.resize((256, 256), Image.LANCZOS).save("icon.ico", sizes=sizes)
print("ok")
