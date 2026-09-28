# ============================================================================
# Battle screen: two rows of stack cards (defender on top, attacker below),
# engagement/guard lines, initiative queue, commander cards, actions, log.
# Left-click an action then a target; right-click cancels or shows details.
# ============================================================================
extends Control

var b: Battle = null
var on_end: Callable
var mode = null      # action id while targeting
var sel = null       # selected stack id (details panel)
var spell = null     # {side, id, t1}
var cmd = null       # {side, id, label}
var busy := false
var ended := false
var ai_delay := 0.38

var _top_status: HBoxContainer
var _queue: HBoxContainer
var _rows: Array = []
var _mid: PanelContainer
var _act: VBoxContainer
var _info: VBoxContainer
var _log: RichTextLabel
var _log_n := 0
var _lines: Control
var _field_base: ColorRect
var _field_paint: Control
var _cards := {}   # stack id -> card Control
var _built := false
var _chips: HBoxContainer

const ACTIONS := [
	{"id": "attack", "key": "A", "label": "Attack", "tip": "Hit a target. Must target an assaulter if you are under assault. Attacking something you are NOT engaged with costs your guard, protector status, advantages and engagements (ranged units keep them)."},
	{"id": "engage", "key": "E", "label": "Engage", "tip": "Put an enemy under assault: it must target you (or another assaulter). Lets you attack it even if guarded, and without losing status. Costs your guard/protector status and advantages."},
	{"id": "guard", "key": "G", "label": "Guard", "tip": "Protect a friendly stack: it cannot be attacked or engaged except by units already engaged with it (and ranged/flying). Cannot guard while under assault. Costs advantages and engagements."},
	{"id": "deny", "key": "D", "label": "Deny", "tip": "End one of the target's engagements, a guard, or one advantage; or (spending an advantage) one level of a spell on it. Costs guard/protector status, one advantage, and engagements with anyone else."},
	{"id": "rally", "key": "R", "label": "Rally", "tip": "Remove morale damage equal to twice your morale from a friendly stack (or yourself)."},
	{"id": "seek", "key": "S", "label": "Seek Adv.", "tip": "+1 advantage (+1 attack, +1 defence) until lost."},
	{"id": "retaliate", "key": "T", "label": "Retaliate", "tip": "Hit back against every attack on you until your next turn."},
	{"id": "fallback", "key": "F", "label": "Fall Back", "tip": "Drop all engagements, guards and advantages. Until your next turn only guard can target you. Not allowed for your last standing unit."},
	{"id": "wait", "key": "W", "label": "Wait", "tip": "Tactics: act at the end of this round."},
]

const RULES := """[font_size=18][color=#f0d68e][b]Combat quick reference[/b][/color][/font_size]

[b]Turn order.[/b] Every stack acts once per round by initiative (ties: attacker first). Your commander acts at its initiative (3 points = 1, shown as 1, 1+, 1++…) and from then until the round ends may cast at the start of any of your stacks' turns.

[b]Damage.[/b] Roll 1dX (X = creatures, min 3): 1 = minimum, X = maximum, otherwise middle damage. × creatures. Each attack point above the target's defence +10% (max +300%); each defence point above attack −5% (max −75%). 75% goes to morale, 25% to health.

[b]Critical.[/b] Adds to your roll while you are trying to roll the top face (maximum damage), so with 3 or fewer creatures a +2 critical always hits maximum — there are no natural 1s.

[b]Casualties.[/b] When damage exceeds creatures × (value − 1), one creature is removed and damage drops by twice its value (+courage for morale). Morale casualties desert, health casualties die. Deserters also remove (health − 1) physical damage. Every turn a stack recovers morale damage equal to its morale.

[b]Numbers.[/b] Each creature adds +5% base attack/defence and +10% morale. Stacks at ≤ ⅓ of their start (or ≤ 2) become [b]heroes[/b]: +1 attack, defence, damage, morale; they rally; +1 courage (−1 when a hero stack is lost).

[b]Courage[/b] = hero courage − (number of allied stacks + number of allied tier-4 creatures). Each point removes 1 extra morale damage when a creature deserts.

[b]Mouse.[/b] On your stack's turn, click an enemy to attack it. For other actions, click the action then a target. Right-click cancels targeting, or shows a stack's details. Double-click one of your stacks to rename it. Keys: A E G D R S T F W, Esc cancels.

[b]Actions.[/b] Attack · Engage · Guard · Deny · Rally · Seek Advantage · Retaliate · Fall Back (· Wait with Tactics). Hover each button for exact rules. Red arrows = engagements, blue dashed = guards.

[b]Slow[/b] units can't attack in the first round(s) unless engaged with the target. [b]Ranged[/b] units can't be attacked/engaged in round 1 except by cavalry. [b]Cavalry[/b] can only be engaged by cavalry.

[b]End.[/b] An army is destroyed, someone retreats, or a full round passes with no damage."""

func start(battle: Battle, end_cb: Callable) -> void:
	b = battle
	on_end = end_cb
	mode = null; sel = null; spell = null; cmd = null; ended = false; busy = false
	_log_n = 0
	if not _built:
		_build()
	_setup_field()
	UI.show("battle")
	render()

