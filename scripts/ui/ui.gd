# ============================================================================
# UI — theme, screens, tooltips (BBCode), modal dialogs (awaitable), toasts,
# small widget builders and the shared unit tooltip text.
# ============================================================================
extends Node

const C := {
	"bg": Color("#1a1714"), "bg2": Color("#231f1a"), "panel": Color("#2d2821"), "panel2": Color("#3b342b"),
	"line": Color("#4d4336"), "line2": Color("#6b5d49"), "text": Color("#eadcb8"), "muted": Color("#a89878"), "dim": Color("#75694f"),
	"gold": Color("#d4a94a"), "gold2": Color("#f3d98e"), "stone": Color("#6a5f50"), "bronze": Color("#8a6a2e"), "danger": Color("#d65a4a"), "good": Color("#6cc07a"), "info": Color("#6aa5dc"),
	"morale": Color("#e2a33e"), "health": Color("#cf4a3f"), "engage": Color("#e0604a"), "guard": Color("#5aa0e0"), "adv": Color("#7fd6c4"), "spell": Color("#b58cf0"),
}
const HEX := {
	"muted": "#a89878", "dim": "#75694f", "gold": "#d4a94a", "gold2": "#f3d98e", "bad": "#d65a4a", "good": "#6cc07a",
	"spell": "#b58cf0", "adv": "#7fd6c4", "engage": "#e0604a", "guard": "#5aa0e0", "warm": "#d9d0b0", "flag": "#ff9f43",
}

var theme: Theme
var font: Font
var font_bold: Font
var font_mono: Font
var font_head: Font      # chunky serif for titles and buttons
var grain: Texture2D
var root: Control
var screens: Control
var overlay: CanvasLayer
var _modal_bg: ColorRect
var _modal_center: CenterContainer
var _modal_panel: PanelContainer
var _modal_scroll: ScrollContainer
var _modal_content: Control = null
var _modal_locked := false
var _modal_minw := 320.0
var _tip_panel: PanelContainer
var _tip_rtl: RichTextLabel
var _tip_src = null
var _tip_text := ""
var _toast: PanelContainer
var _toast_lbl: Label
var _toast_t := 0.0
var cur_screen := ""
var autopilot := false   # tests: dialogs answer themselves (OK / first option)


# ------------------------------------------------------------------ setup
func setup(main: Control) -> void:
	root = main
	var sans := _load_font("res://fonts/DejaVuSans.ttf")
	var sans_b := _load_font("res://fonts/DejaVuSans-Bold.ttf")
	font = _load_font("res://fonts/DejaVuSerifCondensed.ttf", [sans])
	font_bold = _load_font("res://fonts/DejaVuSerifCondensed-Bold.ttf", [sans_b])
	font_head = _load_font("res://fonts/DejaVuSerif-Bold.ttf", [sans_b])
	font_mono = _load_font("res://fonts/DejaVuSansMono.ttf", [sans])
	grain = RetroTex.grain()
	theme = _make_theme()
	main.theme = theme
	var bg := TextureRect.new()
	bg.texture = RetroTex.wall()
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(bg)
	screens = Control.new()
	screens.name = "Screens"
	screens.set_anchors_preset(Control.PRESET_FULL_RECT)
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(screens)
	overlay = CanvasLayer.new()
	overlay.layer = 10
	main.add_child(overlay)
	var ov := Control.new()
	ov.theme = theme
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ov)
	# modal
	_modal_bg = ColorRect.new()
	_modal_bg.color = Color(0, 0, 0, 0.55)
	_modal_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_bg.visible = false
	_modal_bg.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not _modal_locked:
			close_modal())
	ov.add_child(_modal_bg)
	_modal_center = CenterContainer.new()
	_modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_center.visible = false
	ov.add_child(_modal_center)
	_modal_panel = PanelContainer.new()
	_modal_panel.add_theme_stylebox_override("panel", stone("frame"))
	_modal_center.add_child(_modal_panel)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_panel.add_child(_modal_scroll)
	# toast
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", stone("tip").margins(14, 8))
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_color_override("font_color", C.gold2)
	_toast.add_child(_toast_lbl)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(_toast)
	# tooltip
	_tip_panel = PanelContainer.new()
	_tip_panel.add_theme_stylebox_override("panel", stone("tip"))
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_rtl = rich("", 12)
	_tip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_rtl)
	_tip_panel.visible = false
	_tip_panel.top_level = true
	ov.add_child(_tip_panel)

