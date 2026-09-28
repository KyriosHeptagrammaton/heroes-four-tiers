# Unit portrait: the hand-drawn creature (art/units/<faction>_<tier>.png), with
# its weapon in hand showing the upgrade path (sword = melee, bow = ranged,
# wand = magi; cavalry get a banner / spiked ball / serpent wand tinted in the
# unit's own colour), gold pips for the upgrade level, and riders drawn sitting
# on the right number of mounts.
class_name UnitSym
extends Control

var def: Dictionary = {}
var dim := false

static var _meta = null
static var _tex := {}
static var _portraits = null   # Options → "Unit icons": portraits or abstract symbols
const CFG_PATH := "user://settings.cfg"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_to_group("unitsym")

static func portraits() -> bool:
	if _portraits == null:
		var cf := ConfigFile.new()
		_portraits = cf.get_value("display", "portraits", true) if cf.load(CFG_PATH) == OK else true
	return _portraits

static func set_portraits(on: bool) -> void:
	_portraits = on
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("display", "portraits", on)
	cf.save(CFG_PATH)

## the original placeholder: tier shape (1 circle, 2 triangle, 3 square, 4 star) in
## faction colour with the faction glyph; arrow = ranged, ✦ = magi, » = cavalry
static func draw_abstract(ci: CanvasItem, d: Dictionary, rect: Rect2, dim_it: bool = false) -> void:
	var k := minf(rect.size.x, rect.size.y) / 40.0
	var o := rect.position + Vector2((rect.size.x - 40 * k) / 2, (rect.size.y - 40 * k) / 2)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	var mod := Color(1, 1, 1, 0.3) if dim_it else Color(1, 1, 1, 1)
	var font: Font = UI.font_bold
	if d.get("mounted", false):
		# each creature gets its own full symbol: the mounts along the bottom, the rider above
		var R := Units.resolve(d.riderKey)
		var Mo := Units.resolve(d.mountKey)
		var n: int = maxi(1, int(d.get("mountsPer", 1)))
		var shown := mini(n, 4)
		var box := 40.0 * k
		var ms := box * (0.62 if shown == 1 else (0.5 if shown == 2 else 0.4))
		var step := ms * 0.8
		var row_w := ms + step * (shown - 1)
		var top := o.y + box - ms
		for i in shown:
			draw_abstract(ci, Mo, Rect2(o.x + (box - row_w) / 2 + i * step, top, ms, ms), dim_it)
		var rs := box * 0.52
		draw_abstract(ci, R, Rect2(o.x + (box - rs) / 2, top - rs * 0.72, rs, rs), dim_it)
		if n > shown:
			_count_label(ci, "×%d" % n, rect, box, mod)
		return
	else:
		draw_shape(ci, mini(4, d.tier), P.call(20, 20), 14 * k, Color(D.FACTIONS[d.faction].color) * mod, Color.BLACK * mod, 1.5 * k)
		var g: String = D.FACTIONS[d.faction].glyph
		var fs := int(maxf(6, 12 * k))
		var tw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = P.call(20, 24.5) - Vector2(tw / 2, 0)
		ci.draw_string_outline(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(2 * k), Color(0, 0, 0, 0.55) * mod)
		ci.draw_string(font, pos, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE * mod)
	if d.ab.get("ranged", false):
		ci.draw_line(P.call(30, 10), P.call(39, 1), Color.WHITE * mod, 2 * k)
		ci.draw_polyline(PackedVector2Array([P.call(34, 1), P.call(39, 1), P.call(39, 6)]), Color.WHITE * mod, 2 * k)
	if d.get("mod", "") == "m":
		ci.draw_string(UI.font, P.call(1, 11), "✦", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(6, 12 * k)), Color("#e9d0ff") * mod)
	if d.up >= 1:
		ci.draw_circle(P.call(36, 37), 2.2 * k, Color("#f0d68e") * mod)
		if d.up >= 2:
			ci.draw_circle(P.call(30, 37), 2.2 * k, Color("#f0d68e") * mod)
	if d.ab.get("cavalry", false):
		ci.draw_string(UI.font_bold, P.call(0, 39), "»", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(6, 12 * k)), Color.WHITE * mod)

static func meta() -> Dictionary:
	if _meta == null:
		var f := FileAccess.open("res://art/units.json", FileAccess.READ)
		_meta = JSON.parse_string(f.get_as_text()) if f else {"units": {}, "weapons": {}}
	return _meta

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

## portrait extent (px) for a unit drawn in a box of size `box`: tier 1 art is
## small and tier 4 big, so keep that difference but compress it to stay legible
static func _extent(m: Dictionary, box: float) -> float:
	var ext: float = maxf(m.w, m.h)
	var k := clampf((ext - 26.0) / 70.0, 0.0, 1.0)
	return box * (0.58 + 0.42 * k)

## weapon for a unit definition: "" (base creature), "melee", "ranged" or "magi"
static func _path(d: Dictionary) -> String:
	if d.up < 1: return ""
	return {"": "melee", "r": "ranged", "m": "magi"}.get(d.mod, "melee")

