# ============================================================================
# UI — theme, screens, tooltips (BBCode), modal dialogs (awaitable), toasts,
# small widget builders and the shared unit tooltip text.
# ============================================================================
extends Node

const C := {
	"bg": Color("#16181d"), "bg2": Color("#1d2027"), "panel": Color("#242830"), "panel2": Color("#2c313b"),
	"line": Color("#3a404c"), "line2": Color("#4a5160"), "text": Color("#ebe6d9"), "muted": Color("#a39f94"), "dim": Color("#6f6c66"),
	"gold": Color("#d9b45a"), "gold2": Color("#f0d68e"), "danger": Color("#d65a4a"), "good": Color("#6cc07a"), "info": Color("#6aa5dc"),
	"morale": Color("#e2a33e"), "health": Color("#cf4a3f"), "engage": Color("#e0604a"), "guard": Color("#5aa0e0"), "adv": Color("#7fd6c4"), "spell": Color("#b58cf0"),
}
const HEX := {
	"muted": "#a39f94", "dim": "#6f6c66", "gold": "#d9b45a", "gold2": "#f0d68e", "bad": "#d65a4a", "good": "#6cc07a",
	"spell": "#b58cf0", "adv": "#7fd6c4", "engage": "#e0604a", "guard": "#5aa0e0", "warm": "#d9d0b0", "flag": "#ff9f43",
}

var theme: Theme
var font: Font
var font_bold: Font
var font_mono: Font
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
	font = _load_font("res://fonts/DejaVuSans.ttf")
	font_bold = _load_font("res://fonts/DejaVuSans-Bold.ttf")
	font_mono = _load_font("res://fonts/DejaVuSansMono.ttf")
	theme = _make_theme()
	main.theme = theme
	var bg := ColorRect.new()
	bg.color = C.bg
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
	_modal_bg.color = Color(0, 0, 0, 0.62)
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
	_modal_panel.add_theme_stylebox_override("panel", sb(C.panel, C.gold, 10, 1, 18))
	_modal_center.add_child(_modal_panel)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_panel.add_child(_modal_scroll)
	# toast
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", sb(Color(0.055, 0.06, 0.07, 0.93), C.gold, 8, 1, 10))
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_color_override("font_color", C.gold2)
	_toast.add_child(_toast_lbl)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(_toast)
	# tooltip
	_tip_panel = PanelContainer.new()
	_tip_panel.add_theme_stylebox_override("panel", sb(Color(0.055, 0.06, 0.07, 0.95), C.line2, 6, 1, 9))
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_rtl = rich("", 12)
	_tip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_rtl)
	_tip_panel.visible = false
	_tip_panel.top_level = true
	ov.add_child(_tip_panel)

func _load_font(p: String) -> Font:
	var f = load(p)
	if f is FontFile:
		(f as FontFile).allow_system_fallback = true
	return f