func _load_font(p: String, fallbacks: Array = []) -> Font:
	var f = load(p)
	if f is FontFile:
		(f as FontFile).allow_system_fallback = true
		if fallbacks.size():
			(f as FontFile).fallbacks = fallbacks
	return f

## generic box: square corners, stone grain, a small bevel (radius is ignored — 90s look)
func sb(bg: Color, border: Color = Color(0, 0, 0, 0), _radius: int = 0, bw: int = 1, margin: float = 8.0, margin_v: float = -1.0) -> StoneBox:
	var s := StoneBox.new()
	s.fill = bg
	var solid := bg.a > 0.3
	s.outline = border if border.a > 0 else (Color(0, 0, 0, 0.85) if solid else Color(0, 0, 0, 0))
	s.outline_w = maxi(bw, 1) if s.outline.a > 0 else 0
	s.bevel = 2 if solid else 0
	s.tex = grain if solid else null
	s.tex_alpha = 0.55
	return s.margins(margin, margin_v)

## named stone styles
func stone(kind: String) -> StoneBox:
	var s := StoneBox.new()
	s.tex = grain
	match kind:
		"button":
			s.fill = C.stone; s.bevel = 3; s.tex_alpha = 0.9
		"panel":
			s.fill = Color("#2b261f"); s.bevel = 2; s.trim = Color("#5c4a2a"); s.outline = Color("#0d0b08"); s.tex_alpha = 0.5
			s.margins(12)
		"frame":
			s.fill = Color("#2f2922"); s.bevel = 4; s.trim = Color("#c9a24a"); s.studs = true; s.outline = Color.BLACK; s.outline_w = 2; s.tex_alpha = 0.8
			s.margins(24, 20)
		"tip":
			s.fill = Color(0.1, 0.09, 0.07, 0.97); s.bevel = 2; s.trim = Color("#8a6a2e"); s.outline = Color.BLACK; s.tex_alpha = 0.4
			s.margins(10, 8)
		"inset":
			s.fill = Color("#16130f"); s.bevel = 2; s.raised = false; s.outline = Color(0, 0, 0, 0.9); s.tex_alpha = 0.35
			s.margins(7, 4)
		"plate":
			s.fill = Color("#3b342b"); s.bevel = 1; s.tex_alpha = 0.5
			s.margins(9, 4)
		"bar":
			s.fill = Color("#231f1a"); s.bevel = 2; s.trim = Color("#5c4a2a"); s.outline = Color("#0d0b08"); s.tex_alpha = 0.7
			s.margins(14, 8)
	return s

