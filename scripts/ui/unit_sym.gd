# Abstract unit symbol: tier shape (1 circle, 2 triangle, 3 square, 4 star) in
# faction colour, faction glyph, and marks for ranged / magi / upgrades / cavalry.
class_name UnitSym
extends Control

var def: Dictionary = {}
var dim := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

static func shape_points(tier: int, cx: float, cy: float, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	match tier:
		1:
			for i in 24:
				var a := TAU * i / 24.0
				p.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
		2:
			p.append(Vector2(cx, cy - r)); p.append(Vector2(cx + r * 0.95, cy + r * 0.8)); p.append(Vector2(cx - r * 0.95, cy + r * 0.8))
		3:
			var k := r * 0.85
			p.append(Vector2(cx - k, cy - k)); p.append(Vector2(cx + k, cy - k)); p.append(Vector2(cx + k, cy + k)); p.append(Vector2(cx - k, cy + k))
		_:
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				var rr := r * 0.45 if i % 2 else r
				p.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	return p

## draw a filled, outlined tier shape on any CanvasItem
static func draw_shape(ci: CanvasItem, tier: int, c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	var p := shape_points(tier, c.x, c.y, r)
	if tier == 4:
		# concave star: fan triangles from the centre
		for i in 10:
			ci.draw_colored_polygon(PackedVector2Array([c, p[i], p[(i + 1) % 10]]), fill)
	else:
		ci.draw_colored_polygon(p, fill)
	var q := p.duplicate()
	q.append(p[0])
	ci.draw_polyline(q, stroke, w, true)

func _draw() -> void:
	if def.is_empty():
		return
	var k := minf(size.x, size.y) / 40.0
	var o := Vector2((size.x - 40 * k) / 2, (size.y - 40 * k) / 2)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var mod := Color(1, 1, 1, 0.3) if dim else Color(1, 1, 1, 1)
	var fcol: Color = Color(D.FACTIONS[def.faction].color) * mod
	var font: Font = UI.font_bold
	if def.mounted:
		var R := Units.resolve(def.riderKey)
		var M := Units.resolve(def.mountKey)
		draw_shape(self, mini(4, M.tier), P.call(20, 26), 11 * k, Color(Color(D.FACTIONS[M.faction].color), 0.9) * mod, Color.BLACK * mod, 1.5 * k)
		draw_shape(self, mini(4, R.tier), P.call(20, 13), 8 * k, Color(D.FACTIONS[R.faction].color) * mod, Color.WHITE * mod, 1.5 * k)
	else:
		draw_shape(self, mini(4, def.tier), P.call(20, 20), 14 * k, fcol, Color.BLACK * mod, 1.5 * k)
		var g: String = D.FACTIONS[def.faction].glyph
		var fs := int(maxf(6, 12 * k))
		var tw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = P.call(20, 24.5) - Vector2(tw / 2, 0)
		draw_string_outline(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(2 * k), Color(0, 0, 0, 0.55) * mod)
		draw_string(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE * mod)
	if def.ab.get("ranged", false):
		draw_line(P.call(30, 10), P.call(39, 1), Color.WHITE * mod, 2 * k)
		draw_polyline(PackedVector2Array([P.call(34, 1), P.call(39, 1), P.call(39, 6)]), Color.WHITE * mod, 2 * k)
	if def.mod == "m":
		draw_string(UI.font, P.call(1, 11), "✦", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(6, 12 * k)), Color("#e9d0ff") * mod)
	if def.up >= 1:
		draw_circle(P.call(36, 37), 2.2 * k, Color("#f0d68e") * mod)
		if def.up >= 2:
			draw_circle(P.call(30, 37), 2.2 * k, Color("#f0d68e") * mod)
	if def.ab.get("cavalry", false):
		draw_string(UI.font_bold, P.call(0, 39), "»", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(6, 12 * k)), Color.WHITE * mod)
