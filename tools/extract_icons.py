"""Cuts the hand-drawn unit portraits and weapon marks out of the icon sheets
(cyan background) and records where each unit holds its weapon (the black
stars on the second sheet).
Usage: python3 tools/extract_icons.py icons.png stars.png
Note: on the sheets the row labels say "Tier" and the column labels say the
faction, but it is the other way round: rows are factions, columns tiers."""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

ICONS, STARS = sys.argv[1], sys.argv[2]
ROOT = os.path.join(os.path.dirname(__file__), "..", "art")
FACTIONS = ["alpha", "beta", "gamma", "delta"]           # sheet rows
ROW_Y = [85, 145, 230, 305]
COL_X = [140, 240, 355, 472]                               # tiers 1-4
BG = np.array([0, 255, 255], float)

a = np.array(Image.open(ICONS).convert("RGB")).astype(float)
b = np.array(Image.open(STARS).convert("RGB")).astype(float)

def unmix_interior(rgb, band_px=7):
    """Keys out the cyan background. Pixels well inside a shape keep their colour.
    Edge pixels (within band_px of the background) are treated as a mix of cyan and
    the colour of the nearest solid interior pixel: alpha is how far along that line
    they sit, and they take the interior colour (so glows and anti-aliased rims fade
    out cleanly instead of turning green or purple). Thin parts with no interior
    nearby fall back to colour-difference keying (key = min(G,B) - R)."""
    bg = np.linalg.norm(rgb - BG, axis=-1) < 12
    d_bg = ndimage.distance_transform_edt(~bg)
    near = (d_bg <= band_px) & ~bg
    deep = d_bg > band_px
    d_deep, (iy, ix) = ndimage.distance_transform_edt(~deep, return_indices=True)
    f = rgb[iy, ix]
    fb = f - BG
    cb = rgb - BG
    proj = np.clip((cb * fb).sum(-1) / np.maximum((fb * fb).sum(-1), 1.0), 0, 1)
    key = np.clip((np.minimum(rgb[..., 1], rgb[..., 2]) - rgb[..., 0]) / 255.0, 0, 1)
    a_key = 1.0 - key
    a3 = np.maximum(a_key[..., None], 1e-3)
    unmixed = np.clip((rgb - (1 - a3) * BG) / a3, 0, 255)
    use_interior = d_deep <= band_px * 1.6
    alpha = np.ones(rgb.shape[:2])
    fg = rgb.copy()
    m1 = near & use_interior
    alpha[m1] = proj[m1]
    fg[m1] = f[m1]
    m2 = near & ~use_interior
    alpha[m2] = a_key[m2]
    fg[m2] = unmixed[m2]
    alpha[bg] = 0.0
    return alpha, fg

def unmix_key(rgb, band_px=10):
    """Colour-difference keying for a cyan screen: key = min(G,B) - R (255 on pure
    cyan). Only pixels within band_px of the background are keyed and un-mixed."""
    bg = np.linalg.norm(rgb - BG, axis=-1) < 12
    near = ndimage.distance_transform_edt(~bg) <= band_px
    key = np.clip((np.minimum(rgb[..., 1], rgb[..., 2]) - rgb[..., 0]) / 255.0, 0, 1)
    alpha = np.where(near, 1.0 - key, 1.0)
    alpha[bg] = 0.0
    a3 = np.maximum(alpha[..., None], 1e-3)
    unmixed = np.clip((rgb - (1 - a3) * BG) / a3, 0, 255)
    return alpha, np.where(near[..., None], unmixed, rgb)

# Most portraits key best by colour difference; the big soft yellow/white glows
# key better against their own interior colour (no green/purple fringe).
alpha_k, fg_k = unmix_key(a)
alpha_i, fg_i = unmix_interior(a)
alpha_w, fg_w = unmix_key(a, band_px=2)       # weapons: thin, keep their colours
INTERIOR = {"beta_2", "beta_3", "beta_4"}
alpha, fg = alpha_k, fg_k
solid = alpha > 0.06

def crop(mask, x0, y0, x1, y1, pad=2):
    ys, xs = np.where(mask[y0:y1, x0:x1])
    if len(xs) == 0:
        return None
    bx0, by0 = max(0, x0 + xs.min() - pad), max(0, y0 + ys.min() - pad)
    bx1, by1 = x0 + xs.max() + 1 + pad, y0 + ys.max() + 1 + pad
    return bx0, by0, bx1, by1

def save_rgba(box, path, keep=None, src=None):
    al_src, fg_src = src if src else (alpha, fg)
    x0, y0, x1, y1 = box
    al = al_src[y0:y1, x0:x1].copy()
    if keep is not None:
        al *= keep[y0:y1, x0:x1]
    img = np.dstack([fg_src[y0:y1, x0:x1], al * 255]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path)