func _check_icon(on: bool, hover: bool = false) -> ImageTexture:
	var S := 18
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in S:
		for x in S:
			var c := Color("#16130f")
			if x == 0 or y == 0 or x == S - 1 or y == S - 1: c = Color.BLACK
			elif x == 1 or y == 1: c = Color(0, 0, 0, 1).lerp(Color("#16130f"), 0.3)
			elif x == S - 2 or y == S - 2: c = Color("#5c4a2a") if not hover else Color("#c9a24a")
			img.set_pixel(x, y, c)
	if on:
		var gold := Color("#f3d98e")
		for i in 12:
			var t := i / 11.0
			var px: float
			var py: float
			if t < 0.4:
				px = 4 + t / 0.4 * 3; py = 9 + t / 0.4 * 3
			else:
				px = 7 + (t - 0.4) / 0.6 * 7; py = 12 - (t - 0.4) / 0.6 * 8
			for d in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				img.set_pixel(clampi(int(px + d.x), 2, S - 3), clampi(int(py + d.y), 2, S - 3), gold)
	return ImageTexture.create_from_image(img)

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 14
	# buttons: chunky carved stone slabs
	var kinds := {
		"": [C.stone, Color(0, 0, 0, 0), C.text],
		"Primary": [Color("#7d5f2a"), Color("#e2bd62"), C.gold2],
		"Danger": [Color("#6e3a2e"), Color(0, 0, 0, 0), Color("#f6c2b4")],
		"Sel": [Color("#8a6a2e"), Color("#f3d98e"), Color("#fff0c0")],
	}
	for size in ["", "Small", "Big"]:
		for k in kinds:
			var name: String = size + k
			var tn := "Button" if name == "" else name
			if name != "":
				t.set_type_variation(tn, "Button")
			var col: Array = kinds[k]
			var mh := 14.0; var mv := 6.0; var fs := 14; var bv := 3
			if size == "Small": mh = 9.0; mv = 3.0; fs = 12; bv = 2
			if size == "Big": mh = 16.0; mv = 11.0; fs = 17; bv = 4
			var n := stone("button")
			n.fill = col[0]; n.bevel = bv; n.trim = col[1]
			n.margins(mh, mv)
			var hv := n.copy()
			hv.fill = col[0].lightened(0.12); hv.trim = Color("#f3d98e", 0.85)
			var pr := n.copy()
			pr.fill = col[0].darkened(0.15); pr.raised = false; pr.trim = Color("#f3d98e", 0.6)
			pr.content_margin_top = mv + 1; pr.content_margin_bottom = mv - 1; pr.content_margin_left = mh + 1; pr.content_margin_right = mh - 1
			var ds := n.copy()
			ds.fill = col[0].darkened(0.5); ds.light = Color(1, 1, 1, 0.08); ds.trim = Color(0, 0, 0, 0); ds.tex_alpha = 0.3
			t.set_stylebox("normal", tn, n)
			t.set_stylebox("hover", tn, hv)
			t.set_stylebox("pressed", tn, pr)
			t.set_stylebox("hover_pressed", tn, pr)
			t.set_stylebox("disabled", tn, ds)
			t.set_stylebox("focus", tn, StyleBoxEmpty.new())
			t.set_font("font", tn, font_head if size != "Small" else font_bold)
			t.set_color("font_color", tn, col[2])
			t.set_color("font_hover_color", tn, col[2].lightened(0.15))
			t.set_color("font_pressed_color", tn, col[2])
			t.set_color("font_hover_pressed_color", tn, col[2])
			t.set_color("font_focus_color", tn, col[2])
			t.set_color("font_disabled_color", tn, Color("#8a8070"))
			t.set_color("font_outline_color", tn, Color("#140e08"))
			t.set_constant("outline_size", tn, 3 if size != "Small" else 2)
			t.set_font_size("font_size", tn, fs)
	var inp := stone("inset")
	var inp_f := inp.copy()
	inp_f.trim = Color("#c9a24a")
	for tn in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", tn, inp)
		t.set_stylebox("focus", tn, inp_f)
		t.set_stylebox("read_only", tn, inp)
		t.set_color("font_color", tn, C.text)
		t.set_color("caret_color", tn, C.gold2)
		t.set_color("selection_color", tn, Color("#8a6a2e", 0.6))
	var ob := stone("button")
	ob.bevel = 2; ob.fill = Color("#4a4238"); ob.margins(8, 3)
	var obh := ob.copy()
	obh.fill = ob.fill.lightened(0.1); obh.trim = Color("#f3d98e", 0.7)
	var obp := ob.copy()
	obp.raised = false; obp.fill = ob.fill.darkened(0.15)
	t.set_stylebox("normal", "OptionButton", ob)
	t.set_stylebox("hover", "OptionButton", obh)
	t.set_stylebox("pressed", "OptionButton", obp)
	t.set_stylebox("disabled", "OptionButton", ob)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", C.text)
	t.set_color("font_hover_color", "OptionButton", C.gold2)
	var pm := stone("tip")
	pm.margins(4)
	t.set_stylebox("panel", "PopupMenu", pm)
	var pmh := StoneBox.new()
	pmh.fill = Color("#7d5f2a"); pmh.bevel = 1; pmh.outline = Color(0, 0, 0, 0); pmh.tex = grain; pmh.tex_alpha = 0.5
	t.set_stylebox("hover", "PopupMenu", pmh)
	t.set_color("font_color", "PopupMenu", C.text)
	t.set_color("font_hover_color", "PopupMenu", Color("#fff0c0"))
	t.set_color("font_color", "Label", C.text)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	for tn in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", tn, C.text)
		t.set_color("font_hover_color", tn, C.gold2)
		t.set_color("font_pressed_color", tn, C.text)
		t.set_color("font_hover_pressed_color", tn, C.gold2)
		t.set_color("font_focus_color", tn, C.text)
		t.set_stylebox("focus", tn, StyleBoxEmpty.new())
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, tn, StyleBoxEmpty.new())
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	t.set_color("default_color", "RichTextLabel", C.text)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("mono_font", "RichTextLabel", font_mono)
	t.set_constant("table_h_separation", "RichTextLabel", 10)
	t.set_stylebox("panel", "PanelContainer", stone("panel"))
	t.set_stylebox("panel", "TooltipPanel", stone("tip"))
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	var trough := stone("inset")
	trough.margins(0)
	var grab := stone("button")
	grab.bevel = 2; grab.fill = Color("#5a5044"); grab.margins(0)
	var grab_h := grab.copy()
	grab_h.fill = Color("#8a6a2e")
	for tn in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", tn, trough)
		t.set_stylebox("scroll_focus", tn, trough)
		t.set_stylebox("grabber", tn, grab)
		t.set_stylebox("grabber_highlight", tn, grab_h)
		t.set_stylebox("grabber_pressed", tn, grab_h)
	var sl := stone("inset")
	sl.margins(0, 3)
	var sla := StoneBox.new()
	sla.fill = Color("#b08a3e"); sla.bevel = 1; sla.outline = Color(0, 0, 0, 0); sla.margins(0, 3)
	t.set_stylebox("slider", "HSlider", sl)
	t.set_stylebox("grabber_area", "HSlider", sla)
	t.set_stylebox("grabber_area_highlight", "HSlider", sla)
	var knob := Image.create(12, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 12:
			var c := Color("#6a5f50")
			if x == 0 or y == 0: c = Color("#b8aa90")
			elif x == 11 or y == 17: c = Color("#1a140e")
			elif x == 10 or y == 16: c = Color("#3a3228")
			knob.set_pixel(x, y, c)
	var knob_t := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", knob_t)
	t.set_icon("grabber_highlight", "HSlider", knob_t)
	return t

# ------------------------------------------------------------------ per-frame: tooltip, toast, modal fitting
func _process(delta: float) -> void:
	if root == null:
		return
	# toast
	if _toast.visible:
		_toast_t -= delta
		if _toast_t <= 0:
			_toast.visible = false
		var vs := root.get_viewport_rect().size
		_toast.reset_size()
		_toast.position = Vector2((vs.x - _toast.size.x) / 2, vs.y - _toast.size.y - 18)
	# modal sizing (content may grow as RichTextLabels settle)
	if _modal_content != null and is_instance_valid(_modal_content):
		var vs := root.get_viewport_rect().size
		var m := _modal_content.get_combined_minimum_size()
		var maxw := minf(820.0, vs.x * 0.94)
		var want := Vector2(minf(maxf(m.x, _modal_minw), maxw), minf(m.y, vs.y * 0.86 - 36))
		if _modal_scroll.custom_minimum_size != want:
			_modal_scroll.custom_minimum_size = want
			_modal_panel.reset_size()
	# tooltip
	_update_tip()

func _update_tip() -> void:
	var c = root.get_viewport().gui_get_hovered_control()
	var src = null
	var node = c
	while node != null and node is Control:
		if node.has_meta("tip"):
			src = node
			break
		node = node.get_parent()
	if src == null:
		_tip_panel.visible = false
		_tip_src = null
		return
	var t = src.get_meta("tip")
	var text: String = t.call() if t is Callable else str(t)
	if text == "":
		_tip_panel.visible = false
		return
	if src != _tip_src or text != _tip_text:
		_tip_src = src
		_tip_text = text
		_tip_rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		_tip_rtl.custom_minimum_size = Vector2.ZERO
		_tip_rtl.text = text
		var w := _tip_rtl.get_content_width()
		_tip_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_rtl.custom_minimum_size = Vector2(minf(w + 6, 360), 0)
		_tip_panel.reset_size()
	_tip_panel.visible = true
	_tip_panel.reset_size()
	var mp := root.get_viewport().get_mouse_position()
	var vs := root.get_viewport_rect().size
	var sz := _tip_panel.size
	var p := mp + Vector2(14, 14)
	if p.x + sz.x > vs.x - 6: p.x = mp.x - sz.x - 10
	if p.y + sz.y > vs.y - 6: p.y = mp.y - sz.y - 10
	_tip_panel.position = p.max(Vector2(2, 2))

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and modal_open() and not _modal_locked:
		close_modal()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ screens
func add_screen(name: String, node: Control) -> void:
	node.name = name
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.visible = false
	screens.add_child(node)

func show(name: String) -> void:
	cur_screen = name
	for s in screens.get_children():
		s.visible = s.name == name
	_tip_panel.visible = false

func screen(name: String) -> Control:
	return screens.get_node_or_null(name)

func on(name: String) -> bool:
	return cur_screen == name

# ------------------------------------------------------------------ modal & dialogs
func modal(content: Control, locked: bool = false, minw: float = 320.0) -> void:
	if _modal_content != null and is_instance_valid(_modal_content):
		_modal_content.queue_free()
	_modal_content = content
	_modal_locked = locked
	_modal_minw = minw
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_scroll.add_child(content)
	_modal_scroll.custom_minimum_size = Vector2(minw, 60)
	_modal_scroll.scroll_vertical = 0
	_modal_bg.visible = true
	_modal_center.visible = true
	_tip_panel.visible = false

func close_modal() -> void:
	if _modal_content != null and is_instance_valid(_modal_content):
		_modal_content.queue_free()
	_modal_content = null
	_modal_bg.visible = false
	_modal_center.visible = false

func modal_open() -> bool:
	return _modal_bg.visible

func alert(title: String, body: String = "") -> void:
	if autopilot:
		print("[alert] ", title, ": ", body.replace("\n", " | "))
		await get_tree().process_frame
		return
	var w := Waiter.new()
	var box := vbox([h2(title)])
	if body != "":
		box.add_child(rich(body))
	box.add_child(row_end([button("OK", func(): close_modal(); w.done.emit(true), "Primary")]))
	modal(box, true, 360)
	await w.done

func confirm(text: String, ok_label: String = "OK") -> bool:
	if autopilot:
		await get_tree().process_frame
		return true
	var w := Waiter.new()
	var box := vbox([rich(text), row_end([
		button("Cancel", func(): close_modal(); w.done.emit(false)),
		button(ok_label, func(): close_modal(); w.done.emit(true), "Primary")])])
	modal(box, true, 360)
	return await w.done

## returns the entered text, or null when cancelled
func prompt(title: String, value: String = ""):
	if autopilot:
		await get_tree().process_frame
		return value
	var w := Waiter.new()
	var le := LineEdit.new()
	le.text = value
	le.custom_minimum_size.x = 320
	le.text_submitted.connect(func(_t): close_modal(); w.done.emit(le.text.strip_edges()))
	var box := vbox([h2(title), le, row_end([
		button("Cancel", func(): close_modal(); w.done.emit(null)),
		button("OK", func(): close_modal(); w.done.emit(le.text.strip_edges()), "Primary")])])
	modal(box, true, 360)
	le.call_deferred("grab_focus")
	le.call_deferred("select_all")
	return await w.done

## options: [{label, desc?, variant?}] → returns index (or -1 for cancel when cancel_label given)
func choose(title: String, text: String, options: Array, cancel_label: String = "", minw: float = 460.0) -> int:
	if autopilot:
		await get_tree().process_frame
		print("[choose] ", title, " -> ", options[0].label)
		return 0
	var w := Waiter.new()
	var box := vbox([h2(title)])
	if text != "":
		box.add_child(rich(text))
	for i in options.size():
		var o: Dictionary = options[i]
		var lbl: String = o.label + ("  —  " + o.desc if o.get("desc", "") != "" else "")
		var b := button(lbl, func(): close_modal(); w.done.emit(i), o.get("variant", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if o.has("tip"): tip(b, o.tip)
		box.add_child(b)
	if cancel_label != "":
		box.add_child(row_end([button(cancel_label, func(): close_modal(); w.done.emit(-1))]))
	modal(box, cancel_label == "", minw)
	return await w.done

## two or more big clickable cards side by side; returns index
func pick_cards(title: String, text: String, cards: Array, minw: float = 480.0) -> int:
	if autopilot:
		await get_tree().process_frame
		return 0
	var w := Waiter.new()
	var box := vbox([h2(title)])
	if text != "":
		box.add_child(rich(text))
	var row := hbox([])
	row.add_theme_constant_override("separation", 12)
	for i in cards.size():
		var b := Button.new()
		b.text = ""
		b.custom_minimum_size = Vector2(200, 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r := rich(cards[i])
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.offset_left = 10; r.offset_top = 8; r.offset_right = -10; r.offset_bottom = -8
		b.add_child(r)
		b.pressed.connect(func(): close_modal(); w.done.emit(i))
		row.add_child(b)
	box.add_child(row)
	modal(box, true, minw)
	return await w.done

func toast(text: String, secs: float = 2.2) -> void:
	_toast_lbl.text = text
	_toast_t = secs
	_toast.visible = true

# ------------------------------------------------------------------ builders
func tip(c: Control, t) -> Control:
	c.set_meta("tip", t)
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c

func label(text: String, cls: String = "", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if cls != "" and HEX.has(cls):
		l.add_theme_color_override("font_color", Color(HEX[cls]))
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l

func h1(text: String, col: Color = C.gold2) -> Label:
	var l := label(text, "", 32)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font_head)
	l.add_theme_color_override("font_outline_color", Color("#140e08"))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l

func h2(text: String, col: Color = C.gold2) -> Label:
	var l := label(text, "", 19)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font_head)
	l.add_theme_color_override("font_outline_color", Color("#140e08"))
	l.add_theme_constant_override("outline_size", 3)
	return l

func h3(text: String) -> Label:
	var l := label(text.to_upper(), "", 13)
	l.add_theme_color_override("font_color", C.gold)
	l.add_theme_font_override("font", font_head)
	return l

func rich(bb: String, size: int = 0, fit: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = not fit
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	if size > 0:
		for k in ["normal_font_size", "bold_font_size", "mono_font_size"]:
			r.add_theme_font_size_override(k, size)
	r.text = bb
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

func button(text: String, cb: Callable, variant: String = "", tp = null) -> Button:
	var b := Button.new()
	b.text = text
	if variant != "":
		b.theme_type_variation = variant
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	if tp != null:
		tip(b, tp)
	return b

func hbox(kids: Array, sep: int = -1) -> HBoxContainer:
	var b := HBoxContainer.new()
	if sep >= 0: b.add_theme_constant_override("separation", sep)
	for k in kids:
		if k != null: b.add_child(k)
	return b

func vbox(kids: Array, sep: int = -1) -> VBoxContainer:
	var b := VBoxContainer.new()
	if sep >= 0: b.add_theme_constant_override("separation", sep)
	for k in kids:
		if k != null: b.add_child(k)
	return b

func flow(kids: Array, sep: int = 6) -> HFlowContainer:
	var b := HFlowContainer.new()
	b.add_theme_constant_override("h_separation", sep)
	b.add_theme_constant_override("v_separation", sep)
	for k in kids:
		if k != null: b.add_child(k)
	return b

func row_end(kids: Array) -> HBoxContainer:
	var b := hbox([spacer()] + kids)
	return b

func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func panel(child: Control, style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	if style != null:
		p.add_theme_stylebox_override("panel", style)
	p.add_child(child)
	return p

func chip(text: String, cls: String = "", tp = null) -> PanelContainer:
	var border: Color = C.line2
	var col: Color = C.text
	if cls == "gold": border = C.gold; col = C.gold2
	if cls == "warn": border = C.danger; col = Color("#f3b1a8")
	var l := label(text, "", 12)
	l.add_theme_color_override("font_color", col)
	var st := stone("plate")
	if cls != "": st.trim = border
	var p := panel(l, st)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tp != null: tip(p, tp)
	return p

func sep_line() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("#5c4a2a")
	line.thickness = 2
	s.add_theme_stylebox_override("separator", line)
	s.add_theme_constant_override("separation", 6)
	return s

func option(items: Array, selected, on_change: Callable) -> OptionButton:
	# items: [[value, label], ...]
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	var sel_i := 0
	for i in items.size():
		o.add_item(str(items[i][1]), i)
		if str(items[i][0]) == str(selected): sel_i = i
	o.select(sel_i)
	o.item_selected.connect(func(i): on_change.call(items[i][0]))
	return o

func spin(v: int, lo: int, hi: int, on_change: Callable, width: float = 80) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = v
	s.rounded = true
	s.custom_minimum_size.x = width
	s.select_all_on_focus = true
	s.value_changed.connect(func(x): on_change.call(int(x)))
	return s

func check(text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c

func sym(d: Dictionary, size: float = 36) -> Control:
	var s := UnitSym.new()
	s.def = d
	s.custom_minimum_size = Vector2(size, size)
	return s

func clear(n: Node) -> Node:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
	return n

# ------------------------------------------------------------------ BBCode helpers
func col(t, c: String) -> String:
	return "[color=%s]%s[/color]" % [HEX.get(c, c), str(t)]

func b(t) -> String:
	return "[b]%s[/b]" % str(t)

func kv(pairs: Array) -> String:
	var s := "[table=2]"
	for p in pairs:
		s += "[cell][color=%s]%s[/color][/cell][cell]%s[/cell]" % [HEX.muted, p[0], p[1]]
	return s + "[/table]"

func unit_tip(d: Dictionary, extra: String = "") -> String:
	var F: Dictionary = D.FACTIONS[d.faction]
	var s := "[b][color=%s]%s[/color][/b] %s" % [F.color, U.esc(d.name), col("%s · tier %d%s" % [F.name, d.tier, " (mounted)" if d.mounted else ""], "muted")]
	if d.placeholder: s += " " + col("⚑", "flag")
	var dm := []
	for x in d.dmg: dm.append(U.fmt(x))
	s += "\n" + kv([["Health", U.fmt(d.hp)], ["Morale", Units.stat_str(d, "mor")], ["Damage", " / ".join(dm)], ["Initiative", str(d.ini)],
		["Attack", Units.stat_str(d, "att")], ["Defence", Units.stat_str(d, "def")], ["Weight/Str", "%s / %s" % [d.w, d.s]]])
	var ab := []
	for k in d.ab:
		if d.ab[k] and D.ABILITY_TEXT.has(k):
			ab.append("• " + ("Slow %s" % d.ab.slow if k == "slow" else k.capitalize()))
	if ab.size(): s += "\n" + "\n".join(ab)
	var sp := []
	for k in d.sp:
		if d.sp[k]:
			var tx := Units.special_text(k, d.sp[k])
			if tx != "": sp.append("◦ " + tx)
	if sp.size(): s += "\n" + col("\n".join(sp), "warm")
	if d.placeholder: s += "\n" + col("⚑ Placeholder \"+1\" second-upgrade stats", "flag")
	return s + extra
