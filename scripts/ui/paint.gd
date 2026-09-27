# ============================================================================
# Procedural terrain painter. Draws a terrain type into a rectangle of any
# CanvasItem (the baked overworld texture and the battle backdrop).
# base() fills the ground; motifs() adds trees, peaks, grass...
# ============================================================================
class_name Paint
extends RefCounted

static func shade(hex: String, f: float) -> Color:
	var c := Color(hex)
	if f < 0:
		return Color(c.r * (1 + f), c.g * (1 + f), c.b * (1 + f))
	return Color(c.r + (1 - c.r) * f, c.g + (1 - c.g) * f, c.b + (1 - c.b) * f)

static func base(ci: CanvasItem, id: String, r: Rect2) -> void:
	var T: Dictionary = D.TERRAIN.get(id, D.TERRAIN.field)
	var c0 := shade(T.color, 0.06)
	var c1 := shade(T.color, -0.12)
	var w := r.size.x
	var h := r.size.y
	var pts := PackedVector2Array([r.position, r.position + Vector2(w, 0), r.end, r.position + Vector2(0, h)])
	var cols := PackedColorArray([c0, c0.lerp(c1, w / (w + h)), c1, c0.lerp(c1, h / (w + h))])
	ci.draw_polygon(pts, cols)

static func _ellipse(c: Vector2, rx: float, ry: float, a0: float = 0.0, a1: float = TAU, n: int = 18) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n + 1:
		var a := a0 + (a1 - a0) * i / n
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return p