# ---- portraits: components in the portrait area, grouped by nearest grid cell
area = np.zeros_like(solid)
area[55:352, 100:545] = True
lab, n = ndimage.label(ndimage.binary_dilation(solid & area, iterations=2))
cells = {}
for i in range(1, n + 1):
    ys, xs = np.where(lab == i)
    if len(xs) < 6:
        continue
    cy, cx = ys.mean(), xs.mean()
    r = int(np.argmin([abs(cy - y) for y in ROW_Y]))
    c = int(np.argmin([abs(cx - x) for x in COL_X]))
    cells.setdefault((r, c), np.zeros_like(solid))
    cells[(r, c)] |= (lab == i)

# ---- stars: black on the second sheet but not on the first
star = (b.sum(-1) < 60) & (a.sum(-1) > 120)
slab, sn = ndimage.label(ndimage.binary_closing(star, iterations=1))
stars = []
for i in range(1, sn + 1):
    ys, xs = np.where(slab == i)
    if len(xs) < 12:
        continue
    fill = len(xs) / ((np.ptp(xs) + 1) * (np.ptp(ys) + 1))
    if a[int(ys.mean()), int(xs.mean())].sum() < 100:   # dark eyes whose soft edges differ
        continue
    stars.append({"x": float(xs.mean()), "y": float(ys.mean()), "d": float(max(14, np.ptp(xs) + 1, np.ptp(ys) + 1))})

meta = {"units": {}, "weapons": {}}
boxes = {}
for (r, c), m in cells.items():
    box = crop(m & solid, 0, 0, m.shape[1], m.shape[0])
    boxes[(r, c)] = box
for s in stars:
    # nearest portrait box
    best, bd = None, 1e9
    for k, (x0, y0, x1, y1) in boxes.items():
        dx = max(x0 - s["x"], 0, s["x"] - x1)
        dy = max(y0 - s["y"], 0, s["y"] - y1)
        d = (dx * dx + dy * dy) ** 0.5
        if d < bd:
            best, bd = k, d
    s["cell"] = best
for (r, c), box in sorted(boxes.items()):
    f, t = FACTIONS[r], c + 1
    x0, y0, x1, y1 = box
    name = f"{f}_{t}"
    src = (alpha_i, fg_i) if name in INTERIOR else (alpha_k, fg_k)
    save_rgba(box, os.path.join(ROOT, "units", name + ".png"), keep=cells[(r, c)].astype(float), src=src)
    # dominant colour: the most common solid colour that isn't near-black outline/eyes
    region = fg[y0:y1, x0:x1][(alpha[y0:y1, x0:x1] > 0.8) & (cells[(r, c)][y0:y1, x0:x1])]
    region = region[region.max(axis=1) > 60]
    q = (region // 24).astype(int)
    keys, counts = np.unique(q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2], return_counts=True)
    k = keys[np.argmax(counts)]
    dom = np.array([k // 10000, k // 100 % 100, k % 100]) * 24 + 12
    meta["units"][name] = {
        "w": x1 - x0, "h": y1 - y0,
        "hands": [{"x": round(s["x"] - x0, 1), "y": round(s["y"] - y0, 1), "d": round(s["d"], 1)} for s in stars if s["cell"] == (r, c)],
        "color": "#%02x%02x%02x" % tuple(int(v) for v in np.clip(dom, 0, 255)),
    }

# ---- weapons: melee / ranged / magi for infantry (upper row) and cavalry (lower row)
green = (a[..., 1] > a[..., 0] + 30) & (a[..., 1] > a[..., 2] + 30) & solid
# columns and the row split between infantry and cavalry (gaps found on the sheet)
slots = {}
for ci, (x0, x1, split) in enumerate([(115, 205, 455), (205, 320, 474), (320, 430, 460)]):
    for ri, (y0, y1) in enumerate([(386, split), (split, 548)]):
        m = np.zeros_like(solid)
        m[y0:y1, x0:x1] = solid[y0:y1, x0:x1]
        slots[(ci, ri)] = m
for (ci, ri), m in slots.items():
    path, kind = ["melee", "ranged", "magi"][ci], ["inf", "cav"][ri]
    m = m & solid
    box = crop(m, 0, 0, m.shape[1], m.shape[0])
    bx0, by0, bx1, by1 = box
    save_rgba(box, os.path.join(ROOT, "weapons", f"{path}_{kind}.png"), keep=(m & ~green).astype(float), src=(alpha_w, fg_w))
    g = (green & m)[by0:by1, bx0:bx1]
    if g.any():
        tint = np.dstack([np.full(g.shape + (3,), 255), alpha_w[by0:by1, bx0:bx1] * g * 255]).astype(np.uint8)
        Image.fromarray(tint, "RGBA").save(os.path.join(ROOT, "weapons", f"{path}_{kind}_tint.png"))
    meta["weapons"][f"{path}_{kind}"] = {"w": bx1 - bx0, "h": by1 - by0, "tint": bool(g.any())}

json.dump(meta, open(os.path.join(ROOT, "units.json"), "w"), indent=1, default=lambda o: o.item() if hasattr(o, "item") else str(o))
print(len(meta["units"]), "portraits,", len(stars), "stars,", len(meta["weapons"]), "weapons")
for k, v in sorted(meta["units"].items()):
    print(k, v["w"], "x", v["h"], "hands", [(h["x"], h["y"], h["d"]) for h in v["hands"]], v["color"])