# ------------------------------------------------------------------ layout
func _build() -> void:
	_built = true
	var root := UI.vbox([], 0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# top bar
	_chips = UI.hbox([], 6)
	_top_status = UI.hbox([], 6)
	_queue = UI.hbox([], 4)
	var qs := ScrollContainer.new()
	qs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	qs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qs.custom_minimum_size.y = 46
	qs.add_child(_queue)
	var top := UI.hbox([_chips, _top_status, qs, Music.control(), UI.button("⚙", Main.options, "Small", "Options"), UI.button("? Rules", show_rules, "Small", "Quick rules reference")], 10)
	root.add_child(UI.panel(top, UI.stone("bar").margins(12, 6)))
	# main
	var main := UI.hbox([], 0)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	var field := Control.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.clip_contents = true
	field.gui_input.connect(_field_input)
	main.add_child(field)
	_field_base = ColorRect.new()
	_field_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(_field_base)
	_field_paint = Control.new()
	_field_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_paint.modulate.a = 0.55
	_field_paint.draw.connect(func():
		if b != null:
			Paint.motifs(_field_paint, b.terrain_id, Rect2(Vector2.ZERO, _field_paint.size), 7, 34, 0.6))
	_field_paint.resized.connect(_field_paint.queue_redraw)
	field.add_child(_field_paint)
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.9, 0.9)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.06))
	gr.set_color(1, Color(0, 0, 0, 0.33))
	gt.gradient = gr
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(vig)
	var fm := MarginContainer.new()
	fm.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]: fm.add_theme_constant_override("margin_" + k, 16)
	for k in ["top", "bottom"]: fm.add_theme_constant_override("margin_" + k, 18)
	fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(fm)
	var fv := UI.vbox([], 10)
	fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fm.add_child(fv)
	_rows = [UI.hbox([], 12), UI.hbox([], 12)]
	_mid = PanelContainer.new()
	_mid.add_theme_stylebox_override("panel", UI.stone("tip").margins(16, 5))
	_mid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var s1 := Control.new(); s1.size_flags_vertical = Control.SIZE_EXPAND_FILL; s1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s2 := Control.new(); s2.size_flags_vertical = Control.SIZE_EXPAND_FILL; s2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(_rows[1]); fv.add_child(s1); fv.add_child(_mid); fv.add_child(s2); fv.add_child(_rows[0])
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	field.add_child(_lines)
	# side panel
	var side := UI.vbox([], 0)
	side.custom_minimum_size.x = 360
	main.add_child(UI.panel(side, UI.stone("panel").margins(4)))
	_act = UI.vbox([], 6)
	side.add_child(UI.panel(_act, UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 10)))
	side.add_child(UI.sep_line())
	var isc := ScrollContainer.new()
	isc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	isc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	isc.size_flags_stretch_ratio = 1.0
	_info = UI.vbox([], 4)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	isc.add_child(UI.panel(_info, UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 10)))
	isc.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(isc)
	side.add_child(UI.sep_line())
	_log = UI.rich("", 12, false)
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.size_flags_stretch_ratio = 1.2
	_log.add_theme_font_override("normal_font", UI.font_mono)
	_log.add_theme_color_override("default_color", Color("#cfcabd"))
	side.add_child(UI.panel(_log, UI.stone("inset").margins(8)))
	_log.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.get_parent().size_flags_stretch_ratio = 1.2

func _setup_field() -> void:
	var T: Dictionary = D.TERRAIN[b.terrain_id]
	_field_base.color = Color(T.color)
	_field_paint.queue_redraw()
	UI.clear(_chips)
	var TM: Dictionary = D.TIMES[b.time_id]
	var WE: Dictionary = D.WEATHER[b.weather_id]
	_chips.add_child(UI.chip("▲ " + T.name, "gold", "[b]%s[/b]\n%s" % [T.name, T.desc]))
	_chips.add_child(UI.chip("◐ " + TM.name, "", "[b]%s[/b] (chosen by attacker)\n%s" % [TM.name, TM.desc]))
	_chips.add_child(UI.chip(("☂ " if b.weather_id == "rain" else "☀ ") + WE.name, "", "[b]%s[/b]\n%s" % [WE.name, WE.desc]))
	UI.clear(_log)
	_log.clear()

func _process(_d: float) -> void:
	if visible and _lines:
		_lines.queue_redraw()

# ------------------------------------------------------------------ input
func _field_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_targeting()

func _cancel_targeting() -> bool:
	if mode != null or spell != null or cmd != null:
		mode = null; spell = null; cmd = null
		render()
		return true
	return false

func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or b == null or UI.modal_open() or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
		return
	var ch := OS.get_keycode_string(e.keycode).to_upper()
	for A in ACTIONS:
		if A.key == ch:
			pick_action(A.id)
			get_viewport().set_input_as_handled()
			return

func human_turn() -> bool:
	if b.over:
		return false
	if b.pre_combat:
		return true
	var e = b.current()
	return e != null and not b.sides[e.side].ai

func pick_action(id: String) -> void:
	var a := b.turn_stack()
	if a == null or not human_turn():
		return
	spell = null; cmd = null
	if id in ["seek", "retaliate", "fallback", "wait"]:
		var err = b.act(id)
		if err != null: UI.toast(err)
		mode = null
		render()
		return
	mode = null if mode == id else id
	if id == "attack" and mode != null:
		var any := false
		for t in b.enemies_of(a):
			if b.check_attack(a, t) == null: any = true
		if b.wall != null and b.check_wall_attack(a) == null: any = true
		if not any: UI.toast("No legal attack targets — hover enemies to see why.")
	render()

