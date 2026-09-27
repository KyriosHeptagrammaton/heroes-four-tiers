# ============================================================================
# Overworld screen: the card map (baked terrain texture + live layers) and the
# side panel. Drag / WASD to pan, wheel to zoom, click to plan a path, click
# again or Space to go, right-click / Esc cancels a path or names a card.
# ============================================================================
extends Control

const BASE := 128           # baked pixels per card
var cam := {"x": 0.0, "y": 0.0, "z": 88.0}
var sel_hero := ""
var path = null
var hover = null
var anim := false
var tex: Texture2D = null
var tex_seed := -1
var _baking := false

var map: Control
var fog: Control
var top: Control
var side: VBoxContainer
var hover_panel: PanelContainer
var hover_rtl: RichTextLabel
var _down = null
var _built := false
var _star_mat: ShaderMaterial

func reset_view() -> void:
	tex = null
	tex_seed = -1
	sel_hero = ""
	path = null
	hover = null

# ------------------------------------------------------------------ build
func _build() -> void:
	_built = true
	var root := UI.hbox([], 0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	map = Control.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.clip_contents = true
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	map.mouse_exited.connect(func():
		hover = null
		hover_panel.visible = false)
	root.add_child(map)
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = load("res://scripts/ui/stars.gdshader")
	fog = Control.new()
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.material = _star_mat
	fog.draw.connect(_draw_fog)
	map.add_child(fog)
	top = Control.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.draw.connect(_draw_top)
	map.add_child(top)
	hover_rtl = UI.rich("", 12)
	hover_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_rtl.custom_minimum_size.x = 340
	hover_panel = UI.panel(hover_rtl, UI.sb(Color(0.055, 0.06, 0.07, 0.91), UI.C.line2, 8, 1, 10, 8))
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.visible = false
	map.add_child(hover_panel)
	var tb := UI.hbox([
		UI.button("+", func(): zoom(1.2), "Small", "Zoom in (mouse wheel)"),
		UI.button("−", func(): zoom(1 / 1.2), "Small", "Zoom out"),
		UI.button("☰ Menu", func(): Main.menu(), "Small", "Main menu (game stays open)"),
		UI.button("▣ Save", Game.save_dialog, "Small"),
		UI.button("⚑ Flags", Main.flags, "Small"),
		UI.button("? Help", help, "Small"),
		Music.control()], 6)
	tb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tb.position = Vector2(-10, 10)
	tb.offset_right = -10
	tb.offset_top = 10
	map.add_child(tb)
	side = UI.vbox([], 0)
	side.custom_minimum_size.x = 330
	root.add_child(UI.panel(side, UI.sb(UI.C.bg2, UI.C.line, 0, 1, 0)))

func enter(recenter: bool = true) -> void:
	if not _built:
		_build()
	UI.show("world")
	var S = Game.state
	var mine := World.heroes_of(S.cur)
	var h = World.hero(sel_hero) if sel_hero != "" else null
	if h == null or h.owner != S.cur or not h.alive:
		sel_hero = mine[0].id if mine.size() else ""
	path = null
	if tex == null or tex_seed != S.seed:
		build_cache()
	if recenter:
		await get_tree().process_frame
		center_on_sel()
	render_side()
	redraw()

func redraw() -> void:
	if map:
		map.queue_redraw(); fog.queue_redraw(); top.queue_redraw()

func _process(_d: float) -> void:
	if visible and Game.state != null and map:
		_clamp_cam()
		redraw()
		hover_panel.position = Vector2(10, map.size.y - hover_panel.size.y - 10)

# ------------------------------------------------------------------ camera
func zoom(f: float, at = null) -> void:
	var old: float = cam.z
	var nz := clampf(old * f, 34, 220)
	var m: Vector2 = at if at != null else map.size / 2
	cam.x = (cam.x + m.x) * nz / old - m.x
	cam.y = (cam.y + m.y) * nz / old - m.y
	cam.z = nz
	redraw()

func center_on(c: int, x: int, y: int) -> void:
	var z: float = cam.z
	var s: int = World.card(c).size
	var px: float = (World.cx(c) + (x + 0.5) / s) * z
	var py: float = (World.cy(c) + (y + 0.5) / s) * z
	cam.x = px - map.size.x / 2
	cam.y = py - map.size.y / 2
	redraw()

func center_on_sel() -> void:
	var h = World.hero(sel_hero) if sel_hero != "" else null
	if h != null:
		center_on(h.pos.c, h.pos.x, h.pos.y)
	else:
		var ts := World.towns_of(Game.state.cur)
		if ts.size(): center_on(ts[0].c, ts[0].x, ts[0].y)

func _clamp_cam() -> void:
	var S = Game.state
	var z: float = cam.z
	var mw: float = S.map.W * z
	var mh: float = S.map.H * z
	var cw := map.size.x
	var ch := map.size.y
	var m := z * 1.5
	cam.x = (mw - cw) / 2 if mw + 2 * m < cw else clampf(cam.x, -m, mw - cw + m)
	cam.y = (mh - ch) / 2 if mh + 2 * m < ch else clampf(cam.y, -m, mh - ch + m)

func tile_rect(c: int, x: int, y: int) -> Rect2:
	var z: float = cam.z
	var s: int = World.card(c).size
	var X: float = World.cx(c) * z - cam.x
	var Y: float = World.cy(c) * z - cam.y
	return Rect2(X + x * z / s, Y + y * z / s, z / s, z / s)

func card_center(c: int) -> Vector2:
	var z: float = cam.z
	return Vector2((World.cx(c) + 0.5) * z - cam.x, (World.cy(c) + 0.5) * z - cam.y)

# ------------------------------------------------------------------ baked terrain
func build_cache() -> void:
	if _baking: return
	_baking = true
	var S = Game.state
	var W: int = S.map.W
	var H: int = S.map.H
	var vp := SubViewport.new()
	vp.size = Vector2i(W * BASE, H * BASE)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_2X
	var painter := Control.new()
	painter.size = Vector2(vp.size)
	painter.draw.connect(func(): _paint_map(painter, S))
	vp.add_child(painter)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		tex_seed = S.seed
	vp.queue_free()
	_baking = false
	redraw()

func _paint_map(ci: Control, S: Dictionary) -> void:
	var W: int = S.map.W
	var B := float(BASE)
	var cards: Array = S.map.cards
	for c in cards.size():
		Paint.base(ci, cards[c].t, Rect2((c % W) * B, (c / W) * B, B, B))
	for c in cards.size():
		Paint.motifs(ci, cards[c].t, Rect2((c % W) * B, (c / W) * B, B, B), c * 31 + 7, B / 7.0)
	for c in cards.size():
		var card: Dictionary = cards[c]
		var x := (c % W) * B
		var y := (c / W) * B
		var s: int = card.size
		if s > 1:
			var pts := PackedVector2Array()
			for k in range(1, s):
				pts.append(Vector2(x + k * B / s, y)); pts.append(Vector2(x + k * B / s, y + B))
				pts.append(Vector2(x, y + k * B / s)); pts.append(Vector2(x + B, y + k * B / s))
			ci.draw_multiline(pts, Color(0, 0, 0, 0.15), 1.0)
		if card.road[0] or card.road[1] or card.road[2] or card.road[3]:
			var m := s >> 1
			var cc := Vector2(x + (m + 0.5) * B / s, y + (m + 0.5) * B / s)
			var ends := [Vector2(cc.x, y), Vector2(x + B, cc.y), Vector2(cc.x, y + B), Vector2(x, cc.y)]
			for pass_i in 2:
				var col := Color("#8a6d45") if pass_i == 0 else Color("#c9a877")
				var wdt := B * (0.09 if pass_i == 0 else 0.035)
				for e in 4:
					if card.road[e]:
						ci.draw_line(cc, ends[e], col, wdt, true)
				ci.draw_circle(cc, wdt / 2, col)
		ci.draw_rect(Rect2(x + 0.75, y + 0.75, B - 1.5, B - 1.5), Color(0, 0, 0, 0.33), false, 1.5)

# ------------------------------------------------------------------ drawing
func _visible_range() -> Array:
	var S = Game.state
	var z: float = cam.z
	return [maxi(0, int(floor(cam.x / z))), maxi(0, int(floor(cam.y / z))),
		mini(S.map.W - 1, int(floor((cam.x + map.size.x) / z))), mini(S.map.H - 1, int(floor((cam.y + map.size.y) / z)))]

func _text_c(ci: CanvasItem, f: Font, center: Vector2, t: String, fs: int, col: Color, outline: int = 0, ocol: Color = Color.BLACK) -> void:
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(center.x - tw / 2, center.y + fs * 0.36)
	if outline > 0:
		ci.draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, ocol)
	ci.draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_map() -> void:
	var S = Game.state
	if S == null: return
	var W: int = S.map.W
	var z: float = cam.z
	var P: Dictionary = S.players[S.cur]
	if World.vmask[S.cur].is_empty(): World.compute_visible(S.cur)
	if tex != null:
		map.draw_texture_rect(tex, Rect2(-cam.x, -cam.y, W * z, S.map.H * z), false)
	else:
		for c in S.map.cards.size():
			map.draw_rect(Rect2((c % W) * z - cam.x, (c / W) * z - cam.y, z, z), Color(D.TERRAIN[S.map.cards[c].t].color))
	var vr := _visible_range()
	var act = P.trans.active
	var now := Time.get_ticks_msec() / 1000.0
	for cy in range(vr[1], vr[3] + 1):
		for cx in range(vr[0], vr[2] + 1):
			var c: int = cy * W + cx
			var X: float = cx * z - cam.x
			var Y: float = cy * z - cam.y
			if P.seen[c] and P.trans.cards.has(c):
				var pulse := 0.5 + 0.5 * sin(now * 2.5 + c)
				map.draw_rect(Rect2(X + 4, Y + 4, z - 8, z - 8), Color(0.75, 0.55, 1.0, 0.45 + 0.4 * pulse), false, 3)
				map.draw_string(UI.font, Vector2(X + 6, Y + z * 0.2), "✧", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(10, z * 0.16)), Color("#d8b8ff"))
			if act != null and act.region.has(c) and P.seen[c]:
				map.draw_rect(Rect2(X, Y, z, z), Color(0.63, 0.43, 1.0, 0.13))
	# objects
	for cy in range(vr[1], vr[3] + 1):
		for cx in range(vr[0], vr[2] + 1):
			var c: int = cy * W + cx
			if not P.seen[c]: continue
			for o in S.map.cards[c].objs:
				if not World.tile_seen(P, c, o.x, o.y): continue
				if o.get("hidden", false) and not World.sub_seen(P, c, o.x, o.y): continue
				_draw_obj(o, c)
	# parked trains
	for h in S.heroes.values():
		if h.alive and h.train != null and h.train.state == "parked" and (h.owner == S.cur or World.tile_vis(S.cur, h.train.at.c, h.train.at.x, h.train.at.y)):
			var r := tile_rect(h.train.at.c, h.train.at.x, h.train.at.y)
			var ctr := r.get_center()
			var rr := minf(r.size.x, r.size.y) * 0.32
			var body := Rect2(ctr.x - rr, ctr.y - rr * 0.5, rr * 2, rr)
			map.draw_rect(body, Color(S.players[h.owner].color))
			map.draw_rect(body, Color.BLACK, false, 1.5)
			map.draw_circle(Vector2(ctr.x - rr * 0.6, ctr.y + rr * 0.55), rr * 0.3, Color("#222"))
			map.draw_circle(Vector2(ctr.x + rr * 0.6, ctr.y + rr * 0.55), rr * 0.3, Color("#222"))

