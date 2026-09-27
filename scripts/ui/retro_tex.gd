# ============================================================================
# RetroTex — procedural, tileable textures for the 90s look (no image assets):
#   grain(): speckled stone grain as white/black alpha, laid over any colour
#   wall():  a dark dressed-stone block wall for screen backgrounds
# ============================================================================
class_name RetroTex
extends RefCounted

static var _cache := {}

## periodic value noise, bilinear with smoothstep, period `cells` over size px
static func _vnoise(r: Rng, size: int, cells: int) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for i in cells * cells: g[i] = r.next()
	var out := PackedFloat32Array()
	out.resize(size * size)
	var cs := float(size) / cells
	for y in size:
		var fy := y / cs
		var iy := int(fy)
		var ty := fy - iy
		ty = ty * ty * (3 - 2 * ty)
		var y0 := (iy % cells) * cells
		var y1 := ((iy + 1) % cells) * cells
		for x in size:
			var fx := x / cs
			var ix := int(fx)
			var tx := fx - ix
			tx = tx * tx * (3 - 2 * tx)
			var x0 := ix % cells
			var x1 := (ix + 1) % cells
			var a := lerpf(g[y0 + x0], g[y0 + x1], tx)
			var b := lerpf(g[y1 + x0], g[y1 + x1], tx)
			out[y * size + x] = lerpf(a, b, ty)
	return out

static func _fbm(seed_v: int, size: int, octaves: Array) -> PackedFloat32Array:
	var r := Rng.new(seed_v)
	var acc := PackedFloat32Array()
	acc.resize(size * size)
	var wsum := 0.0
	for o in octaves:
		var n := _vnoise(r, size, o[0])
		for i in size * size: acc[i] += n[i] * o[1]
		wsum += o[1]
	for i in size * size: acc[i] /= wsum
	return acc

static func grain(strength: float = 1.0) -> Texture2D:
	var key := "grain%.2f" % strength
	if _cache.has(key): return _cache[key]
	var S := 128
	var n := _fbm(71, S, [[4, 0.5], [8, 0.3], [32, 0.2]])
	var fine := _fbm(19, S, [[64, 1.0]])
	var r := Rng.new(5)
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var v: float = (n[y * S + x] - 0.5) * 1.6 + (fine[y * S + x] - 0.5) * 0.7
			var a := clampf(absf(v) * 0.4 * strength, 0, 1)
			img.set_pixel(x, y, Color(1, 0.97, 0.9, a * 0.6) if v > 0 else Color(0, 0, 0, a))
	# pits and flecks
	for i in 260:
		var x := r.rint(0, S - 1)
		var y := r.rint(0, S - 1)
		img.set_pixel(x, y, Color(0, 0, 0, 0.35 * strength) if r.next() < 0.6 else Color(1, 1, 0.9, 0.25 * strength))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

## dressed stone blocks with mortar, tileable (256x256)
static func wall(base: Color = Color("#3a342c")) -> Texture2D:
	var key := "wall" + base.to_html()
	if _cache.has(key): return _cache[key]
	var S := 256
	var n := _fbm(33, S, [[8, 0.45], [16, 0.3], [64, 0.25]])
	var r := Rng.new(1234)
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var rows := 8
	var rh := S / rows
	var mortar := base.darkened(0.6)
	for row in rows:
		# random block widths summing to S, offset per row so seams stagger
		var widths := []
		var left := S
		while left > 0:
			var w: int = r.rint(44, 84)
			if left - w < 40: w = left
			widths.append(w)
			left -= w
		var off := r.rint(0, S - 1)
		var x0 := 0
		for w in widths:
			var tint: float = 1.0 + (r.next() - 0.5) * 0.22
			var hue: float = (r.next() - 0.5) * 0.04
			for yy in rh:
				var y := row * rh + yy
				for xx in w:
					var x: int = (x0 + xx + off) % S
					var c: Color
					if yy < 2 or xx < 2:
						c = mortar
					else:
						var v: float = n[y * S + x]
						c = Color(base.r * tint + hue, base.g * tint, base.b * tint - hue) * (0.72 + v * 0.56)
						if yy == 2 or xx == 2: c = c.lightened(0.18)
						elif yy == rh - 1 or xx == w - 1: c = c.darkened(0.3)
					img.set_pixel(x, y, Color(c.r, c.g, c.b))
			x0 += w
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