func click_stack(s) -> void:
	if b.over:
		return
	if spell != null:
		spell_target(s.id)
		return
	if cmd != null:
		var err = b.command(cmd.side, cmd.id, s.id)
		if err != null: UI.toast(err)
		cmd = null
		render()
		return
	if mode != null and human_turn():
		var a := b.turn_stack()
		if mode == "deny":
			var err0 = b.check_deny(a, s)
			if err0 != null:
				UI.toast(err0)
				return
			var opts := b.deny_options(a, s)
			if opts.size() == 1:
				do_act("deny", s.id, 0)
				return
			var labels := opts.map(func(o): return {"label": o.label})
			var i := await UI.choose("Deny " + s.name, "", labels, "Cancel", 360)
			if i >= 0:
				do_act("deny", s.id, i)
			return
		do_act(mode, s.id)
		return
	# no action picked: clicking an enemy during your stack's turn attacks it
	var cur_s := b.turn_stack()
	if cur_s != null and human_turn() and s.side != cur_s.side and s.count > 0:
		do_act("attack", s.id)
		return
	sel = s.id
	render()

func do_act(action: String, target, opt = null) -> void:
	var err = b.act(action, target, opt)
	if err != null:
		UI.toast(err)
		return
	mode = null
	render()

func pick_spell(side: int, id: String) -> void:
	if not b.hero_can_act(side):
		return
	mode = null; cmd = null
	spell = null if (spell != null and spell.id == id) else {"side": side, "id": id, "t1": null}
	render()

func spell_target(tid) -> void:
	var S: Dictionary = D.SPELLS[spell.id]
	if S.target == "pair" and spell.t1 == null:
		spell.t1 = tid
		UI.toast("Now pick the stack that receives the morale damage")
		render()
		return
	var err = b.cast(spell.side, spell.id, spell.t1, tid) if S.target == "pair" else b.cast(spell.side, spell.id, tid)
	if err != null: UI.toast(err)
	spell = null
	render()

# ------------------------------------------------------------------ rendering
func render() -> void:
	if b == null:
		return
	# status chips
	UI.clear(_top_status)
	_top_status.add_child(UI.chip("Round %d" % maxi(1, b.round_n)))
	if b.over == null and b.round_n >= 1 and not b.damage_this_round:
		_top_status.add_child(UI.chip("No damage yet this round", "warn", "If neither side takes damage during a round, the battle ends."))
	for sd in b.sides:
		_top_status.add_child(UI.chip("%s Courage %s" % ["▲" if sd.idx else "▼", U.fmt(sd.courage)], "", "%s courage. Each point removes 1 extra morale damage when a creature deserts. Starts at hero courage − (number of allied stacks + number of allied tier-4 creatures)." % U.esc(sd.name)))
	# queue
	UI.clear(_queue)
	for i in b.queue.size():
		var e: Dictionary = b.queue[i]
		var lbl: String
		var symc: Control
		if e.type == "hero":
			lbl = b.sides[e.side].hero.name
			symc = UI.label("♛", "gold2", 18)
			symc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			var s = b.stack(e.id)
			if s == null: continue
			lbl = s.name
			symc = UI.sym(s.def, 22)
			if s.count <= 0: symc.dim = true
		var iv: String = Heroes.init_str(U.jr(e.init * 3)) if e.type == "hero" else str(maxi(0, U.jr(e.init)))
		var curq: bool = i == b.qi and not b.pre_combat
		var t := UI.label(("▲" if e.side else "▼") + iv, "", 10)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_color_override("font_color", UI.C.gold2 if curq else UI.C.muted)
		var box := UI.vbox([symc, t], 0)
		var p := UI.panel(box, UI.sb(Color("#3a3120") if curq else Color(0, 0, 0, 0), UI.C.gold if curq else Color(0, 0, 0, 0), 6, 1, 4, 2))
		p.custom_minimum_size.x = 38
		if i < b.qi: p.modulate.a = 0.35
		UI.tip(p, "%s — initiative %s (%s)" % [U.esc(lbl), iv, "defender" if e.side else "attacker"])
		_queue.add_child(p)
	# rows
	_cards.clear()
	for side in 2:
		var row: HBoxContainer = _rows[side]
		UI.clear(row)
		row.add_child(hero_card(side))
		var st := HFlowContainer.new()
		st.alignment = FlowContainer.ALIGNMENT_CENTER
		st.add_theme_constant_override("h_separation", 10)
		st.add_theme_constant_override("v_separation", 10)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == 1 and b.wall != null:
			st.add_child(wall_card())
		for s in b.stacks:
			if s.side == side:
				var c := stack_card(s)
				_cards[s.id] = c
				st.add_child(c)
		row.add_child(st)
	# middle banner
	var mid := UI.hbox([], 6)
	var cur = b.current()
	if b.over != null:
		mid.add_child(UI.label("Battle over"))
	elif b.pre_combat:
		mid.add_child(UI.label("Pre-combat spells — then"))
		mid.add_child(UI.button("Begin battle", func(): b.end_pre_combat(); render(), "SmallPrimary"))
	elif cur != null:
		if cur.type == "hero":
			mid.add_child(UI.label("%s (%s) may cast or command." % [b.sides[cur.side].hero.name, b.sides[cur.side].name]))
		else:
			var s = b.stack(cur.id)
			mid.add_child(UI.label("%s (%s) to act" % [s.name, b.sides[s.side].name]))
		if mode != null: mid.add_child(UI.label(" — choose a target to %s  (Esc / right-click to cancel)" % mode, "gold2"))
		if spell != null: mid.add_child(UI.label(" — casting %s: pick %s target (Esc to cancel)" % [D.SPELLS[spell.id].name, "the receiving" if spell.t1 != null else "a"], "spell"))
		if cmd != null: mid.add_child(UI.label(" — %s: pick a friendly stack" % cmd.label, "gold2"))
	UI.clear(_mid)
	_mid.add_child(mid)
	render_actions()
	render_info()
	render_log()
	maybe_ai()
	if b.over != null and not ended:
		ended = true
		await get_tree().create_timer(0.02 if UI.autopilot else 0.45).timeout
		finish()