func _draw_obj(o: Dictionary, c: int) -> void:
	var S = Game.state
	var r := tile_rect(c, o.x, o.y)
	var ctr := r.get_center()
	var R := maxf(7, minf(r.size.x * 0.38, cam.z * 0.19))
	var def: Dictionary = D.OBJ[o.type]
	if o.type == "town":
		var t: Dictionary = S.towns[o.town]
		var col := Color(S.players[t.owner].color) if t.owner >= 0 else Color("#999")
		var rr := R * 1.25
		var body := Rect2(ctr.x - rr, ctr.y - rr * 0.7, rr * 2, rr * 1.4)
		map.draw_rect(body, Color("#2a2622"))
		map.draw_rect(body, col, false, 3)
		for k in 4:
			map.draw_rect(Rect2(ctr.x - rr + k * rr * 0.62, ctr.y - rr * 0.95, rr * 0.3, rr * 0.3), col)
		_text_c(map, UI.font, ctr + Vector2(0, 1), "♛" if t.capital else "♜", int(rr * 0.9), Color("#e8dcc0"))
		if cam.z > 50:
			var fs := int(maxf(10, cam.z * 0.13))
			var tw := UI.font_bold.get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			map.draw_rect(Rect2(ctr.x - tw / 2 - 3, ctr.y + rr * 0.8, tw + 6, cam.z * 0.17), Color(0, 0, 0, 0.66))
			_text_c(map, UI.font_bold, Vector2(ctr.x, ctr.y + rr * 0.8 + cam.z * 0.085), t.name, fs, Color.WHITE)
		return
	if o.type == "monster":
		var st: Dictionary = o.army.stacks[0]
		for s in o.army.stacks:
			if Units.resolve(s.key).tier > Units.resolve(st.key).tier: st = s
		var d := Units.resolve(st.key)
		map.draw_circle(ctr, R * 1.05, Color(0, 0, 0, 0.66))
		UnitSym.draw_shape(map, mini(4, d.tier), ctr, R * 0.75, Color(D.FACTIONS[d.faction].color), Color.BLACK, 1.5)
		var n := 0
		for s in o.army.stacks: n += s.count
		_text_c(map, UI.font_bold, ctr + Vector2(0, R * 1.05), count_word(n), int(maxf(9, R * 0.62)), Color.WHITE, 3)
		return
	var ring = null
	if o.type == "mine": ring = Color(S.players[o.owner].color) if o.owner >= 0 else Color("#777")
	map.draw_circle(ctr, R, Color(0.063, 0.067, 0.086, 0.87))
	var rc: Color = ring if ring != null else (Color("#ff7a6a") if o.has("guard") else Color.BLACK)
	map.draw_arc(ctr, R, 0, TAU, 28, rc, 2.5 if (o.has("guard") or ring != null) else 1.0, true)
	_text_c(map, UI.font, ctr + Vector2(0, 1), def.glyph, int(R * 1.2), Color(def.color))
	if o.has("guard"):
		_text_c(map, UI.font_bold, ctr + Vector2(R * 0.85, -R * 0.75), "!", int(maxf(8, R * 0.6)), Color("#ff7a6a"))

