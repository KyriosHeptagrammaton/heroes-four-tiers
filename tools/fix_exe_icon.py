"""Post-export fix for the Windows exe's icon resources.

Godot 4.3 + rcedit add the new icon as a second RT_GROUP_ICON but leave the
template's named "GODOT_ICON" group in place with the old robot's size table.
Explorer reads the named group first, so we rewrite every icon group in place
to describe the icon images actually stored in the exe (same length, so no
offsets move and the embedded pck is untouched).

usage: python3 tools/fix_exe_icon.py HeroesOfFourSeasons.exe
"""
import struct, sys

path = sys.argv[1]
d = bytearray(open(path, "rb").read())
pe = struct.unpack_from("<I", d, 0x3C)[0]
nsec, = struct.unpack_from("<H", d, pe + 6)
optsz, = struct.unpack_from("<H", d, pe + 20)
oh = pe + 24
magic, = struct.unpack_from("<H", d, oh)
rsrc_rva, _ = struct.unpack_from("<II", d, oh + (112 if magic == 0x20B else 96) + 16)
secs = [struct.unpack_from("<IIII", d, oh + optsz + 40 * i + 8) for i in range(nsec)]

def off(rva):
    for vs, va, rs, ro in secs:
        if va <= rva < va + vs:
            return rva - va + ro
    raise ValueError(hex(rva))

base = off(rsrc_rva)

def leaves(o, path, out):
    nn, ni = struct.unpack_from("<HH", d, o + 12)
    for i in range(nn + ni):
        e, t = struct.unpack_from("<II", d, o + 16 + 8 * i)
        p = path + [("n", e & 0x7FFFFFFF) if e & 0x80000000 else e]
        if t & 0x80000000:
            leaves(base + (t & 0x7FFFFFFF), p, out)
        else:
            rva, sz = struct.unpack_from("<II", d, base + t)
            out.append((p, off(rva), sz))

res = []
leaves(base, [], res)
icons = {p[1]: (o, sz) for p, o, sz in res if p[0] == 3}
groups = [(p, o, sz) for p, o, sz in res if p[0] == 14]

def dims(o, sz):
    b = d[o:o + 24]
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", b[16:24])
    else:                                   # BITMAPINFOHEADER: height is doubled
        w, h = struct.unpack_from("<ii", d, o + 4)
        h //= 2
    return w, h

fixed = 0
for p, o, sz in groups:
    n, = struct.unpack_from("<H", d, o + 4)
    for i in range(n):
        e = o + 6 + 14 * i
        iid, = struct.unpack_from("<H", d, e + 12)
        if iid not in icons:
            continue
        io, isz = icons[iid]
        w, h = dims(io, isz)
        struct.pack_into("<BBBBHHI", d, e, w % 256, h % 256, 0, 0, 1, 32, isz)
        fixed += 1
    print("group", p[1], "entries", n)
open(path, "wb").write(d)
print("fixed", fixed, "entries")