func _hero_sb(cur: bool) -> StoneBox:
	var s := UI.stone("panel").margins(9)
	if cur:
		s.halo = UI.C.gold; s.trim = UI.C.gold2
	return s

func hero_card(side: int) -> Control:
	var sd = b.sides[side]
	var box := UI.vbox([], 3)
	var card := UI.panel(box)
	card.custom_minimum_size.x = 176
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if sd.hero == null:
		card.add_theme_stylebox_override("panel", _hero_sb(false))
		var n := UI.label(sd.name, "gold2", 13)
		n.add_theme_font_override("font", UI.font_bold)
		box.add_child(n)
		box.add_child(UI.label("Neutral creatures" if sd.neutral else "No commander", "muted", 12))
		return card
	var hs = sd.hs
	var hero = sd.hero
	var can_act: bool = b.hero_can_act(side) and not sd.ai
	card.add_theme_stylebox_override("panel", _hero_sb(b.hero_turn_now(side) or (b.pre_combat and hs.freeCast > 0)))
	var nm := UI.label("♛ " + hero.name, "gold2", 13)
	nm.add_theme_font_override("font", UI.font_bold)
	UI.tip(nm, hero_tip(side))
	box.add_child(nm)
	var sn := UI.label(sd.name, "muted", 11)
	sn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sn.custom_minimum_size.x = 150
	box.add_child(sn)
	var init := Heroes.init_str(Heroes.stat(hero, "initiative") - hs.pips)
	box.add_child(UI.label("%s · Atk %d Def %d Pow %d Init %s" % [D.CLASSES[hero.cls].name, Heroes.stat(hero, "attack"), Heroes.stat(hero, "defence"), b.hero_stat(side, "power"), init], "muted", 11))
	if hs.gone:
		box.add_child(UI.label("Fallen in battle" if hs.gone == "dead" else "Fled the field", "bad", 12))
		return card
	var casts: String
	if b.pre_combat:
		casts = "Free pre-combat casts: %d" % hs.freeCast
	elif is_inf(hs.castsLeft):
		casts = "Casts left this round: ∞"
	else:
		casts = "Casts left this round: " + (U.fmt(hs.castsLeft) if hs.active else "— (acts at its initiative)")
	var cl := UI.label(casts, "muted", 11)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size.x = 150
	box.add_child(cl)
	var left := b.spell_uses_left(side)
	for id in left:
		var S: Dictionary = D.SPELLS[id]
		var uses: String = "∞" if is_inf(left[id]) else "×%s" % U.fmt(left[id])
		var sel_now: bool = spell != null and spell.id == id and spell.side == side
		var bt := UI.button("%s   %s" % [S.name, uses], func(): pick_spell(side, id), "SmallSel" if sel_now else "Small")
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.disabled = not can_act or left[id] <= 0
		var tp: String = "[b]%s[/b] (%s, cost %s)\n%s" % [S.name, S.kind, S.cost, S.desc]
		if S.kind == "damage":
			var pm := b.spell_power_mult(side, id)
			tp += "\nRight now: %d (power +%d%%)" % [U.jr(S.amount * pm), U.jr((pm - 1) * 100)]
		UI.tip(bt, tp)
		box.add_child(bt)
	if not sd.ai and not b.pre_combat:
		var cmds := UI.flow([], 4)
		for c in b.command_options(side):
			var cb := UI.button(c.label, func():
				if c.need == null:
					var err = b.command(side, c.id)
					if err != null: UI.toast(err)
					render()
					return
				mode = null; spell = null
				cmd = {"side": side, "id": c.id, "label": c.label}
				render(), "SmallSel" if (cmd != null and cmd.id == c.id) else "Small", c.desc)
			cb.disabled = not can_act
			cmds.add_child(cb)
		box.add_child(cmds)
		var r2 := UI.flow([], 4)
		if b.hero_turn_now(side):
			r2.add_child(UI.button("End command ▸", func(): b.hero_end(side); spell = null; cmd = null; render(), "SmallPrimary"))
		r2.add_child(UI.button("Retreat", func():
			if await UI.confirm("%s: retreat from the battle?" % sd.name):
				b.flee(side)
				render(), "SmallDanger"))
		box.add_child(r2)
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and spell != null and D.SPELLS[spell.id].target == "stackOrHero":
			spell_target("hero%d" % side))
	return card

func hero_tip(side: int) -> String:
	var sd = b.sides[side]
	var hero = sd.hero
	var s := "[b]%s[/b] — %s\n" % [U.esc(hero.name), D.CLASSES[hero.cls].name]
	var pairs := []
	for k in D.PRIMARY:
		pairs.append([k, Heroes.init_str(Heroes.stat(hero, k)) if k == "initiative" else str(Heroes.stat(hero, k))])
	s += UI.kv(pairs)
	var sk := []
	for k in hero.skills:
		if hero.skills[k]: sk.append("%s %s" % [D.SKILLS[k].name, "I".repeat(hero.skills[k])])
	if sk.size(): s += "\n" + ", ".join(sk)
	if hero.artifacts.size():
		s += "\n" + UI.col(", ".join(hero.artifacts.map(func(a): return D.ARTIFACTS[a].name)), "gold")
	if sd.hs != null:
		s += "\n" + UI.col("Spare knowledge %s · pips spent %d" % [U.fmt(sd.hs.spareKnowledge), sd.hs.pips], "muted")
	return s

