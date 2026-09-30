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
	box.add_child(UI.button("Options", options, "Big"))
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

## Options: unit icon style, music and button sounds (saved in the settings file)
func options() -> void:
	var icons := UI.option([["portraits", "Hand-drawn portraits"], ["abstract", "Abstract symbols (original placeholders)"]],
		"portraits" if UnitSym.portraits() else "abstract", func(v):
			UnitSym.set_portraits(v == "portraits")
			get_tree().call_group("unitsym", "queue_redraw")
			var ws = UI.screen("world")
			if ws and ws.has_method("redraw"): ws.redraw())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	grid.add_child(UI.label("Unit icons"))
	grid.add_child(icons)
	grid.add_child(UI.label("Music & sounds"))
	grid.add_child(Music.control())
	grid.add_child(UI.label("Battle"))
	grid.add_child(UI.check("Crowd cheers on critical (maximum) rolls", Sfx.cheers, func(v):
		Sfx.cheers = v
		Sfx.save()
		if v: Sfx.play_cheer()))
	grid.add_child(UI.label("Battle AI"))
	var BS = preload("res://scripts/ui/battle_screen.gd")
	var ai_opt := UI.option(BS.AI_LEVELS, BS.ai_difficulty(), func(v): BS.set_ai_difficulty(v))
	UI.tip(ai_opt, "[b]Normal[/b]: the original combat AI.\n[b]Hard[/b]: on each stack's turn it tries every legal move and plays each one forward (2 samples × 16 actions) before choosing, so it thinks a little longer.\n[color=#d9a441]Hard's look-ahead ignores commanders (their turns, spells and stat bonuses) and walls. Commander turns themselves are played by the Normal AI, and if Hard's move isn't legal on the real board (e.g. behind walls) that turn falls back to Normal.[/color]")
	grid.add_child(ai_opt)
	grid.add_child(UI.label("Casualty rule"))
	var th := UI.check("Test: stack × full value threshold (health and morale)", Battle.full_threshold(), func(v): Battle.set_full_threshold(v))
	UI.tip(th, "[b]Off (doc rule):[/b] a stack starts losing creatures once its damage exceeds count × (health − 1), and likewise count × (morale − 1).\n[b]On (test):[/b] the thresholds are count × health and count × morale, and each deserter sheds a full health of damage. Each creature lost still removes twice its value.\nTakes effect immediately, including mid-battle.")
	grid.add_child(th)
	var box := UI.vbox([UI.h2("Options"), grid, UI.row_end([UI.button("Close", UI.close_modal, "Primary")])], 12)
	UI.modal(box, false, 460)
