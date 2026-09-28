# ============================================================================
# Main — boot, main menu, design flags screen.
# ============================================================================
extends Node

const VERSION := "0.2 (Godot)"

func boot() -> void:
	UI.add_screen("menu", Control.new())
	UI.add_screen("sandbox", preload("res://scripts/ui/sandbox_screen.gd").new())
	UI.add_screen("battle", preload("res://scripts/ui/battle_screen.gd").new())
	UI.add_screen("world", preload("res://scripts/ui/world_screen.gd").new())
	UI.add_screen("town", preload("res://scripts/ui/town_screen.gd").new())
	UI.add_screen("handoff", Control.new())
	menu()

func menu() -> void:
	var el: Control = UI.screen("menu")
	UI.clear(el)
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.0))
	gr.set_color(1, Color(0, 0, 0, 0.75))
	gt.gradient = gr
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	el.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	el.add_child(cc)
	var outer := UI.vbox([], 14)
	cc.add_child(outer)
	var box := UI.vbox([], 10)
	box.custom_minimum_size.x = 400
	var sig := UI.label("α β γ δ", "gold", 64)
	sig.add_theme_font_override("font", UI.font_head)
	sig.add_theme_color_override("font_outline_color", Color("#140e08"))
	sig.add_theme_constant_override("outline_size", 8)
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sig)
	var t := UI.h1("Heroes of Four Seasons")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var v := UI.label("An abstract prototype · v" + VERSION, "gold")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	for c in box.get_children():
		box.remove_child(c)
		outer.add_child(c)
	outer.add_child(UI.panel(box, UI.stone("frame").margins(30, 26)))
	var has_game: bool = Game.state != null
	if has_game:
		box.add_child(UI.button("Continue game", Game.resume, "BigPrimary"))
	if Game.has_method("new_game_dialog"):
		box.add_child(UI.button("New hotseat game", Game.new_game_dialog, "Big" if has_game else "BigPrimary"))
		box.add_child(UI.button("Load game", Game.load_dialog, "Big"))
	box.add_child(UI.button("Combat sandbox", func(): UI.screen("sandbox").open(), "Big"))
	box.add_child(UI.button("Design flags (%d)" % D.FLAGS.size(), flags, "Big"))
	box.add_child(UI.button("Combat rules", func(): UI.screen("battle").show_rules(), "Big"))
	box.add_child(UI.button("Quit", func(): get_tree().quit(), "Big"))
	var mc := UI.hbox([UI.spacer(), UI.label("Music", "muted"), Music.control(), UI.spacer()])
	box.add_child(mc)
	UI.show("menu")

func flags() -> void:
	var areas := []
	for f in D.FLAGS:
		if not areas.has(f.area): areas.append(f.area)
	var box := UI.vbox([UI.h2("Design flags"), UI.rich(UI.col("Everything below was assumed, invented or interpreted because the design doc left it open. Items marked ⚑ in-game are placeholders to revisit.", "muted"))], 6)
	for a in areas:
		box.add_child(UI.h3(a))
		for f in D.FLAGS:
			if f.area == a:
				var r := UI.rich(U.esc(f.text), 13)
				var st := UI.stone("plate").margins(10, 6)
				st.accent_w = 3
				st.trim = Color("#ff9f43", 0.6)
				box.add_child(UI.panel(r, st))
	box.add_child(UI.row_end([UI.button("Close", UI.close_modal, "Primary")]))
	UI.modal(box, false, 720)