func wall_card() -> Control:
	var a := b.turn_stack()
	var box := UI.vbox([UI.label("▙▟▙", "", 24), UI.label("Walls"), UI.label("%s / %s" % [U.fmt(b.wall.hp), U.fmt(b.wall.max)])], 2)
	for c in box.get_children(): c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ok := false
	var err = null
	if mode == "attack" and a != null:
		err = b.check_wall_attack(a)
		ok = err == null
	var card := UI.panel(box, UI.sb(Color(0.165, 0.15, 0.133, 0.93), UI.C.good if ok else Color("#8a7a60"), 10, 2, 8))
	card.custom_minimum_size.x = 110
	if b.wall.hp <= 0: card.modulate.a = 0.3
	UI.tip(card, "Town walls. While standing they protect defenders (every %d damage uncovers one more defender, from the bottom of the line)." % D.CFG.wallPerStack)
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and mode == "attack" and a != null:
			if err != null: UI.toast(err)
			else: do_act("attack", "wall"))
	return card

func check_for(m: String, a, t):
	match m:
		"attack": return b.check_attack(a, t)
		"engage": return b.check_engage(a, t)
		"guard": return b.check_guard(a, t)
		"deny": return b.check_deny(a, t)
		"rally": return b.check_rally(a, t)
	return "n/a"

func _bar(frac: float, col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 6)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0, 0, 0, 0.45))
		if frac > 0: c.draw_rect(Rect2(Vector2.ZERO, Vector2(c.size.x * clampf(frac, 0, 1), c.size.y)), col))
	return c

func _barlbl(l: String, r: String) -> Control:
	var a := UI.label(l, "muted", 10)
	var z := UI.label(r, "muted", 10)
	a.add_theme_font_override("font", UI.font_mono)
	z.add_theme_font_override("font", UI.font_mono)
	return UI.hbox([a, UI.spacer(), z], 0)

func _badge(text: String, fg: Color, border: Color, tp: String) -> Control:
	var l := UI.label(text, "", 10)
	l.add_theme_color_override("font_color", fg)
	var p := UI.panel(l, UI.sb(Color(0, 0, 0, 0.4), border, 4, 1, 4, 0))
	UI.tip(p, tp)
	return p