func _draw_fog() -> void:
	var S = Game.state
	if S == null: return
	_star_mat.set_shader_parameter("cam", Vector2(cam.x, cam.y))
	var W: int = S.map.W
	var H: int = S.map.H
	var z: float = cam.z
	var P: Dictionary = S.players[S.cur]
	var sky := Color.WHITE
	var dim := Color(0.031, 0.035, 0.047, 0.45)
	# space around the map
	var mx: float = -cam.x
	var my: float = -cam.y
	var mw := W * z
	var mh := H * z
	var sz := map.size
	if my > 0: fog.draw_rect(Rect2(0, 0, sz.x, my), sky)
	if my + mh < sz.y: fog.draw_rect(Rect2(0, my + mh, sz.x, sz.y - my - mh), sky)
	if mx > 0: fog.draw_rect(Rect2(0, my, mx, mh), sky)
	if mx + mw < sz.x: fog.draw_rect(Rect2(mx + mw, my, sz.x - mx - mw, mh), sky)
	var vr := _visible_range()
	var vm: Dictionary = World.vmask[S.cur]
	for cy in range(vr[1], vr[3] + 1):
		for cx in range(vr[0], vr[2] + 1):
			var c: int = cy * W + cx
			var X: float = cx * z - cam.x
			var Y: float = cy * z - cam.y
			if not P.seen[c]:
				fog.draw_rect(Rect2(X - 0.5, Y - 0.5, z + 1, z + 1), sky)
				continue
			var s: int = S.map.cards[c].size
			var full := World.full_mask(c)
			var seen_m: int = int(P.tmask[c]) & full
			var vis_m: int = int(vm.get(c, 0)) & full
			if seen_m == full and vis_m == full: continue
			if seen_m == full and vis_m == 0:
				fog.draw_rect(Rect2(X, Y, z, z), dim)
				continue
			var ts := z / s
			for ty in s:
				for tx in s:
					var bit := 1 << (ty * s + tx)
					if not (seen_m & bit):
						fog.draw_rect(Rect2(X + tx * ts - 0.5, Y + ty * ts - 0.5, ts + 1, ts + 1), sky)
					elif not (vis_m & bit):
						fog.draw_rect(Rect2(X + tx * ts, Y + ty * ts, ts, ts), dim)