static func motifs(ci: CanvasItem, id: String, rect: Rect2, seed_v: int, unit: float = 0.0, density: float = 1.0) -> void:
	var T: Dictionary = D.TERRAIN.get(id, D.TERRAIN.field)
	var base_hex: String = T.color
	var r := Rng.new(seed_v if seed_v else 1)
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var u: float = unit if unit > 0 else maxf(4, minf(w, h) / 10)
	var area := w * h
	var N := func(k: float) -> int: return maxi(1, U.jr(area / (u * u) * k * density))
	var rx := func() -> float: return x + r.next() * w
	var ry := func() -> float: return y + r.next() * h
	var grass := func(k: float, col: Color):
		var pts := PackedVector2Array()
		for i in N.call(k):
			var a: float = rx.call()
			var b: float = ry.call()
			pts.append(Vector2(a, b)); pts.append(Vector2(a + u * 0.15, b - u * 0.35))
			pts.append(Vector2(a + u * 0.2, b)); pts.append(Vector2(a + u * 0.28, b - u * 0.3))
		ci.draw_multiline(pts, col, maxf(0.6, u * 0.08), true)
	var tree := func(a: float, b: float, s: float, col: Color, trunk: Color = Color("#3b2a1a")):
		ci.draw_rect(Rect2(a - s * 0.07, b, s * 0.14, s * 0.25), trunk)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(a, b - s * 0.75), Vector2(a + s * 0.38, b + s * 0.05), Vector2(a - s * 0.38, b + s * 0.05)]), col)
	var blob := func(a: float, b: float, s: float, col: Color):
		ci.draw_circle(Vector2(a, b), s, col)
	var peak := func(a: float, b: float, s: float, snow: bool):
		ci.draw_colored_polygon(PackedVector2Array([Vector2(a - s, b), Vector2(a, b - s * 1.2), Vector2(a + s, b)]), shade(base_hex, -0.25))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(a, b - s * 1.2), Vector2(a + s, b), Vector2(a + s * 0.2, b)]), shade(base_hex, 0.05))
		if snow:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(a, b - s * 1.2), Vector2(a + s * 0.32, b - s * 0.8), Vector2(a - s * 0.32, b - s * 0.8)]), Color("#f2f4f5"))
	var S := func(f: float) -> Color: return shade(base_hex, f)
	match id:
		"plains": grass.call(0.5, S.call(-0.25))
		"field":
			grass.call(0.35, S.call(-0.25))
			for i in N.call(0.08): blob.call(rx.call(), ry.call(), u * 0.08, Color("#f3e28a") if r.next() < 0.5 else Color("#f0f0f0"))
		"forest":
			for i in N.call(0.55):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * (0.9 + r.next() * 0.5)
				tree.call(a, b, s, Color("#2f6a33") if r.next() < 0.5 else Color("#3b7a3a"))
		"hill":
			for i in N.call(0.12):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * (0.9 + r.next() * 0.8)
				ci.draw_colored_polygon(_ellipse(Vector2(a, b), s, s * 0.55, PI, TAU), S.call(-0.15))
				ci.draw_colored_polygon(_ellipse(Vector2(a - s * 0.2, b), s * 0.55, s * 0.35, PI, TAU), S.call(0.1))
			grass.call(0.15, S.call(-0.3))
		"canyon":
			for i in N.call(0.1):
				var a: float = rx.call()
				var p := PackedVector2Array([Vector2(a, y)])
				for k in range(1, 7): p.append(Vector2(a + (r.next() - 0.5) * u, y + h * k / 6.0))
				ci.draw_polyline(p, S.call(-0.35), u * 0.12, true)
		"ashlands":
			for i in N.call(0.6): blob.call(rx.call(), ry.call(), u * 0.06, Color("#2a2422"))
			for i in N.call(0.06): blob.call(rx.call(), ry.call(), u * 0.07, Color("#e0522e"))
		"moor":
			for i in N.call(0.08): ci.draw_colored_polygon(_ellipse(Vector2(rx.call(), ry.call()), u * 1.2, u * 0.3), Color("#dfe7e855"))
			for i in N.call(0.05):
				var a: float = rx.call(); var b: float = ry.call()
				ci.draw_multiline(PackedVector2Array([Vector2(a, b), Vector2(a, b - u * 0.7), Vector2(a, b - u * 0.7), Vector2(a + u * 0.25, b - u * 0.95), Vector2(a, b - u * 0.5), Vector2(a - u * 0.25, b - u * 0.7)]), Color("#3a3a36"), u * 0.08, true)
		"steppe":
			var pts := PackedVector2Array()
			for i in N.call(0.35):
				var a: float = rx.call(); var b: float = ry.call()
				pts.append(Vector2(a, b)); pts.append(Vector2(a + u * 0.8, b - u * 0.05))
			ci.draw_multiline(pts, S.call(-0.2), u * 0.06, true)
		"badlands":
			for i in N.call(0.07):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * (0.8 + r.next())
				ci.draw_colored_polygon(PackedVector2Array([Vector2(a - s, b), Vector2(a - s * 0.6, b - s * 0.7), Vector2(a + s * 0.6, b - s * 0.7), Vector2(a + s, b)]), S.call(-0.28))
		"escarpment", "bluffs":
			for i in N.call(0.05):
				var b: float = ry.call()
				var p := PackedVector2Array([Vector2(x, b)])
				var a := x
				while a < x + w:
					a += u
					p.append(Vector2(a, b + (r.next() - 0.5) * u * 0.4))
				ci.draw_polyline(p, S.call(-0.35), u * 0.12, true)
			grass.call(0.1, S.call(-0.25))
		"swamp":
			for i in N.call(0.18):
				var c := Vector2(rx.call(), ry.call())
				ci.draw_colored_polygon(_ellipse(c, u * (0.4 + r.next() * 0.5), u * 0.22), Color("#4c6a70aa"))
			var pts := PackedVector2Array()
			for i in N.call(0.3):
				var a: float = rx.call(); var b: float = ry.call()
				pts.append(Vector2(a, b)); pts.append(Vector2(a - u * 0.08, b - u * 0.45))
				pts.append(Vector2(a + u * 0.1, b)); pts.append(Vector2(a + u * 0.14, b - u * 0.35))
			ci.draw_multiline(pts, Color("#34482c"), u * 0.06, true)
		"tundra":
			for i in N.call(0.2):
				ci.draw_arc(Vector2(rx.call(), ry.call()), u * 0.5, PI * 1.1, PI * 1.9, 10, Color("#b9ccd6"), u * 0.07, true)
			for i in N.call(0.05): tree.call(rx.call(), ry.call(), u * 0.9, Color("#3d5a4a"))
		"dreamwood":
			for i in N.call(0.35):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * (0.9 + r.next() * 0.4)
				tree.call(a, b, s, Color("#4e3a78") if r.next() < 0.5 else Color("#6a4a9a"), Color("#2a1d3a"))
			for i in N.call(0.1): blob.call(rx.call(), ry.call(), u * 0.06, Color("#f5e6ff"))
		"stones":
			grass.call(0.25, S.call(-0.25))
			var cx := x + w / 2; var cy := y + h / 2; var R := minf(w, h) * 0.28
			for i in 8:
				var a := i / 8.0 * TAU
				ci.draw_rect(Rect2(cx + cos(a) * R - u * 0.12, cy + sin(a) * R * 0.6 - u * 0.45, u * 0.24, u * 0.45), Color("#6c6c78"))
		"village":
			grass.call(0.2, S.call(-0.2))
			for i in maxi(2, N.call(0.03)):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * 0.5
				ci.draw_rect(Rect2(a - s / 2, b - s / 2, s, s * 0.7), Color("#e8dcc0"))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(a - s * 0.6, b - s / 2), Vector2(a, b - s), Vector2(a + s * 0.6, b - s / 2)]), Color("#a0452e"))
		"watchfort":
			grass.call(0.25, S.call(-0.25))
			var cx := x + w / 2; var cy := y + h / 2; var s := minf(w, h) * 0.18
			ci.draw_rect(Rect2(cx - s / 2, cy - s, s, s * 1.4), Color("#5d554a"))
			for k in 3: ci.draw_rect(Rect2(cx - s / 2 + k * s * 0.38, cy - s * 1.15, s * 0.24, s * 0.2), Color("#7a7060"))
		"crossroads":
			grass.call(0.25, S.call(-0.25))
			ci.draw_line(Vector2(x, y + h / 2), Vector2(x + w, y + h / 2), Color("#a58e62"), u * 0.5)
			ci.draw_line(Vector2(x + w / 2, y), Vector2(x + w / 2, y + h), Color("#a58e62"), u * 0.5)
		"grove":
			for i in N.call(0.2):
				var a: float = rx.call(); var b: float = ry.call(); var s := u * (0.35 + r.next() * 0.3)
				blob.call(a, b, s, Color("#4f9a45") if r.next() < 0.5 else Color("#62b058"))
			for i in N.call(0.08): blob.call(rx.call(), ry.call(), u * 0.07, Color("#fff6c0"))
		"arena":
			grass.call(0.15, S.call(-0.2))
			ci.draw_polyline(_ellipse(Vector2(x + w / 2, y + h / 2), w * 0.33, h * 0.26, 0, TAU, 40), Color("#8a6a50"), u * 0.35, true)
		"nexus":
			for i in 4:
				var p0 := Vector2(rx.call(), y)
				var c1 := Vector2(rx.call(), ry.call())
				var c2 := Vector2(rx.call(), ry.call())
				var p3 := Vector2(rx.call(), y + h)
				var p := PackedVector2Array()
				for k in 25:
					var t := k / 24.0
					var q := 1 - t
					p.append(p0 * q * q * q + c1 * 3 * q * q * t + c2 * 3 * q * t * t + p3 * t * t * t)
				ci.draw_polyline(p, Color("#d8f0ffaa"), u * 0.08, true)
			for i in N.call(0.08): blob.call(rx.call(), ry.call(), u * 0.06, Color.WHITE)
		"mountain":
			for i in N.call(0.05):
				var a: float = rx.call(); var b := y + h * (0.35 + r.next() * 0.7); var s := u * (1.2 + r.next() * 1.1)
				peak.call(a, b, s, true)
		"chasm":
			var p := PackedVector2Array([Vector2(x + w * 0.35, y)])
			for k in 9: p.append(Vector2(x + w * (0.3 + r.next() * 0.1), y + h * k / 8.0))
			var right := []
			for k in range(8, -1, -1): right.append(Vector2(x + w * (0.6 + r.next() * 0.1), y + h * k / 8.0))
			for v in right: p.append(v)
			var tri := Geometry2D.triangulate_polygon(p)
			if tri.size():
				ci.draw_colored_polygon(p, Color("#0a0908"))
		"town": grass.call(0.2, S.call(-0.2))

static func terrain(ci: CanvasItem, id: String, rect: Rect2, seed_v: int, unit: float = 0.0, density: float = 1.0) -> void:
	base(ci, id, rect)
	motifs(ci, id, rect, seed_v, unit, density)