func stack_card(s) -> Control:
	var cur := b.turn_stack()
	var reason = null
	var state := ""
	if s.count > 0 and mode != null and cur != null and human_turn():
		reason = check_for(mode, cur, s)
		state = "invalid" if reason != null else "valid"
	if s.count > 0 and spell != null:
		var S: Dictionary = D.SPELLS[spell.id]
		var err = b.check_cast(spell.side, spell.id, s.id, s.id if (S.target == "pair" and spell.t1 != null) else null)
		if S.target == "pair" and spell.t1 == s.id: reason = "first target"
		elif S.target == "pair" and spell.t1 != null: reason = null
		else: reason = err
		state = "invalid" if reason != null else "valid"
	if cmd != null and (s.count > 0 or _can_bring_back(s)):
		state = "valid" if (s.side == cmd.side and (s.count > 0 or _can_bring_back(s))) else "invalid"
	var active: bool = cur == s and b.over == null
	var border: Color = UI.C.line2
	if state == "valid": border = UI.C.good
	if active: border = UI.C.gold
	var st := UI.stone("panel").margins(8, 7)
	st.fill = Color("#26211b")
	st.trim = Color(0, 0, 0, 0)
	var band := Color("#9a4a34") if s.side == 0 else Color("#3f6a9a")
	if s.side == 0: st.accent_bottom = band
	else: st.accent_top = band
	if active:
		st.halo = UI.C.gold; st.trim = UI.C.gold2
	elif state == "valid":
		st.halo = UI.C.good; st.halo_w = 2
	if sel == s.id and not active:
		st.trim = Color(1, 1, 1, 0.75)
	var mv: int = s.morale_val
	var hp := b.health(s)
	var mcap := maxi(0, s.count * (mv - 1))
	var hcap := maxi(0, s.count * (hp - 1))
	var mfrac: float = minf(1, maxf(0, s.mor) / mcap) if mcap > 0 else (1.0 if s.mor > 0 else 0.0)
	var hfrac: float = minf(1, maxf(0, s.phys) / hcap) if hcap > 0 else (1.0 if s.phys > 0 else 0.0)
	var slow := b.slow_level(s)
	var badges := UI.flow([], 3)
	if s.adv > 0: badges.add_child(_badge("◆%d" % s.adv, UI.C.adv, Color("#3f7a70"), "+%d attack and defence" % s.adv))
	var eng := []
	for id in s.engaging:
		var x = b.stack(id)
		if x != null: eng.append(x)
	if eng.size(): badges.add_child(_badge("⚔→%d" % eng.size(), UI.C.engage, Color("#7a3a30"), "Engaging: " + ", ".join(eng.map(func(x): return U.esc(x.name)))))
	var ass := b.assaulters(s)
	if ass.size(): badges.add_child(_badge("⚠ assault", UI.C.engage, Color("#7a3a30"), "Under assault from: %s\nMust target one of them." % ", ".join(ass.map(func(x): return U.esc(x.name)))))
	if b.is_guarded(s): badges.add_child(_badge("◈", UI.C.guard, Color("#2e5a80"), "Guarded by " + U.esc(b.protector_of(s).name)))
	if s.guarding != null and b.stack(s.guarding) != null: badges.add_child(_badge("◈→", UI.C.guard, Color("#2e5a80"), "Guarding " + U.esc(b.stack(s.guarding).name)))
	if s.retaliating or s.sp("alwaysRetaliate"): badges.add_child(_badge("↺", Color("#f0c070"), UI.C.line2, "Will retaliate"))
	if s.fallen_back: badges.add_child(_badge("↶", UI.C.text, UI.C.line2, "Fallen back: only guard can target it until its next turn"))
	if slow and s.count > 0: badges.add_child(_badge("◷%d" % slow, Color("#c0b090"), UI.C.line2, "Slow %d: cannot attack in rounds 1-%d unless engaged with the target" % [slow, slow]))
	if b.is_ranged(s): badges.add_child(_badge("➶", UI.C.text, UI.C.line2, D.ABILITY_TEXT.ranged + (" (half damage, from the Watchfort)" if b.half_ranged_only(s) else "")))
	if b.is_cavalry(s): badges.add_child(_badge("»", UI.C.text, UI.C.line2, D.ABILITY_TEXT.cavalry))
	if b.wall_protected(s): badges.add_child(_badge("▙", UI.C.guard, Color("#2e5a80"), "Protected by the walls"))
	for id in s.spells:
		badges.add_child(_badge(D.SPELLS[id].name + (" %d" % s.spells[id] if s.spells[id] > 1 else ""), UI.C.spell, Color("#5c4680"), D.SPELLS[id].desc))
	if s.phys < 0: badges.add_child(_badge("⬢" + U.fmt(-s.phys), UI.C.adv, Color("#3f7a70"), "Negative physical damage (buffer)"))
	# body
	var cnt := UI.label(str(s.count), "", 22)
	cnt.add_theme_font_override("font", UI.font_bold)
	var nm := UI.label(s.name, "muted", 11)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	nm.custom_minimum_size.x = 76
	var topr := UI.hbox([UI.sym(s.def, 44), UI.vbox([cnt, nm], 0)], 6)
	if s.hero and s.count > 0:
		var cr := UI.label("♛", "gold2", 14)
		UI.tip(cr, "Hero unit: +1 attack, defence, damage, morale")
		topr.add_child(cr)
	var stats := UI.label("Atk %s Def %s I%d" % [U.fmt(b.attack(s)), U.fmt(b.defence(s)), b.initiative(s)], "muted", 10)
	stats.add_theme_font_override("font", UI.font_mono)
	var body := UI.vbox([topr, stats,
		_bar(mfrac, UI.C.morale), _barlbl("M " + U.fmt(mv), "%s/%s" % [U.fmt(maxf(0, s.mor)), U.fmt(mcap)]),
		_bar(1.0 if s.phys < 0 else hfrac, UI.C.adv if s.phys < 0 else UI.C.health), _barlbl("H " + U.fmt(hp), "%s/%s" % [U.fmt(maxf(0, s.phys)), U.fmt(hcap)]),
		badges], 2)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := UI.panel(body, st)
	card.custom_minimum_size.x = 138
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if s.count > 0 else Control.CURSOR_ARROW
	if s.count <= 0: card.modulate = Color(0.8, 0.8, 0.8, 0.75) if state == "valid" else Color(0.6, 0.6, 0.6, 0.3)
	elif state == "invalid" and not active: card.modulate.a = 0.45
	elif s.fallen_back: card.modulate.a = 0.7
	# tooltip
	var tp := UI.unit_tip(s.def, live_tip(s))
	if reason != null and reason != "first target":
		tp = UI.col("✗ " + U.esc(reason), "bad") + "\n" + tp
	elif mode == "attack" and cur != null and s.count > 0 and reason == null:
		tp = preview_tip(cur, s) + tp
	elif mode == null and spell == null and cmd == null and cur != null and s.count > 0 and s.side != cur.side and human_turn():
		var why = b.check_attack(cur, s)
		if why != null:
			tp = UI.col("Click: can't attack — " + U.esc(why), "bad") + "\n" + tp
		else:
			tp = UI.col("Click to attack", "gold2") + "\n" + preview_tip(cur, s) + tp
	UI.tip(card, tp)
	card.gui_input.connect(func(e):
		if not (e is InputEventMouseButton) or not e.pressed: return
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click:
				var v = await UI.prompt("Rename stack", s.name)
				if v != null and v != "":
					s.name = v
					render()
			elif s.count > 0 or (cmd != null and _can_bring_back(s)):
				click_stack(s)
			card.accept_event()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			if not _cancel_targeting():
				sel = s.id
				render()
			card.accept_event())
	return card

## a wiped-out stack the current command could bring back (recall a deserter / revive a dead)
func _can_bring_back(s) -> bool:
	if cmd == null or s.count > 0 or s.side != cmd.side: return false
	return (cmd.id == "recall" and s.deserters > 0) or (cmd.id == "revive" and s.dead > 0)

func preview_tip(a, t) -> String:
	var n := b.hit_numbers(a, t, {"average": true})
	var e := b.expected_hit(a, t)
	var ret: bool = (t.retaliating or t.sp("alwaysRetaliate")) and not (b.is_ranged(a) and not b.is_ranged(t))
	var s := UI.col(UI.b("Attack preview (average roll)"), "good") + "\n"
	s += "Atk %s vs Def %s → %s%d%% damage\n%s morale + %s health damage\n≈ %s creature(s) removed" % [U.fmt(n.A), U.fmt(n.D), "+" if n.mult >= 1 else "", U.jr((n.mult - 1) * 100), U.fmt(n.mor), U.fmt(n.phys), str(e.removed)]
	if ret: s += "\n" + UI.col("Target will retaliate", "bad")
	return s + "\n" + UI.col("────────────", "dim") + "\n"