func _draw_top() -> void:
	var S = Game.state
	if S == null: return
	var P: Dictionary = S.players[S.cur]
	var z: float = cam.z
	# transcendent lines
	var lines: Array = P.trans.lines.duplicate()
	if P.trans.active != null: lines.append(P.trans.active.line)
	for line in lines: _draw_trans_line(line)
	# heroes
	for h in S.heroes.values():
		if not h.alive: continue
		if h.owner != S.cur and not World.tile_vis(S.cur, h.pos.c, h.pos.x, h.pos.y): continue
		_draw_hero(h)
	# path
	if path != null:
		var hero = World.hero(sel_hero)
		var mp: int = hero.mp if hero != null else 0
		for i in path.size():
			var n: Dictionary = path[i]
			var r := tile_rect(n.c, n.x, n.y)
			var last: bool = i == path.size() - 1
			var rad := maxf(2.5, minf(r.size.x, r.size.y) * (0.16 if last else 0.09))
			top.draw_circle(r.get_center(), rad, Color("#7fe08a") if i < mp else Color("#e0b050"))
			if last: top.draw_arc(r.get_center(), rad, 0, TAU, 20, Color.BLACK, 1, true)
	# player-given card names
	if z >= 44:
		var vr := _visible_range()
		var fs := int(maxf(10, minf(15, z * 0.12)))
		for cy in range(vr[1], vr[3] + 1):
			for cx in range(vr[0], vr[2] + 1):
				var c: int = cy * S.map.W + cx
				var card: Dictionary = S.map.cards[c]
				if card.get("name", "") == "" or not P.seen[c]: continue
				var X: float = cx * z - cam.x + z / 2
				var Y: float = cy * z - cam.y + 3
				var tw := UI.font_bold.get_string_size(card.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				top.draw_rect(Rect2(X - tw / 2 - 4, Y - 1, tw + 8, fs + 5), Color(0, 0, 0, 0.66))
				top.draw_string(UI.font_bold, Vector2(X - tw / 2, Y + fs), card.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f0d68e"))
	# hover highlight
	if hover != null:
		var r := tile_rect(hover.c, hover.x, hover.y)
		top.draw_rect(r.grow(-1), Color(1, 1, 1, 0.53), false, 1.5)
		var cc := card_center(hover.c)
		top.draw_rect(Rect2(cc.x - z / 2 + 0.5, cc.y - z / 2 + 0.5, z - 1, z - 1), Color(1, 1, 1, 0.19), false, 1)

func _draw_trans_line(line: Array) -> void:
	if line.size() < 2: return
	for i in range(1, line.size()):
		var a := card_center(line[i - 1])
		var b := card_center(line[i])
		var jump := World.cheb(line[i - 1], line[i]) > 1
		var pts := PackedVector2Array()
		if jump:
			var m := (a + b) / 2 - Vector2(0, a.distance_to(b) * 0.25)
			for k in 33:
				var t := k / 32.0
				pts.append(a.lerp(m, t).lerp(m.lerp(b, t), t))
		else:
			pts = PackedVector2Array([a, b])
		for glow in [[10.0, 0.10], [6.0, 0.18]]:
			if jump:
				for k in range(0, pts.size() - 1, 2): top.draw_line(pts[k], pts[k + 1], Color(0.78, 0.61, 1.0, glow[1]), glow[0], true)
			else:
				top.draw_polyline(pts, Color(0.78, 0.61, 1.0, glow[1]), glow[0], true)
		var core := Color(0.84, 0.71, 1.0, 0.87)
		if jump:
			for k in range(0, pts.size() - 1, 2): top.draw_line(pts[k], pts[k + 1], core, 3, true)
		else:
			top.draw_polyline(pts, core, 3, true)

func _draw_hero(h: Dictionary) -> void:
	var S = Game.state
	var r := tile_rect(h.pos.c, h.pos.x, h.pos.y)
	var ctr := r.get_center()
	var R := maxf(8, minf(r.size.x * 0.42, cam.z * 0.22))
	var col := Color(S.players[h.owner].color)
	if h.id == sel_hero and h.owner == S.cur:
		top.draw_arc(ctr, R * 1.15 + sin(Time.get_ticks_msec() / 250.0) * 1.5, 0, TAU, 32, Color("#f0d68e"), 2, true)
	top.draw_rect(Rect2(ctr.x - R * 0.55 - 1, ctr.y - R, 3, R * 1.9), Color.BLACK)
	var flag := PackedVector2Array([Vector2(ctr.x - R * 0.5, ctr.y - R), Vector2(ctr.x + R * 0.8, ctr.y - R * 0.6), Vector2(ctr.x - R * 0.5, ctr.y - R * 0.1)])
	top.draw_colored_polygon(flag, col)
	flag.append(flag[0])
	top.draw_polyline(flag, Color.BLACK, 1.5, true)
	_text_c(top, UI.font, Vector2(ctr.x + R * 0.05, ctr.y + R * 0.45), "♛", int(R * 0.7), Color.WHITE, 2, Color(0, 0, 0, 0.6))

# ------------------------------------------------------------------ input
func pick(pos: Vector2):
	var S = Game.state
	var z: float = cam.z
	var px: float = pos.x + cam.x
	var py: float = pos.y + cam.y
	var cx := int(floor(px / z))
	var cy := int(floor(py / z))
	if cx < 0 or cy < 0 or cx >= S.map.W or cy >= S.map.H: return null
	var c: int = cy * S.map.W + cx
	var s: int = S.map.cards[c].size
	return {"c": c, "x": mini(s - 1, int(floor((px / z - cx) * s))), "y": mini(s - 1, int(floor((py / z - cy) * s)))}

func _map_input(e: InputEvent) -> void:
	if Game.state == null: return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom(1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom(1 / 1.15, e.position)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if e.pressed:
				_down = {"pos": e.position, "cx": cam.x, "cy": cam.y, "moved": false, "btn": e.button_index}
			elif _down != null:
				if not _down.moved: on_click(e.position, _down.btn)
				_down = null
	elif e is InputEventMouseMotion:
		if _down != null:
			var d: Vector2 = e.position - _down.pos
			if absf(d.x) + absf(d.y) > 5: _down.moved = true
			if _down.moved:
				cam.x = _down.cx - d.x
				cam.y = _down.cy - d.y
		on_hover(e.position)

func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or Game.state == null or UI.modal_open() or not (e is InputEventKey) or not e.pressed: return
	var step := 60.0
	var handled := true
	match e.keycode:
		KEY_LEFT, KEY_A: cam.x -= step
		KEY_RIGHT, KEY_D: cam.x += step
		KEY_UP, KEY_W: cam.y -= step
		KEY_DOWN, KEY_S: cam.y += step
		KEY_H: next_hero()
		KEY_SPACE:
			if path != null: go()
		KEY_ESCAPE:
			path = null
		KEY_N:
			if hover != null: rename_card(hover.c)
		KEY_E:
			Game.end_turn_confirm()
		_: handled = false
	if handled: get_viewport().set_input_as_handled()

func on_hover(pos: Vector2) -> void:
	var n = pick(pos)
	hover = n
	if n == null:
		hover_panel.visible = false
		return
	var S = Game.state
	var P: Dictionary = S.players[S.cur]
	var txt := ""
	if not World.tile_seen(P, n.c, n.x, n.y):
		txt = UI.col("Unexplored", "muted")
	else:
		var card: Dictionary = S.map.cards[n.c]
		var TT: Dictionary = D.TERRAIN[card.t]
		if card.get("name", "") != "": txt += UI.b(UI.col(U.esc(card.name), "gold2")) + " · "
		txt += "%s %s" % [UI.b(TT.name), UI.col("%d×%d · seen from %d tiles · your sight %s%d when standing here" % [card.size, card.size, World.sight_range(card.t, 0, 0), "+" if TT.sight >= 0 else "", U.jr(TT.sight * D.CFG.sightScale)], "muted")]
		txt += "\n" + UI.col("Battle: " + TT.desc, "warm")
		txt += "\n" + UI.col("Right-click or press N to %s this card." % ("rename" if card.get("name", "") != "" else "name"), "muted")
		if card.road[0] or card.road[1] or card.road[2] or card.road[3]:
			txt += "\n" + UI.col("Road" if World.is_road(n.c, n.x, n.y) else "Off-road (supply train cannot go here)", "muted")
		if P.trans.cards.has(n.c):
			txt += "\n" + UI.col("✧ One of your transcendent cards: entering it opens a jump to a far part of the map.", "#d8b8ff")
		var o = World.obj_at(n.c, n.x, n.y)
		if o != null and (not o.get("hidden", false) or World.sub_seen(P, n.c, n.x, n.y)):
			txt += "\n" + UI.col("────────", "dim") + "\n" + obj_info(o)
		var hh = World.hero_at(n.c, n.x, n.y)
		if hh != null and (hh.owner == S.cur or World.tile_vis(S.cur, n.c, n.x, n.y)):
			txt += "\n" + UI.col("────────", "dim") + "\n[b][color=%s]♛ %s[/color][/b] (%s)\n%s" % [S.players[hh.owner].color, U.esc(hh.name), U.esc(S.players[hh.owner].name), army_text(hh.army, hh.owner == S.cur)]
	if path != null and path.size():
		txt += "\n" + UI.col("────────", "dim") + "\nPath: %d steps (movement left: %d). Click again or press Space to go." % [path.size(), World.hero(sel_hero).mp]
	hover_rtl.text = txt
	hover_panel.visible = true
	hover_panel.reset_size()

func count_word(n: int) -> String:
	if n < 5: return "Few"
	if n < 10: return "Several"
	if n < 20: return "Pack"
	if n < 50: return "Lots"
	if n < 100: return "Horde"
	return "Throng"

func army_text(groups: Array, exact: bool) -> String:
	var out := []
	for g in groups:
		var d := Units.resolve(g.key)
		out.append("%s %s%s" % [str(g.count) if exact else count_word(g.count), U.esc(g.name if g.get("name", "") != "" else d.name), (" ×%d stacks" % g.splits) if g.splits > 1 else ""])
	return "\n".join(out)

func obj_info(o: Dictionary) -> String:
	var S = Game.state
	var def: Dictionary = D.OBJ[o.type]
	var title: String = D.MINES[o.kind].name if o.type == "mine" else (S.towns[o.town].name if o.type == "town" else def.name)
	var s := "[b]%s %s[/b]\n%s" % [def.glyph, U.esc(title), UI.col(def.desc, "muted")]
	if o.type == "town":
		var t: Dictionary = S.towns[o.town]
		s += "\n%s town · %s" % [D.FACTIONS[t.faction].name, ("owned by " + S.players[t.owner].name) if t.owner >= 0 else "neutral"]
		if t.garrison.size() and t.owner != S.cur: s += "\nGarrison: " + army_text(t.garrison, false)
	if o.type == "mine":
		var M: Dictionary = D.MINES[o.kind]
		s += "\n+%d gold/day · claim cost %d · %s" % [M.income, M.cost, ("owned by " + S.players[o.owner].name) if o.owner >= 0 else "unclaimed"]
	if o.type == "monster": s += "\n" + monster_text(o.army)
	if o.has("guard"): s += "\n" + UI.col("Guarded:", "bad") + " " + monster_text(o.guard)
	if o.type == "shrine": s += "\nSpell: " + D.SPELLS[o.spell].name
	if o.type == "artifact" and not o.has("guard"): s += "\n" + D.ARTIFACTS[o.art].name
	if o.type == "hermit": s += "\n+%d %s experience" % [o.amount, o.stat]
	if o.has("join"): s += "\n%d × %s%s" % [o.join.count, Units.resolve(o.join.key).name, (" for %d gold" % o.price) if o.has("price") else ""]
	return s

func monster_text(a: Dictionary) -> String:
	var val := 0.0
	var parts := []
	for s in a.stacks:
		val += s.count * Units.value(Units.resolve(s.key))
		parts.append("%s %s" % [count_word(s.count), Units.resolve(s.key).name])
	return ", ".join(parts) + " " + UI.col("(level %d, value ≈%s)" % [a.level, U.fmt(val)], "muted")

func on_click(pos: Vector2, btn: int) -> void:
	if anim: return
	var n = pick(pos)
	if n == null: return
	var S = Game.state
	if btn == MOUSE_BUTTON_RIGHT:
		if path != null:
			path = null
		else:
			rename_card(n.c)
		return
	if btn != MOUSE_BUTTON_LEFT: return
	var hh = World.hero_at(n.c, n.x, n.y)
	if hh != null and hh.owner == S.cur and hh.id != sel_hero:
		sel_hero = hh.id
		path = null
		render_side()
		return
	var o = World.obj_at(n.c, n.x, n.y)
	var hero = World.hero(sel_hero) if sel_hero != "" else null
	if hero == null:
		if o != null and o.type == "town" and S.towns[o.town].owner == S.cur: UI.screen("town").open(o.town, "")
		return
	if hh != null and hh.id == hero.id:
		if o != null and o.type == "town" and S.towns[o.town].owner == S.cur: UI.screen("town").open(o.town, hero.id)
		return
	if path != null and path.size():
		var last: Dictionary = path[path.size() - 1]
		if last.c == n.c and last.x == n.x and last.y == n.y:
			go()
			return
	var p = World.path(hero, n)
	if p == null:
		var why = World.enterable(hero, n, S.players[S.cur])
		UI.toast(why if (why != null and why != "stop") else "No route")
		path = null
		return
	path = p
	on_hover(pos)

func rename_card(c: int) -> void:
	var S = Game.state
	var P: Dictionary = S.players[S.cur]
	var card: Dictionary = S.map.cards[c]
	if not P.seen[c]:
		UI.toast("You can only name land you have seen")
		return
	var v = await UI.prompt("Name this %s (leave empty to clear)" % D.TERRAIN[card.t].name.to_lower(), card.get("name", ""))
	if v == null: return
	if v == "": card.erase("name")
	else: card.name = v.substr(0, 32)

func go() -> void:
	var hero = World.hero(sel_hero) if sel_hero != "" else null
	if hero == null or path == null: return
	Game.walk(hero, path)

func next_hero() -> void:
	var hs := World.heroes_of(Game.state.cur)
	if hs.is_empty(): return
	var i := -1
	for k in hs.size():
		if hs[k].id == sel_hero: i = k
	sel_hero = hs[(i + 1) % hs.size()].id
	path = null
	center_on_sel()
	render_side()

# ------------------------------------------------------------------ side panel
func _sec(kids: Array, expand: bool = false) -> Control:
	var v := UI.vbox(kids, 6)
	var p := UI.panel(v, UI.sb(UI.C.bg2, Color(0, 0, 0, 0), 0, 0, 12, 10))
	if expand: p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p

func render_side() -> void:
	if side == null or Game.state == null: return
	UI.clear(side)
	var S = Game.state
	var P: Dictionary = S.players[S.cur]
	var week: int = (S.day - 1) / 7 + 1
	var dow: int = (S.day - 1) % 7 + 1
	var gold := UI.rich("● [b][color=#f0d68e]%s[/color][/b]  %s%s" % [U.fmt(P.gold), UI.col("+%d/day" % World.income(S.cur), "muted"), ("  " + UI.col("+%d/wk" % P.invest, "muted")) if P.invest else ""], 13)
	UI.tip(gold, "Gold, income per day, and treasury pay per week")
	var ess := UI.rich("  ".join([1, 2, 3, 4].map(func(t): return "⬡%d [b][color=#f0d68e]%s[/color][/b]" % [t, P.essence[str(t)]])), 13)
	UI.tip(ess, "Upgrade essence by tier (from killing creatures of that tier)")
	side.add_child(_sec([UI.hbox([UI.h2(P.name, Color(P.color)), UI.spacer(), UI.chip("Day %d · Week %d" % [dow, week])]), gold, ess]))
	side.add_child(UI.sep_line())
	# heroes
	var hs := World.heroes_of(S.cur)
	var hsec := [UI.h3("Heroes")]
	for hr in hs:
		var tab := _tab([UI.label("♛"), _bold(hr.name), UI.label(D.CLASSES[hr.cls].name, "muted"), UI.spacer(), UI.chip("%d/%d" % [hr.mp, World.mp_max(hr)], "", "Movement left today"),
			UI.chip("★", "gold", "Skill choice waiting") if hr.pendingSkillChoice != null else null], hr.id == sel_hero, func():
				sel_hero = hr.id
				path = null
				center_on_sel()
				render_side())
		tab.get_child(0).get_child(0).add_theme_color_override("font_color", Color(P.color))
		hsec.append(tab)
	if hs.is_empty(): hsec.append(UI.label("No heroes. Hire one in a town tavern.", "muted"))
	side.add_child(_sec(hsec))
	side.add_child(UI.sep_line())
	var hero = World.hero(sel_hero) if sel_hero != "" else null
	if hero != null:
		var train_txt: String
		if hero.train == null or hero.train.state == "none": train_txt = "no supply train"
		elif hero.train.state == "with":
			var wn := 0
			for w in hero.train.wounded: wn += w.count
			train_txt = "supply train with army" + (" (%d wounded)" % wn if wn else "")
		else: train_txt = "supply train parked"
		var mini_army := UI.flow([], 4)
		for g in hero.army:
			var d := Units.resolve(g.key)
			var am := UI.panel(UI.hbox([UI.sym(d, 18), UI.label(str(g.count) + ("÷%d" % g.splits if g.splits > 1 else ""), "", 12)], 3), UI.sb(UI.C.panel, UI.C.line, 6, 1, 5, 2))
			UI.tip(am, UI.unit_tip(d))
			mini_army.add_child(am)
		var stat_line := "A%d D%d C%d I%s P%d K%d" % [Heroes.stat(hero, "attack"), Heroes.stat(hero, "defence"), Heroes.stat(hero, "courage"), Heroes.init_str(Heroes.stat(hero, "initiative")), Heroes.stat(hero, "power"), Heroes.stat(hero, "knowledge")]
		var tl := UI.label("⚒ " + train_txt + (" (Logistics: not needed)" if Heroes.skill(hero, "logistics") else ""), "muted", 12)
		for f in D.FLAGS:
			if f.id == "trainrules": UI.tip(tl, f.text)
		var btns := UI.flow([UI.button("Hero" + (" ★" if hero.pendingSkillChoice != null else ""), func(): ArmyUI.hero_screen(hero.id), "Small"),
			UI.button("Army", func(): ArmyUI.army_screen(hero.id, "", Callable()), "Small")], 4)
		if hero.train != null and hero.train.state == "with":
			btns.add_child(UI.button("Park train", func(): Game.park_train(hero), "Small"))
		var o = World.obj_at(hero.pos.c, hero.pos.x, hero.pos.y)
		if o != null and o.type == "town" and S.towns[o.town].owner == S.cur:
			btns.add_child(UI.button("Town", func(): UI.screen("town").open(o.town, hero.id), "Small"))
		if o != null and o.type in ["post", "font", "mine", "mercs"]:
			btns.add_child(UI.button("Use " + D.OBJ[o.type].name, func(): Game.use_site(hero, o), "Small"))
		btns.add_child(UI.button("◎", center_on_sel, "Small", "Centre on hero"))
		side.add_child(_sec([UI.hbox([_bold(hero.name, "gold2"), UI.spacer(), UI.label(stat_line, "muted", 12)]), mini_army, tl, btns]))
		side.add_child(UI.sep_line())
	var ts := World.towns_of(S.cur)
	var tsec := [UI.h3("Towns")]
	for t in ts:
		tsec.append(_tab([UI.label("♛" if t.capital else "♜"), _bold(t.name), UI.label(D.FACTIONS[t.faction].name, "muted")], false, func():
			center_on(t.c, t.x, t.y)
			var hh = World.hero_at(t.c, t.x, t.y)
			UI.screen("town").open(t.id, hh.id if (hh != null and hh.owner == S.cur) else "")))
	side.add_child(_sec(tsec))
	side.add_child(UI.sep_line())
	var logr := UI.rich("", 12, false)
	logr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lines := []
	var L: Array = S.log.slice(maxi(0, S.log.size() - 40))
	L.reverse()
	for l in L:
		var t := "D%d: %s" % [l.day, U.esc(l.t)]
		lines.append(t if l.p == S.cur else UI.col(t, "muted"))
	logr.text = "\n".join(lines)
	side.add_child(_sec([logr], true))
	var et := UI.button("End turn ▸", Game.end_turn_confirm, "BigPrimary", "End your turn [E]")
	side.add_child(_sec([et]))

func _bold(t: String, cls: String = "") -> Label:
	var l := UI.label(t, cls)
	l.add_theme_font_override("font", UI.font_bold)
	return l

func _tab(kids: Array, selected: bool, cb: Callable) -> Control:
	var p := UI.panel(UI.hbox(kids, 6), UI.sb(Color(0.23, 0.19, 0.125, 0.53) if selected else UI.C.panel, UI.C.gold if selected else UI.C.line, 6, 1, 7, 5))
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: cb.call())
	for k in p.get_child(0).get_children():
		if k is Control: k.mouse_filter = Control.MOUSE_FILTER_PASS
	return p

const HELP := """[font_size=18][color=#f0d68e][b]Overworld[/b][/color][/font_size]

[b]Cards.[/b] The map is 20×20 cards. Each card is a small NxN world of its own (prairie 1×1 … swamp 4×4): every square inside is explorable, and walking across a big card takes more steps. Hover a card for its battle effect.

[b]Moving.[/b] Select a hero, click a destination to see the path (green = reachable today), click again or press Space to go. Right-click / Esc cancels a path. With no path shown, right-click a card (or hover it and press N) to name it. H cycles heroes; drag or WASD / arrow keys to pan; wheel zooms; E ends the turn.

[b]Supply train.[/b] While your train is with you, you may only walk on roads. Park it to go off-road (your troops get −1 morale and suffer attrition until you return to it). Wounded ride in the train and rejoin in town.

[b]Sight.[/b] Sight is counted in tiles and cards are uncovered tile by tile: you see a tile if it is within the card's visibility of your hero, counting every square in between, so a 4×4 swamp in the way blocks more than a 1×1 prairie. Most cards are seen from 3 tiles, hills from 5, mountains from 9. Starry tiles are unexplored; dim tiles are remembered but not currently in view. Standing on high ground helps, forests and swamps hurt. Mountains hide the cards just behind them. Small hidden things inside a card are only found by walking near them.

[b]Transcendent cards (✧).[/b] Each player has secret cards. Entering one lifts a distant part of the map beside you: the next edge you cross takes you there, and a glowing line records your route. Walk back along the line to return; step off it and you are in that far place for real. Your opponent just sees you vanish and reappear.

[b]Battles.[/b] The defender chooses the ground (its card or any of the 8 around it) or ignores the attack; the attacker then chooses the time of day, or feints.

[b]Winning.[/b] Capture the enemy capital (♛)."""

func help() -> void:
	UI.modal(UI.rich(HELP), false, 640)
