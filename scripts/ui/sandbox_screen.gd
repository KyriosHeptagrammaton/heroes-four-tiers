# ============================================================================
# Combat sandbox: build two armies + commanders, pick the ground, fight or
# simulate 100 AI-vs-AI battles.
# ============================================================================
extends Control

var cfg = null
var _body: Control

func default_side(f: String, ai: bool) -> Dictionary:
	return {
		"faction": f, "ai": ai, "name": "",
		"hero": {"enabled": true, "cls": "warlord", "name": "", "stats": (D.CFG.heroStart.warlord as Dictionary).duplicate(), "skills": {}, "artifacts": [], "equipped": ["flame"]},
		"stacks": [1, 2, 3].map(func(t): return {"key": Units.key(f, t, 0, ""), "count": default_count(Units.key(f, t, 0, ""))}),
	}

## default stack size by tier: T1 18, T2 9, T3 6, T4 3;
## riders with twice the weekly growth (the Leshi) start with twice as many
func default_count(k: String) -> int:
	var n: int = {1: 18, 2: 9, 3: 6, 4: 3}.get(mini(4, maxi(1, int(Units.resolve(k).tier))), 1)
	if Units.resolve_single(k.split("@")[0]).get("sp", {}).get("doubleGrowth", false):
		n *= 2
	return n

func open() -> void:
	if cfg == null:
		cfg = {"sides": [default_side("alpha", false), default_side("beta", true)], "terrain": "field", "time": "dawn", "weather": "clear", "ignored": false, "seed": 0}
	if cfg.sides[0].name == "": cfg.sides[0].name = "Attacker"
	if cfg.sides[1].name == "": cfg.sides[1].name = "Defender"
	UI.show("sandbox")
	render()

func make_hero(hc: Dictionary, f: String):
	if not hc.enabled:
		return null
	var hero := Heroes.create(hc.cls, f, hc.name if hc.name != "" else null, Rng.new(randi()))
	hero.stats = hc.stats.duplicate()
	hero.skills = hc.skills.duplicate()
	hero.artifacts = hc.artifacts.duplicate()
	hero.spellbook = D.SPELLS.keys()
	hero.equipped = hc.equipped.duplicate()
	if hc.name != "": hero.name = hc.name
	return hero

func battle_opts(seed_v: int = 0, force_ai: bool = false) -> Dictionary:
	var sides := []
	for sd in cfg.sides:
		sides.append({"name": sd.name, "faction": sd.faction, "ai": force_ai or sd.ai, "hero": make_hero(sd.hero, sd.faction),
			"stacks": sd.stacks.map(func(s): return {"key": s.key, "count": s.count})})
	# two random commanders shouldn't share a name
	var h0 = sides[0].hero
	var h1 = sides[1].hero
	if h0 != null and h1 != null and h0.name == h1.name and cfg.sides[1].hero.name == "":
		var others: Array = D.HERO_NAMES.filter(func(n): return n != h0.name)
		h1.name = others[randi() % others.size()]
	return {"seed": seed_v if seed_v else (cfg.seed if cfg.seed else randi() % 1000000000 + 1), "terrain": cfg.terrain, "time": cfg.time, "weather": cfg.weather, "ignoredAttack": cfg.ignored, "sides": sides}

## effective stats of both armies with the current heroes and battlefield
var _eff_cache := {"k": "", "v": []}
func _eff() -> Array:
	var ck := JSON.stringify(cfg)
	if ck == _eff_cache.k:
		return _eff_cache.v
	var o := battle_opts(1)
	for sd in o.sides:
		if sd.stacks.is_empty():
			sd.stacks = [{"key": Units.key(sd.faction, 1, 0, ""), "count": 1}]
	_eff_cache.k = ck
	_eff_cache.v = Battle.probe_stats(o)
	return _eff_cache.v