func live_tip(s) -> String:
	var tri := b.dmg_triple(s)
	var ec := b.eff_count(s)
	var created := "%d / %d (%d dead, %d deserted%s)" % [s.count, s.start, s.dead, s.deserters, (", %d gained" % s.gained) if s.gained else ""]
	return "\n\n" + UI.b("In this battle") + "\n" + UI.kv([
		["Creatures", created], ["Attack", U.fmt(b.attack(s))], ["Defence", U.fmt(b.defence(s))],
		["Morale", "%s each · dmg %s" % [U.fmt(s.morale_val), U.fmt(s.mor)]], ["Health", "%s each · dmg %s" % [U.fmt(b.health(s)), U.fmt(s.phys)]],
		["Damage", "%s × %s (d%d)" % [" / ".join(tri.map(func(x): return U.fmt(x))), U.fmt(ec), maxi(3, U.jr(ec))]], ["Initiative", str(b.initiative(s))]])

func _hint(text: String) -> Control:
	var l := UI.label(text, "gold2", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return UI.panel(l, UI.sb(Color(0.23, 0.19, 0.125, 0.6), Color("#6e5a30"), 6, 1, 8, 6))

func render_actions() -> void:
	UI.clear(_act)
	var a := b.turn_stack()
	if b.over != null:
		_act.add_child(_hint("The battle is over."))
		return
	if b.pre_combat:
		_act.add_child(_hint("Pre-combat: cast your Herald's Scroll spell, then Begin battle."))
		return
	var cur = b.current()
	if not human_turn():
		_act.add_child(_hint("%s (AI) is thinking…" % b.sides[cur.side].name))
		return
	if cur.type == "hero":
		_act.add_child(_hint("Your commander's turn: cast a spell or use a command (commander card), then \"End command\". From now until the round ends, the commander may also act at the start of any of your stacks' turns."))
		return
	var nm := UI.label(a.name, "gold2")
	nm.add_theme_font_override("font", UI.font_bold)
	_act.add_child(UI.hbox([nm, UI.spacer(), UI.label(b.sides[a.side].name, "muted")]))
	var ass := b.assaulters(a)
	if ass.size():
		_act.add_child(_hint("Under assault — attacks, engages and denies must target: " + ", ".join(ass.map(func(x): return x.name))))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for A in ACTIONS:
		if A.id == "wait" and not b.can_wait(a): continue
		var bt := UI.button(A.label, func(): pick_action(A.id), "Sel" if mode == A.id else "", "[b]%s[/b] [%s]\n%s" % [A.label, A.key, A.tip])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if A.id == "fallback": bt.disabled = b.check_fallback(a) != null
		grid.add_child(bt)
	_act.add_child(grid)
	if b.hero_can_act(a.side) and b.sides[a.side].hero != null:
		_act.add_child(UI.label("Your commander may cast before this stack acts.", "muted", 12))

func render_info() -> void:
	UI.clear(_info)
	var s = b.stack(sel) if sel != null else null
	if s == null: s = b.turn_stack()
	if s == null:
		_info.add_child(UI.label("Click a stack for details. Hover anything for help.", "muted", 12))
		return
	_info.add_child(UI.hbox([UI.h3("Details"), UI.spacer(), UI.button("Rename", func():
		var v = await UI.prompt("Rename stack", s.name)
		if v != null and v != "":
			s.name = v
			render(), "Small")]))
	_info.add_child(UI.rich(UI.unit_tip(s.def, live_tip(s)), 12))

const LOG_COL := {"round": "#d9b45a", "dmg": "#e8c9a8", "loss": "#f08a7a", "good": "#6cc07a", "hero": "#f0d68e", "spell": "#b58cf0", "big": "#ffffff"}

func render_log() -> void:
	if _log_n > b.log.size():
		_log.clear(); _log_n = 0
	while _log_n < b.log.size():
		var L: Dictionary = b.log[_log_n]
		var t := U.esc(L.t)
		var c: String = L.get("cls", "")
		if c in ["round", "big"]: t = "[b]%s[/b]" % t
		if LOG_COL.has(c): t = "[color=%s]%s[/color]" % [LOG_COL[c], t]
		if c == "round" and _log_n > 0: t = "\n" + t
		_log.append_text(t + "\n")
		_log_n += 1

# ------------------------------------------------------------------ lines
func _box(id) -> Rect2:
	var c = _cards.get(id)
	if c == null or not is_instance_valid(c): return Rect2()
	var r: Rect2 = c.get_global_rect()
	r.position -= _lines.get_global_rect().position
	return r

func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var q := 1 - t
		out.append(p0 * q * q * q + p1 * 3 * q * q * t + p2 * 3 * q * t * t + p3 * t * t * t)
	return out

func _draw_lines() -> void:
	if b == null: return
	var red := Color("#e0604a")
	var blue := Color("#5aa0e0")
	for s in b.stacks:
		if s.count <= 0: continue
		var A := _box(s.id)
		if A.size == Vector2.ZERO: continue
		for id in s.engaging:
			var t = b.stack(id)
			var B := _box(id)
			if t == null or t.count <= 0 or B.size == Vector2.ZERO: continue
			var p1 := Vector2(A.position.x + A.size.x / 2, A.position.y if s.side == 0 else A.end.y)
			var p2 := Vector2(B.position.x + B.size.x / 2, B.position.y if t.side == 0 else B.end.y)
			var my := (p1.y + p2.y) / 2
			var pts := _bez(p1, Vector2(p1.x, my), Vector2(p2.x, my), p2)
			_lines.draw_polyline(pts, Color(red, 0.9), 3, true)
			var dir := (pts[pts.size() - 1] - pts[pts.size() - 3]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			_lines.draw_colored_polygon(PackedVector2Array([p2, p2 - dir * 11 + nrm * 6, p2 - dir * 11 - nrm * 6]), red)
		if s.guarding != null:
			var t = b.stack(s.guarding)
			var B := _box(s.guarding)
			if t == null or t.count <= 0 or B.size == Vector2.ZERO: continue
			var x1 := A.position.x + A.size.x / 2
			var x2 := B.position.x + B.size.x / 2
			var y := A.end.y + 4 if s.side == 0 else A.position.y - 4
			var dy := 22.0 if s.side == 0 else -22.0
			var pts := _bez(Vector2(x1, y), Vector2(x1, y + dy), Vector2(x2, y + dy), Vector2(x2, y), 30)
			for i in range(0, pts.size() - 1, 2):
				_lines.draw_line(pts[i], pts[i + 1], blue, 3, true)
			var mid := Vector2((x1 + x2) / 2, y + dy * 0.8 + 5)
			_lines.draw_string(UI.font, mid - Vector2(6, 0), "◈", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#9cc8f0"))

# ------------------------------------------------------------------ AI & end
func maybe_ai() -> void:
	if b.over != null or busy: return
	var e = b.current()
	var ai_now: bool
	if b.pre_combat:
		ai_now = true
		for sd in b.sides:
			if not (sd.ai or not (sd.hs != null and sd.hs.freeCast > 0)): ai_now = false
	else:
		ai_now = e != null and (b.sides[e.side].ai or UI.autopilot)
	if UI.autopilot: ai_now = true
	if not ai_now: return
	busy = true
	var bb := b
	if UI.autopilot: await get_tree().process_frame
	else: await get_tree().create_timer(ai_delay).timeout
	busy = false
	if b != bb: return
	CombatAI.step(b)
	render()

func finish() -> void:
	var o: Dictionary = b.over
	var title: String
	if o.winner == null: title = "Stalemate" if o.reason == "stalemate" else "Draw"
	else:
		var ws = b.sides[o.winner]
		title = "Victory for %s" % (ws.hero.name if ws.hero != null else ws.name)
	var fl = o.get("fled")
	var reason: String = {"destroyed": "An army was destroyed or routed.", "fled": "%s retreated." % b.sides[fl if fl != null else 0].name, "stalemate": "No damage was dealt in a whole round.", "exhaustion": "Round limit reached."}.get(o.reason, "")
	var armies := UI.vbox([], 10)
	for side in 2:
		armies.add_child(_army_summary(side, o.winner == side))
	var w := Waiter.new()
	var box := UI.vbox([UI.h2(title), UI.label("%s (%d rounds)" % [reason, b.round_n], "muted"), armies,
		UI.row_end([UI.button("Continue", func(): UI.close_modal(); w.done.emit(true), "Primary")])])
	if UI.autopilot:
		print("[battle] ", title, " — ", reason, " (%d rounds)" % b.round_n)
	else:
		UI.modal(box, true, 440)
		await w.done
	if on_end.is_valid():
		on_end.call(b)

## one army's block in the post-battle report: a coloured title plate, then its stacks and a total
func _army_summary(side: int, won: bool) -> Control:
	var sd = b.sides[side]
	var col: Color = Color(D.FACTIONS[sd.faction].color).lightened(0.2)
	var who: String = ("♛ " + sd.hero.name) if sd.hero != null else sd.name
	var t := UI.label(("▼ " if side == 0 else "▲ ") + who, "", 16)
	t.add_theme_font_override("font", UI.font_head)
	t.add_theme_color_override("font_color", col)
	var kids: Array = [t]
	if sd.hero != null and not sd.name in ["Attacker", "Defender"]: kids.append(UI.label(sd.name, "muted", 12))
	kids.append(UI.label("Attacker" if side == 0 else "Defender", "muted", 12))
	kids.append(UI.spacer())
	if won: kids.append(UI.chip("Victorious", "gold"))
	var plate := UI.stone("plate").margins(10, 5)
	plate.accent_w = 3
	plate.accent_bottom = col
	var head := UI.panel(UI.hbox(kids, 8), plate)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	for hd in ["Stack", "Start", "Left", "Dead", "Deserted"]:
		grid.add_child(UI.label(hd, "muted", 12))
	var tot := [0, 0, 0, 0]
	for s in b.stacks:
		if s.side != side: continue
		var nm := UI.label(s.name, "", 12)
		nm.custom_minimum_size.x = 170
		grid.add_child(nm)
		var vals := [s.start, maxi(0, s.count), s.dead, s.deserters]
		for i in 4:
			tot[i] += vals[i]
			grid.add_child(UI.label(str(vals[i]), "", 12))
	var tl := UI.label("Total", "gold", 12)
	tl.add_theme_font_override("font", UI.font_bold)
	grid.add_child(tl)
	for v in tot:
		var l := UI.label(str(v), "gold", 12)
		l.add_theme_font_override("font", UI.font_bold)
		grid.add_child(l)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_child(grid)
	return UI.vbox([head, m], 4)

func show_rules() -> void:
	UI.modal(UI.rich(RULES), false, 680)