func sb(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 6, bw: int = 1, margin: float = 8.0, margin_v: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin; s.content_margin_right = margin
	s.content_margin_top = margin if margin_v < 0 else margin_v
	s.content_margin_bottom = margin if margin_v < 0 else margin_v
	s.anti_aliasing = true
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 14
	var kinds := {"": [C.panel2, C.line2, C.text], "Primary": [Color("#5a4520"), C.gold, C.gold2], "Danger": [C.panel2, C.danger, Color("#f3b1a8")], "Sel": [Color("#4b3c1c"), C.gold, C.gold2]}
	for size in ["", "Small", "Big"]:
		for k in kinds:
			var name: String = size + k
			var tn := "Button" if name == "" else name
			if name != "":
				t.set_type_variation(tn, "Button")
			var col: Array = kinds[k]
			var mh := 12.0; var mv := 6.0; var fs := 14
			if size == "Small": mh = 8.0; mv = 2.0; fs = 12
			if size == "Big": mh = 12.0; mv = 11.0; fs = 16
			var n := sb(col[0], col[1], 6, 1, mh, mv)
			var hv := sb(col[0].lightened(0.12), C.gold, 6, 1, mh, mv)
			var pr := sb(col[0].darkened(0.1), C.gold, 6, 1, mh, mv)
			var ds := sb(Color(col[0], 0.45), Color(col[1], 0.4), 6, 1, mh, mv)
			t.set_stylebox("normal", tn, n)
			t.set_stylebox("hover", tn, hv)
			t.set_stylebox("pressed", tn, pr)
			t.set_stylebox("disabled", tn, ds)
			t.set_stylebox("focus", tn, StyleBoxEmpty.new())
			t.set_color("font_color", tn, col[2])
			t.set_color("font_hover_color", tn, col[2].lightened(0.1))
			t.set_color("font_pressed_color", tn, col[2])
			t.set_color("font_focus_color", tn, col[2])
			t.set_color("font_disabled_color", tn, Color(col[2], 0.4))
			t.set_font_size("font_size", tn, fs)
	var inp := sb(C.bg2, C.line2, 5, 1, 6, 4)
	for tn in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", tn, inp)
		t.set_stylebox("focus", tn, sb(C.bg2, C.gold, 5, 1, 6, 4))
		t.set_color("font_color", tn, C.text)
	t.set_stylebox("normal", "OptionButton", inp)
	t.set_stylebox("hover", "OptionButton", sb(C.bg2, C.gold, 5, 1, 6, 4))
	t.set_stylebox("pressed", "OptionButton", inp)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", C.text)
	t.set_stylebox("panel", "PopupMenu", sb(C.panel2, C.line2, 4, 1, 4))
	t.set_stylebox("hover", "PopupMenu", sb(Color("#4b3c1c"), Color(0, 0, 0, 0), 3, 0, 4))
	t.set_color("font_color", "PopupMenu", C.text)
	t.set_color("font_hover_color", "PopupMenu", C.gold2)
	t.set_color("font_color", "Label", C.text)
	t.set_color("font_color", "CheckBox", C.text)
	t.set_color("font_hover_color", "CheckBox", C.gold2)
	t.set_color("font_pressed_color", "CheckBox", C.text)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", C.text)
	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("mono_font", "RichTextLabel", font_mono)
	t.set_constant("table_h_separation", "RichTextLabel", 10)
	t.set_stylebox("panel", "PanelContainer", sb(C.panel, C.line, 8, 1, 12))
	t.set_stylebox("panel", "TooltipPanel", sb(Color(0.055, 0.06, 0.07, 0.95), C.line2, 6, 1, 8))
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	var sbar := sb(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 4, 0, 0)
	var grab := sb(C.line2, Color(0, 0, 0, 0), 4, 0, 0)
	for tn in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", tn, sbar)
		t.set_stylebox("grabber", tn, grab)
		t.set_stylebox("grabber_highlight", tn, sb(C.gold, Color(0, 0, 0, 0), 4, 0, 0))
		t.set_stylebox("grabber_pressed", tn, sb(C.gold, Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("slider", "HSlider", sb(C.bg2, C.line2, 3, 1, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", sb(C.gold, Color(0, 0, 0, 0), 3, 0, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(C.gold2, Color(0, 0, 0, 0), 3, 0, 0, 2))
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
	var l := label(text, "", 30)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font_bold)
	return l

func h2(text: String, col: Color = C.gold2) -> Label:
	var l := label(text, "", 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font_bold)
	return l

func h3(text: String) -> Label:
	var l := label(text.to_upper(), "", 13)
	l.add_theme_color_override("font_color", C.gold)
	l.add_theme_font_override("font", font_bold)
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
	var p := panel(l, sb(C.bg2, border, 10, 1, 8, 1))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if tp != null: tip(p, tp)
	return p

func sep_line() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_stylebox_override("separator", sb(C.line, Color(0, 0, 0, 0), 0, 0, 0))
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