## draw one creature (no rider logic) centred at `c` with portrait extent `ext`
## pass "body" draws the portrait, pass "gear" its weapon(s) and upgrade pips, "all" both
static func _draw_creature(ci: CanvasItem, d: Dictionary, c: Vector2, ext: float, mod: Color, cav: bool, pass_: String = "all", pips: bool = false) -> void:
	var key := "%s_%d" % [d.faction, mini(4, d.tier)]
	var M: Dictionary = meta().units.get(key, {})
	var t := tex("res://art/units/%s.png" % key)
	if t == null or M.is_empty():
		ci.draw_circle(c, ext * 0.4, Color(D.FACTIONS[d.faction].color) * mod)
		return
	var s: float = ext / maxf(M.w, M.h)
	var size := Vector2(M.w, M.h) * s
	var o := c - size / 2
	if pass_ != "gear":
		ci.draw_texture_rect(t, Rect2(o, size), false, mod)
	if pass_ == "body":
		return
	if pips and d.up >= 1:
		var k := ext / 40.0
		var base := c + Vector2(size.x / 2, size.y / 2)
		for i in mini(2, int(d.up)):
			var pp := base - Vector2(2 + i * 6, 1) * k
			ci.draw_circle(pp, 2.8 * k, Color(0, 0, 0, 0.7) * mod)
			ci.draw_circle(pp, 2.1 * k, Color("#f0d68e") * mod)
	var p := _path(d)
	if p == "":
		return
	var wkey := p + ("_cav" if cav else "_inf")
	var W: Dictionary = meta().weapons.get(wkey, {})
	var wt := tex("res://art/weapons/%s.png" % wkey)
	if wt == null or W.is_empty():
		return
	var tint := tex("res://art/weapons/%s_tint.png" % wkey) if W.get("tint", false) else null
	var ucol := Color(M.get("color", "#ffffff"))
	for h in M.get("hands", []):
		var target: float = clampf(h.d * 1.4 * s, ext * 0.32, ext * 0.55)
		var ws: float = target / maxf(W.w, W.h)
		var wsize := Vector2(W.w, W.h) * ws
		var wc := o + Vector2(h.x, h.y) * s
		var r := Rect2(wc - wsize / 2, wsize)
		ci.draw_texture_rect(wt, r, false, mod)
		if tint:
			ci.draw_texture_rect(tint, r, false, ucol * mod)

static func _count_label(ci: CanvasItem, txt: String, rect: Rect2, box: float, mod: Color) -> void:
	var f: Font = UI.font_bold
	var fs := int(maxf(8, box * 0.26))
	var pos := Vector2(rect.end.x - f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, rect.end.y)
	ci.draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8) * mod)
	ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE * mod)

## draw a unit (including riders on their mounts) inside `rect`
static func draw_unit(ci: CanvasItem, d: Dictionary, rect: Rect2, dim_it: bool = false) -> void:
	if not portraits():
		draw_abstract(ci, d, rect, dim_it)
		return
	var mod := Color(1, 1, 1, 0.3) if dim_it else Color.WHITE
	var box := minf(rect.size.x, rect.size.y)
	var c := rect.get_center()
	if d.get("mounted", false):
		var R := Units.resolve(d.riderKey)
		var Mo := Units.resolve(d.mountKey)
		var n: int = maxi(1, int(d.get("mountsPer", 1)))
		var shown := mini(n, 4)
		# mounts side by side along the bottom, overlapping a little
		var mext := box * (0.62 if shown == 1 else (0.5 if shown == 2 else 0.4))
		var step := mext * 0.72
		var row_w := mext + step * (shown - 1)
		var my := rect.position.y + (rect.size.y + box) / 2 - mext * 0.5
		# rider on top; everyone shows their own weapon and upgrade, drawn over all the bodies
		var rext := box * 0.52
		var rc := Vector2(c.x, my - mext * 0.42 - rext * 0.28)
		for pass_ in ["body", "gear"]:
			for i in shown:
				var mx := c.x - row_w / 2 + mext / 2 + i * step
				_draw_creature(ci, Mo, Vector2(mx, my), mext, mod, Mo.ab.get("cavalry", false), pass_, i == shown - 1)
			_draw_creature(ci, R, rc, rext, mod, R.ab.get("cavalry", false), pass_, true)
		if n > shown:
			_count_label(ci, "×%d" % n, rect, box, mod)
		return
	else:
		var key := "%s_%d" % [d.faction, mini(4, d.tier)]
		var M: Dictionary = meta().units.get(key, {"w": 40, "h": 40})
		_draw_creature(ci, d, c, _extent(M, box), mod, d.ab.get("cavalry", false))
	# upgrade level pips
	if d.up >= 1:
		var k := box / 40.0
		var base := rect.position + Vector2((rect.size.x + box) / 2, (rect.size.y + box) / 2)
		for i in mini(2, int(d.up)):
			var p := base - Vector2(4 + i * 6, 3) * k
			ci.draw_circle(p, 2.6 * k, Color(0, 0, 0, 0.7) * mod)
			ci.draw_circle(p, 2.0 * k, Color("#f0d68e") * mod)

func _draw() -> void:
	if def.is_empty():
		return
	draw_unit(self, def, Rect2(Vector2.ZERO, size), dim)

# ---- simple tier shapes (kept for anything that still wants an abstract mark)
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

static func draw_shape(ci: CanvasItem, tier: int, c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	var p := shape_points(tier, c.x, c.y, r)
	if tier == 4:
		for i in 10:
			ci.draw_colored_polygon(PackedVector2Array([c, p[i], p[(i + 1) % 10]]), fill)
	else:
		ci.draw_colored_polygon(p, fill)
	var q := p.duplicate()
	q.append(p[0])
	ci.draw_polyline(q, stroke, w, true)
