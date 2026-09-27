# ============================================================================
# StoneBox — a mid-90s style box: square corners, a tiled grain/stone texture,
# a raised or sunken bevel, a dark outline, an optional gold trim line and
# corner studs. Used for buttons, panels, dialogs, cards and chips.
# ============================================================================
class_name StoneBox
extends StyleBox

var fill := Color("#5e564a")
var outline := Color(0, 0, 0, 0.9)
var outline_w := 1
var bevel := 3
var raised := true
var light := Color(1, 0.96, 0.85, 0.28)
var dark := Color(0, 0, 0, 0.45)
var tex: Texture2D = null        # tileable grain (white/black speckle with alpha)
var tex_alpha := 1.0
var trim := Color(0, 0, 0, 0)    # thin inner line (e.g. gold)
var studs := false
var accent_top := Color(0, 0, 0, 0)     # thick coloured band along an edge
var accent_bottom := Color(0, 0, 0, 0)
var accent_w := 4
var halo := Color(0, 0, 0, 0)    # frame drawn just outside the box (selection)
var halo_w := 3

func margins(h: float, v: float = -1.0) -> StoneBox:
	content_margin_left = h; content_margin_right = h
	content_margin_top = h if v < 0 else v
	content_margin_bottom = h if v < 0 else v
	return self

func copy() -> StoneBox:
	var s := StoneBox.new()
	for p in ["fill", "outline", "outline_w", "bevel", "raised", "light", "dark", "tex", "tex_alpha", "trim", "studs", "accent_top", "accent_bottom", "accent_w", "halo", "halo_w",
			"content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		s.set(p, get(p))
	return s

func _frame(ci: RID, r: Rect2, c: Color, w: float) -> void:
	var rs := RenderingServer
	rs.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, w)), c)
	rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - w, r.size.x, w), c)
	rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.position.y + w, w, r.size.y - 2 * w), c)
	rs.canvas_item_add_rect(ci, Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2 * w), c)

func _draw(ci: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var r := rect
	if halo.a > 0:
		_frame(ci, r.grow(halo_w), halo, halo_w)
	if outline.a > 0 and outline_w > 0:
		_frame(ci, r, outline, outline_w)
		r = r.grow(-outline_w)
	if r.size.x <= 0 or r.size.y <= 0:
		return
	if fill.a > 0:
		rs.canvas_item_add_rect(ci, r, fill)
		if tex != null and tex_alpha > 0:
			rs.canvas_item_add_texture_rect(ci, r, tex.get_rid(), true, Color(1, 1, 1, tex_alpha * fill.a))
	if accent_top.a > 0:
		rs.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, accent_w)), accent_top)
	if accent_bottom.a > 0:
		rs.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - accent_w, r.size.x, accent_w), accent_bottom)
	var b := float(mini(bevel, int(minf(r.size.x, r.size.y) / 2)))
	if b > 0:
		var hi := light if raised else dark
		var lo := dark if raised else light
		var tl := r.position
		var tr := Vector2(r.end.x, r.position.y)
		var br := r.end
		var bl := Vector2(r.position.x, r.end.y)
		var d := Vector2(b, b)
		rs.canvas_item_add_polygon(ci, PackedVector2Array([tl, tr, tr + Vector2(-b, b), tl + d]), PackedColorArray([hi]))
		rs.canvas_item_add_polygon(ci, PackedVector2Array([tl, tl + d, bl + Vector2(b, -b), bl]), PackedColorArray([hi]))
		rs.canvas_item_add_polygon(ci, PackedVector2Array([bl, bl + Vector2(b, -b), br - d, br]), PackedColorArray([lo]))
		rs.canvas_item_add_polygon(ci, PackedVector2Array([tr, br, br - d, tr + Vector2(-b, b)]), PackedColorArray([lo]))
	if trim.a > 0:
		var tr_r := r.grow(-(b + 1))
		if tr_r.size.x > 2 and tr_r.size.y > 2:
			_frame(ci, tr_r, trim, 1)
	if studs and r.size.x > 30 and r.size.y > 30:
		var k := b + 5.0
		for p in [r.position + Vector2(k, k), Vector2(r.end.x - k, r.position.y + k), r.end - Vector2(k, k), Vector2(r.position.x + k, r.end.y - k)]:
			rs.canvas_item_add_circle(ci, p + Vector2(0.6, 0.8), 3.2, Color(0, 0, 0, 0.6))
			rs.canvas_item_add_circle(ci, p, 2.8, Color("#8a6a2e"))
			rs.canvas_item_add_circle(ci, p - Vector2(0.8, 0.8), 1.2, Color("#f3d98e"))