## why this setup can't be fought yet (or "" if it can)
func setup_problem() -> String:
	var errs := []
	for i in 2:
		var hc: Dictionary = cfg.sides[i].hero
		if not hc.enabled or hc.equipped.size() <= 1: continue
		var fake := {"cls": hc.cls, "skills": hc.skills, "artifacts": hc.artifacts, "stats": hc.stats}
		var cost := Heroes.equipped_cost(fake, hc.equipped)
		var know := Heroes.stat(fake, "knowledge")
		if cost > know:
			errs.append("%s's commander: spells cost %d but knowledge is only %d" % [cfg.sides[i].name, cost, know])
	for i in 2:
		if cfg.sides[i].stacks.is_empty():
			errs.append("%s has no army" % cfg.sides[i].name)
	return "\n".join(errs)

func fight() -> void:
	var err := setup_problem()
	if err != "":
		UI.toast(err.split("\n")[0], 3.5)
		return
	var b := Battle.new(battle_opts())
	UI.screen("battle").start(b, func(_b): open())

func simulate(n: int) -> void:
	var err := setup_problem()
	if err != "":
		UI.toast(err.split("\n")[0], 3.5)
		return
	var res := {"w": [0, 0, 0], "rounds": 0, "loss": [0.0, 0.0], "n": 0}
	var out := UI.vbox([UI.h2("Simulating…")])
	UI.modal(out, true, 440)
	var total := [0.0, 0.0]
	for i in 2:
		for s in cfg.sides[i].stacks:
			total[i] += s.count * Units.value(Units.resolve(s.key))
	while res.n < n:
		for k in 10:
			if res.n >= n: break
			var b := Battle.new(battle_opts((res.n + 1) * 7919, true))
			var guard := 0
			while b.over == null and guard < 20000:
				CombatAI.step(b)
				guard += 1
			res.w[2 if b.over.winner == null else b.over.winner] += 1
			res.rounds += b.round_n
			for i in 2:
				for s in b.stacks:
					if s.side == i and not (s.name in ["Militia", "Mercenaries"]):
						res.loss[i] += (s.start - maxi(0, s.count)) * Units.value(s.def)
			res.n += 1
		var pct := func(x) -> String: return "%d%%" % U.jr(100.0 * x / maxi(1, res.n))
		UI.clear(out)
		out.add_child(UI.h2("AI vs AI: %d / %d battles" % [res.n, n]))
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 24)
		for x in ["", cfg.sides[0].name + " ▼", cfg.sides[1].name + " ▲", "Wins", pct.call(res.w[0]), pct.call(res.w[1]), "Avg. value lost",
				U.fmt(res.loss[0] / maxi(1, res.n) / maxf(1, total[0]) * 100) + "%", U.fmt(res.loss[1] / maxi(1, res.n) / maxf(1, total[1]) * 100) + "%"]:
			g.add_child(UI.label(x))
		out.add_child(g)
		out.add_child(UI.rich(UI.col("Stalemates/draws: %s · average %s rounds · army value %s vs %s (T1=1, T2=2, T3=3, T4=6 per creature)" % [pct.call(res.w[2]), U.fmt(float(res.rounds) / maxi(1, res.n)), U.fmt(total[0]), U.fmt(total[1])], "muted")))
		out.add_child(UI.label("The AI is a simple one-ply heuristic, so treat these as rough signals, not verdicts.", "muted", 12))
		await get_tree().process_frame
		if not is_instance_valid(out): return
	out.add_child(UI.row_end([UI.button("Close", UI.close_modal, "Primary")]))

# ---------------------------------------------------------------- rendering
func render() -> void:
	UI.clear(self)
	var root := UI.vbox([], 0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var T: Dictionary = D.TERRAIN[cfg.terrain]
	var terr := []
	for k in D.TERRAIN:
		if k != "chasm": terr.append([k, D.TERRAIN[k].name])
	var times := []
	for k in D.TIMES: times.append([k, D.TIMES[k].name])
	var weathers := []
	for k in D.WEATHER: weathers.append([k, D.WEATHER[k].name])
	var o1 := UI.option(terr, cfg.terrain, func(v): cfg.terrain = v; render())
	UI.tip(o1, "[b]%s[/b]\n%s" % [T.name, T.desc])
	var o2 := UI.option(times, cfg.time, func(v): cfg.time = v; render())
	UI.tip(o2, D.TIMES[cfg.time].desc)
	var o3 := UI.option(weathers, cfg.weather, func(v): cfg.weather = v; render())
	UI.tip(o3, D.WEATHER[cfg.weather].desc)
	var ig := UI.check("Defender ignored", cfg.ignored, func(v): cfg.ignored = v)
	UI.tip(ig, "The defender chose to ignore the attack instead of picking ground: 1-3 random defending stacks gain one slow.")
	var bar := UI.hbox([UI.button("◂ Menu", func(): Main.menu()), UI.h2("Combat Sandbox"), UI.button("⚙", Main.options, "Small", "Options"), UI.spacer(),
		UI.label("Ground", "muted"), o1, UI.label("Time", "muted"), o2, UI.label("Weather", "muted"), o3, ig,
		_gated(UI.button("⚖ Simulate ×100", func(): simulate(100), "", "Run 100 AI-vs-AI battles with these armies")),
		_gated(UI.button("⚔ Fight!", fight, "Primary"))], 10)
	root.add_child(UI.panel(bar, UI.stone("bar")))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 12)
	sc.add_child(m)
	var cols := UI.hbox([side_editor(0), side_editor(1)], 12)
	m.add_child(cols)

func side_editor(i: int) -> Control:
	var sd: Dictionary = cfg.sides[i]
	var box := UI.vbox([], 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := LineEdit.new()
	nm.text = sd.name
	nm.custom_minimum_size.x = 130
	nm.text_changed.connect(func(t): sd.name = t)
	var fac := []
	for f in D.FACTION_IDS: fac.append([f, D.FACTIONS[f].name])
	box.add_child(UI.panel(UI.flow([UI.h2("▼ Attacker" if i == 0 else "▲ Defender"), nm, UI.label("Faction", "muted"),
		UI.option(fac, sd.faction, func(v): sd.faction = v; render()), UI.check("AI controlled", sd.ai, func(v): sd.ai = v)], 8)))
	# stacks
	var sp := UI.vbox([], 4)
	var add := UI.button("+ Add stack", func():
		sd.stacks.append({"key": Units.key(sd.faction, 1, 0, ""), "count": default_count(Units.key(sd.faction, 1, 0, ""))})
		render(), "Small")
	add.disabled = sd.stacks.size() >= D.CFG.maxStacks
	sp.add_child(UI.hbox([UI.h3("Army (%d/%d stacks)" % [sd.stacks.size(), D.CFG.maxStacks]), UI.spacer(), add]))
	for k in sd.stacks.size():
		var s: Dictionary = sd.stacks[k]
		var d := Units.resolve(s.key)
		var sy := UI.sym(d, 26)
		# computed on hover so it follows count / hero / battlefield edits
		var e := func() -> Dictionary:
			var all: Array = _eff()[i]
			return all[k] if k < all.size() else {}
		UI.tip(sy, func(): return UI.unit_tip(d, "", e.call()))
		var parts: PackedStringArray = s.key.split("@")
		var rp := Units.parse(parts[0])
		var base_name: String = Units.resolve(Units.key(rp.faction, rp.tier, 0, "")).name
		var nb := UI.button(base_name + (" ⚑" if d.placeholder else ""), func(): pick_unit(sd, s), "", func(): return UI.unit_tip(d, "\n\n" + UI.col("Click to choose another creature", "muted"), e.call()))
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.clip_text = true
		var cnt := UI.spin(s.count, 1, 9999, func(v): s.count = maxi(1, v), 90)
		sp.add_child(UI.hbox([sy, nb, upgrade_picker(s), cnt, UI.button("✕", func(): sd.stacks.remove_at(k); render(), "Small")], 6))
		sp.add_child(mount_row(sd, s))
	box.add_child(UI.panel(sp))
	# hero
	var hc: Dictionary = sd.hero
	var hp := UI.vbox([], 6)
	var head := UI.flow([UI.check("", hc.enabled, func(v): hc.enabled = v; render()), UI.h3("Commander")], 8)
	if hc.enabled:
		var cls := []
		for k in D.CLASSES: cls.append([k, D.CLASSES[k].name])
		head.add_child(UI.option(cls, hc.cls, func(v):
			hc.cls = v
			hc.stats = (D.CFG.heroStart[v] as Dictionary).duplicate()
			hc.skills = (D.CLASSES[v].skills as Dictionary).duplicate()
			render()))
		var hn := LineEdit.new()
		hn.placeholder_text = "name"
		hn.text = hc.name
		hn.custom_minimum_size.x = 120
		hn.text_changed.connect(func(t): hc.name = t)
		head.add_child(hn)
	hp.add_child(head)
	if hc.enabled:
		var dl := UI.label(D.CLASSES[hc.cls].desc, "muted", 12)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hp.add_child(dl)
		var stats := UI.flow([], 10)
		for k in D.PRIMARY:
			var sl := UI.label({"attack": "Atk", "defence": "Def", "power": "Pow"}.get(k, k.capitalize()), "muted")
			var sbx := UI.spin(int(hc.stats[k]), 0, 99, func(v): hc.stats[k] = v; render(), 70)
			var pair := UI.hbox([sl, sbx], 4)
			UI.tip(sl, Heroes.PRIMARY_TEXT[k])
			UI.tip(sbx, Heroes.PRIMARY_TEXT[k])
			stats.add_child(pair)
		hp.add_child(stats)
		var fake := {"cls": hc.cls, "skills": hc.skills, "artifacts": hc.artifacts, "stats": hc.stats}
		var cost := Heroes.equipped_cost(fake, hc.equipped)
		var know := Heroes.stat(fake, "knowledge")
		var sprow := UI.flow([UI.label("Spells", "muted"), UI.chip("%d/%d knowledge" % [cost, know], "warn" if (cost > know and hc.equipped.size() > 1) else "", "Knowledge used / knowledge. You may always equip any one spell.")], 6)
		for j in hc.equipped.size():
			var id: String = hc.equipped[j]
			var bt := UI.button(D.SPELLS[id].name + "  ✕", func(): hc.equipped.remove_at(j); render(), "Small", D.SPELLS[id].desc)
			sprow.add_child(bt)
		var sp_items := [["", "+ equip…"]]
		for k in D.SPELLS: sp_items.append([k, "%s (%d)" % [D.SPELLS[k].name, Heroes.spell_cost(fake, k)]])
		sprow.add_child(UI.option(sp_items, "", func(v):
			if v != "":
				hc.equipped.append(v)
				render()))
		hp.add_child(sprow)
		var skrow := UI.flow([UI.label("Skills", "muted")], 8)
		for k in D.SKILLS:
			var S: Dictionary = D.SKILLS[k]
			var items := [[0, "–"]]
			for n in S.tiers.size(): items.append([n + 1, "I".repeat(n + 1)])
			var tp := "[b]%s[/b]" % S.name
			for n in S.tiers.size(): tp += "\n%s: %s" % ["I".repeat(n + 1), S.tiers[n]]
			var lb := UI.label(S.name, "", 12)
			UI.tip(lb, tp)
			skrow.add_child(UI.hbox([lb, UI.option(items, hc.skills.get(k, 0), func(v):
				hc.skills[k] = int(v)
				if k == "sorcery" and int(v) == 3 and hc.skills.get("arcana", 0) == 3: hc.skills.arcana = 2
				if k == "arcana" and int(v) == 3 and hc.skills.get("sorcery", 0) == 3: hc.skills.sorcery = 2
				render())], 2))
		hp.add_child(skrow)
		var arrow := UI.flow([UI.label("Artifacts", "muted")], 8)
		for a in D.ARTIFACTS:
			var c := UI.check(D.ARTIFACTS[a].name, hc.artifacts.has(a), func(v):
				if v: hc.artifacts.append(a)
				else: hc.artifacts.erase(a)
				render())
			c.add_theme_font_size_override("font_size", 12)
			UI.tip(c, D.ARTIFACTS[a].desc)
			arrow.add_child(c)
		hp.add_child(arrow)
	box.add_child(UI.panel(hp))
	return box

## disable a start button while the setup is invalid, and say why on hover
func _gated(bt: Button) -> Button:
	var err := setup_problem()
	if err != "":
		bt.disabled = true
		UI.tip(bt, UI.col("Can't start yet:", "bad") + "\n" + U.esc(err))
	return bt

## the variant a path/level combination gives (null if that combination doesn't exist)
## path: "" melee, "r" ranged, "m" magi · level: 0 base, 1 first upgrade, 2 second upgrade
func _variant(f: String, tier: int, path: String, level: int):
	if level == 0: return Units.key(f, tier, 0, "")
	if tier == 4 and (path == "r" or level > 1): return null
	if path == "m" and level > 1: return null
	return Units.key(f, tier, level, path)

## area 1: upgrade path (Melee / Ranged / Magi) · area 2: upgrade level (– / I / II)
## part 0 = the creature itself (or the rider), part 1 = its mount
func upgrade_picker(s: Dictionary, part: int = 0) -> Control:
	var parts: PackedStringArray = s.key.split("@")
	var p := Units.parse(parts[part])
	var join := func(k: String) -> String:
		if part == 1: return parts[0] + "@" + k
		return k + (("@" + parts[1]) if parts.size() > 1 else "")
	var apply := func(k: String):
		s.key = join.call(k)
		render()
	var paths := UI.hbox([], 2)
	for pp in [["", "Melee"], ["r", "Ranged"], ["m", "Magi"]]:
		var lvl: int = maxi(1, p.up)
		if pp[0] == "m": lvl = 1
		var k = _variant(p.faction, p.tier, pp[0], lvl)
		var on: bool = p.up > 0 and p.mod == pp[0]
		var bt := UI.button(pp[1], func(): apply.call(k), "SmallSel" if on else "Small")
		if k == null:
			bt.disabled = true
			UI.tip(bt, "No %s path for tier %d" % [pp[1].to_lower(), p.tier])
		else:
			UI.tip(bt, UI.unit_tip(Units.resolve(join.call(k))))
		paths.add_child(bt)
	var levels := UI.hbox([], 2)
	for lv in [[0, "–"], [1, "I"], [2, "II"]]:
		var path: String = p.mod if p.up > 0 else ""
		var k = _variant(p.faction, p.tier, path, lv[0])
		var bt := UI.button(lv[1], func(): apply.call(k), "SmallSel" if p.up == lv[0] else "Small")
		bt.custom_minimum_size.x = 30
		if k == null:
			bt.disabled = true
			UI.tip(bt, "No second upgrade for this creature")
		else:
			UI.tip(bt, UI.unit_tip(Units.resolve(join.call(k))))
		levels.add_child(bt)
	return UI.hbox([levels, paths], 10)   # level (– I II) first, then the path

## unit picker modal: all variants, optionally mounted
## the little "↳ Riding: ..." line under a stack row
func mount_row(sd: Dictionary, s: Dictionary) -> Control:
	var parts: PackedStringArray = s.key.split("@")
	var ind := Control.new()
	ind.custom_minimum_size.x = 34
	var lbl := UI.label("↳ Riding", "muted", 12)
	var kids: Array = [ind, lbl]
	if parts.size() > 1:
		var md := Units.resolve(parts[1])
		var mp := Units.parse(parts[1])
		var mname: String = Units.resolve(Units.key(mp.faction, mp.tier, 0, "")).name
		var R := Units.resolve(parts[0])
		var per := int(ceil(float(R.w) / md.s))
		var mb := UI.button(mname, func(): pick_unit(sd, s, "mount"), "Small", UI.unit_tip(md, "\n" + UI.col("Mounts per rider: %d · click to change" % per, "muted")))
		mb.custom_minimum_size.x = 150
		mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		kids.append(UI.sym(md, 20))
		kids.append(mb)
		kids.append(upgrade_picker(s, 1))
		kids.append(UI.label("%d per rider" % per, "muted", 12))
		kids.append(UI.spacer())
		kids.append(UI.button("✕", func():
			var old_n := default_count(s.key)
			s.key = parts[0]
			var new_n := default_count(s.key)
			if new_n != old_n: s.count = new_n
			render(), "Small", "Dismount: back on foot"))
	else:
		var fb := UI.button("On foot", func(): pick_unit(sd, s, "mount"), "Small", "Click to put this stack on mounts (any creature can ride any creature: mounts needed = rider weight ÷ mount strength, rounded up)")
		fb.custom_minimum_size.x = 150
		fb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		kids.append(fb)
	return UI.hbox(kids, 6)

func pick_unit(sd: Dictionary, s: Dictionary, step: String = "rider") -> void:
	# state lives in a dictionary: lambdas capture locals by value
	var st := {"rider": s.key.split("@")[0], "mount": s.key.split("@")[1] if "@" in s.key else null, "step": step}
	var finish := func():
		var old_n := default_count(s.key)
		s.key = st.rider + "@" + st.mount if st.mount != null else st.rider
		var new_n := default_count(s.key)
		if new_n != old_n: s.count = new_n
		UI.close_modal()
		render()
	var draw := [null]
	draw[0] = func():
		var box := UI.vbox([UI.h2("Choose unit" if st.step == "rider" else "Choose mount")], 6)
		if st.step == "mount":
			box.add_child(UI.label("Rider: %s. Mounts needed = rider weight ÷ mount strength (rounded up)." % Units.resolve(st.rider).name, "muted"))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		var cur_part: String = st.rider if st.step == "rider" else (st.mount if st.mount != null else "")
		var cp = Units.parse(cur_part) if cur_part != "" else null
		for f in D.FACTION_IDS:
			var fl := UI.label(D.FACTIONS[f].name)
			fl.add_theme_color_override("font_color", Color(D.FACTIONS[f].color))
			fl.add_theme_font_override("font", UI.font_head)
			fl.custom_minimum_size.x = 64
			grid.add_child(fl)
			for t in range(1, 5):
				var k: String = carry_upgrade(cur_part, f, t)
				var d := Units.resolve(k)
				var extra := ""
				if st.step == "mount":
					var R := Units.resolve(st.rider)
					extra = "\nMounts per rider: %d" % int(ceil(float(R.w) / d.s))
				var here: bool = cp != null and cp.faction == f and cp.tier == t
				var base_name: String = Units.resolve(Units.key(f, t, 0, "")).name
				var bt := UI.button(base_name, func():
					if st.step == "rider": st.rider = k
					else: st.mount = k
					finish.call(), "SmallSel" if here else "Small", UI.unit_tip(d, extra))
				bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
				bt.custom_minimum_size.x = 150
				bt.clip_text = true
				grid.add_child(UI.hbox([UI.sym(d, 26), bt], 3))
		box.add_child(grid)
		if st.step == "rider":
			box.add_child(UI.label("Pick the upgrade path and level with the buttons on the army row.", "muted", 12))
		var bottom := UI.hbox([])
		if st.step == "mount":
			bottom.add_child(UI.button("On foot (no mount)", func():
				st.mount = null
				finish.call(), "SmallSel" if st.mount == null else "Small"))
		bottom.add_child(UI.spacer())
		bottom.add_child(UI.button("Close", UI.close_modal))
		box.add_child(bottom)
		UI.modal(box, false, 600)
	draw[0].call()

## the same upgrade (path + level) on another creature, falling back when it has no such upgrade
func carry_upgrade(cur_part: String, f: String, tier: int) -> String:
	if cur_part == "":
		return Units.key(f, tier, 0, "")
	var p := Units.parse(cur_part)
	for opt in [[p.mod, p.up], ["", p.up], ["", mini(p.up, 1)], ["", 0]]:
		var k = _variant(f, tier, opt[0], opt[1])
		if k != null: return k
	return Units.key(f, tier, 0, "")
