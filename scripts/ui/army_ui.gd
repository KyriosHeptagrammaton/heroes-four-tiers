# ============================================================================
# ArmyUI — army management (split/merge stacks, riders, transfers), hero
# exchange, hero screen and the secondary-skill choice.
# ============================================================================
extends Node

func group_row(groups: Array, gi: int, opts: Dictionary) -> Control:
	var g: Dictionary = groups[gi]
	var d := Units.resolve(g.key)
	var divs := Army.divisors(g.count).filter(func(k): return k - int(g.get("splits", 1)) + Army.stacks(groups) <= D.CFG.maxStacks)
	var items := divs.map(func(k): return [k, "1 stack" if k == 1 else "%d stacks of %d" % [k, g.count / k]])
	var sel := UI.option(items, g.splits, func(v):
		g.splits = int(v)
		opts.redraw.call())
	UI.tip(sel, "Doc: all stacks of the same creature must be the same size, so a group can only split into equal stacks.")
	var sy := UI.sym(d, 30)
	UI.tip(sy, UI.unit_tip(d, "", opts.get("eff", {})))
	var nm := UI.rich("[b]%d[/b] %s%s\n%s" % [g.count, U.esc(g.name if g.get("name", "") != "" else d.name), UI.col(" ⚑", "flag") if d.placeholder else "", UI.col("%s T%d%s" % [D.FACTIONS[d.faction].name, d.tier, " · mounted" if d.mounted else ""], "muted")], 13)
	nm.custom_minimum_size.x = 170
	var row := UI.hbox([sy, nm, sel], 6)
	row.add_child(UI.button("✎", func():
		var v = await UI.prompt("Name", g.name if g.get("name", "") != "" else d.name)
		if v != null:
			g.name = v
		opts.redraw.call(), "Small", "Rename this group"))
	if d.mounted:
		row.add_child(UI.button("Dismount", func():
			Army.dismount(groups, gi)
			opts.redraw.call(), "Small"))
	if opts.get("transfer") != null:
		row.add_child(UI.button(opts.transfer_label, func(): opts.transfer.call(gi), "Small", "Move creatures"))
	if opts.get("can_dismiss", false):
		row.add_child(UI.button("✕", func():
			if await UI.confirm("Dismiss %d %s?" % [g.count, d.name]):
				groups.remove_at(gi)
			opts.redraw.call(), "SmallDanger", "Dismiss"))
	return row

func mount_panel(groups: Array, redraw: Callable) -> Control:
	var cands := []
	for i in groups.size():
		if not Units.resolve(groups[i].key).mounted: cands.append(i)
	if cands.size() < 2:
		return UI.label("Riders: need two different unmounted groups.", "muted", 12)
	var st := {"r": cands[0], "m": cands[1], "n": 1}
	var info := UI.label("", "muted", 12)
	var upd := func():
		if st.r == st.m:
			info.text = "pick two different groups"
			return
		var R := Units.resolve(groups[st.r].key)
		var M := Units.resolve(groups[st.m].key)
		var per := int(ceil(float(R.w) / M.s))
		var mx := mini(groups[st.r].count, int(floor(float(groups[st.m].count) / per)))
		info.text = "%d mount(s) per rider · up to %d" % [per, mx]
		UI.tip(info, UI.unit_tip(Units.resolve(groups[st.r].key + "@" + groups[st.m].key)))
	var items := cands.map(func(i): return [i, "%d %s" % [groups[i].count, Units.resolve(groups[i].key).name]])
	var o1 := UI.option(items, st.r, func(v):
		st.r = int(v)
		upd.call())
	var o2 := UI.option(items, st.m, func(v):
		st.m = int(v)
		upd.call())
	var num := UI.spin(1, 1, 9999, func(v): st.n = maxi(1, v), 80)
	upd.call()
	return UI.flow([UI.label("Mount"), o1, UI.label("on"), o2, UI.label("×"), num, info, UI.button("Mount", func():
		if st.r == st.m: return
		var err = Army.mount(groups, st.r, st.m, st.n)
		if err != null: UI.toast(err)
		redraw.call(), "Small")], 6)

func move_units(from: Array, to: Array, gi: int) -> bool:
	var g: Dictionary = from[gi]
	var v = await UI.prompt("Move how many %s? (max %d)" % [Units.resolve(g.key).name, g.count], str(g.count))
	if v == null: return false
	var n := clampi(int(v) if str(v).is_valid_int() else 0, 0, g.count)
	if n == 0: return false
	if not Army.can_add(to, g.key):
		UI.toast("No free stack slot there")
		return false
	g.count -= n
	Army.add(to, g.key, n, g.get("name", ""))
	if g.count <= 0: from.remove_at(gi)
	else: Army.normalize(g)
	return true

func _column(title: String, groups: Array, other, dir_label: String, redraw: Callable, on_move: Callable, can_dismiss: bool = true, hero = null) -> Control:
	var eff := Army.eff_by_group(groups, hero, World.trainless(hero) if hero != null else false)
	var c := UI.vbox([UI.hbox([UI.h3(title), UI.spacer(), UI.label("%d/%d stacks" % [Army.stacks(groups), D.CFG.maxStacks], "muted")])], 4)
	for gi in groups.size():
		var tr = null
		if other != null:
			tr = func(i):
				if await on_move.call():
					if await move_units(groups, other, i): pass
				redraw.call()
		c.add_child(group_row(groups, gi, {"redraw": redraw, "can_dismiss": can_dismiss, "transfer": tr, "transfer_label": dir_label, "eff": eff[gi] if gi < eff.size() else {}}))
		c.add_child(UI.sep_line())
	if groups.is_empty(): c.add_child(UI.label("Empty", "muted"))
	c.add_child(mount_panel(groups, redraw))
	var p := UI.panel(c)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

## hero army (+ town garrison if t_id)
func army_screen(h_id: String, t_id: String, on_close: Callable) -> void:
	var S = Game.state
	var hero = World.hero(h_id) if h_id != "" else null
	var t = S.towns[t_id] if t_id != "" else null
	var draw := [null]
	var ask := func() -> bool:
		if hero != null and hero.mp > 0:
			if not await UI.confirm("Doc rule: exchanging units ends the hero's movement for today. Continue?"):
				draw[0].call()
				return false
		if hero != null: hero.mp = 0
		return true
	draw[0] = func():
		var cols := UI.hbox([], 16)
		if hero != null: cols.add_child(_column("♛ " + hero.name, hero.army, t.garrison if t != null else null, "→ town", draw[0], ask, true, hero))
		if t != null: cols.add_child(_column("♜ %s garrison" % t.name, t.garrison, hero.army if hero != null else null, "→ hero", draw[0], ask))
		var box := UI.vbox([UI.h2("Armies"), cols])
		if hero != null and Heroes.skill(hero, "fieldcraft") >= 1 and t == null:
			box.add_child(UI.button("Upgrade in the field (Fieldcraft)", func(): UI.screen("town").upgrade_modal(hero.id, ""), "Small"))
		box.add_child(UI.row_end([UI.button("Done", func():
			UI.close_modal()
			UI.screen("world").render_side()
			if on_close.is_valid(): on_close.call(), "Primary")]))
		UI.modal(box, false, 760)
	draw[0].call()

func exchange(h1: String, h2: String) -> void:
	var A = World.hero(h1)
	var B = World.hero(h2)
	var draw := [null]
	var ask := func() -> bool:
		A.mp = 0
		B.mp = 0
		return true
	draw[0] = func():
		var cols := UI.hbox([], 16)
		cols.add_child(_column("♛ " + A.name, A.army, B.army, "→ " + B.name, draw[0], ask, false, A))
		cols.add_child(_column("♛ " + B.name, B.army, A.army, "→ " + A.name, draw[0], ask, false, B))
		UI.modal(UI.vbox([UI.h2("Exchange"), UI.label("Doc rule: both heroes lose all movement when they exchange units.", "muted"), cols,
			UI.row_end([UI.button("Done", func():
				UI.close_modal()
				UI.screen("world").render_side(), "Primary")])]), false, 760)
	draw[0].call()

func hero_screen(h_id: String) -> void:
	var hero = World.hero(h_id)
	var draw := [null]
	var all_skills := [false]   # secondary skills: learned only, or every skill's progress
	draw[0] = func():
		var box := UI.vbox([], 8)
		var title := UI.h2("♛ " + hero.name)
		UI.tip(title, "Click to rename")
		title.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				var v = await UI.prompt("Rename hero", hero.name)
				if v != null and v != "":
					hero.name = v
				draw[0].call())
		box.add_child(UI.hbox([title, UI.spacer(), UI.label("%s · %s" % [D.CLASSES[hero.cls].name, D.FACTIONS[hero.faction].name], "muted")]))
		box.add_child(UI.rich(UI.col(D.CLASSES[hero.cls].desc + " Primary skills grow by use: each level costs 3× (skilled ★) or 4× (unskilled) the next level in experience.", "muted"), 12))
		var how := {"attack": "killing enemy creatures (tier each)", "defence": "losing creatures to damage (tier each)", "courage": "starting a battle at ≤0 courage; your creatures deserting", "initiative": "rounds where your hero does not act first", "power": "casting spells", "knowledge": "+3 when your spells fill your knowledge; +3 per spell when you run out"}
		var pt := GridContainer.new()
		pt.columns = 4
		pt.add_theme_constant_override("h_separation", 16)
		for hd in ["Primary", "Level", "Experience", "Earned by"]: pt.add_child(UI.label(hd, "muted", 12))
		for k in D.PRIMARY:
			var sk: bool = D.CLASSES[hero.cls].skilled.has(k)
			pt.add_child(UI.tip(UI.label(("★ " if sk else "") + k), Heroes.PRIMARY_TEXT[k]))
			pt.add_child(UI.label(Heroes.init_str(Heroes.stat(hero, k)) if k == "initiative" else str(Heroes.stat(hero, k))))
			pt.add_child(UI.label("%s / %d" % [U.fmt(hero.xp[k]), Heroes.primary_cost(hero, k)]))
			pt.add_child(UI.label(how[k], "muted", 12))
		box.add_child(pt)
		# secondary skills (shown below the spells)
		var sec := UI.vbox([], 8)
		if not D.CLASSES[hero.cls].get("noSecondary", false):
			var known: Array = D.SKILLS.keys().filter(func(k): return Heroes.skill(hero, k) > 0)
			var shown: Array = D.SKILLS.keys() if all_skills[0] else known
			sec.add_child(UI.hbox([UI.h3("Secondary skills"), UI.spacer(), UI.button("Show learned only" if all_skills[0] else "Show all skills' progress", func():
				all_skills[0] = not all_skills[0]
				draw[0].call(), "Small", "All skills gather XP by use. When two or more are ready you choose one; the other loses XP equal to its cost. Every skill you know makes the others cost more.")]))
			if shown.is_empty():
				sec.add_child(UI.label("No secondary skills learned yet.", "muted", 12))
			var st := GridContainer.new()
			st.columns = 4
			st.add_theme_constant_override("h_separation", 16)
			if shown.size():
				for hd in ["Skill", "Tier", "XP / next", "Next tier"]: st.add_child(UI.label(hd, "muted", 12))
			for k in shown:
				var S: Dictionary = D.SKILLS[k]
				var tier := Heroes.skill(hero, k)
				var maxed := Heroes.skill_maxed(hero, k)
				var tp := ""
				for i in S.tiers.size(): tp += ("\n" if i else "") + "%s: %s" % ["I".repeat(i + 1), S.tiers[i]]
				var nl := UI.rich("%s %s" % [S.name, UI.col("(%s)" % S.cat, "muted")], 13)
				nl.custom_minimum_size.x = 170
				UI.tip(nl, tp)
				st.add_child(nl)
				st.add_child(UI.label("I".repeat(tier) if tier else "–"))
				st.add_child(UI.label("max" if maxed else "%s / %d" % [U.fmt(hero.skillXp.get(k, 0)), Heroes.skill_cost(hero, k)]))
				var nx := UI.label("" if maxed else S.tiers[tier], "muted", 12)
				nx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nx.custom_minimum_size.x = 260
				st.add_child(nx)
			sec.add_child(st)
			if hero.pendingSkillChoice != null:
				sec.add_child(UI.button("★ Choose a new skill", func():
					await skill_choice(hero.id)
					draw[0].call(), "Primary"))
		# spells
		var know := Heroes.stat(hero, "knowledge")
		var cost := Heroes.equipped_cost(hero, hero.equipped)
		var sp := UI.vbox([UI.hbox([UI.h3("Spells"), UI.spacer(), UI.chip("Knowledge %d / %d" % [cost, know], "warn" if (cost > know and hero.equipped.size() > 1) else "")]),
			UI.rich(UI.col("Equip spells up to your knowledge (copies allowed; any single spell is always allowed). Casts per round: %s; uses per copy per battle: %s. Spells refresh after every battle." % [U.fmt(Heroes.casts_per_round(hero)), U.fmt(Heroes.uses_per_spell(hero))], "muted"), 12)], 6)
		var can_swap := World.can_swap_spells(hero)
		if not can_swap:
			sp.add_child(UI.rich(UI.col("Spells can only be changed in one of your towns or at a ◈ Ley stone.", "bad"), 12))
		var eq := UI.flow([_bold("Equipped:")], 4)
		for i in hero.equipped.size():
			var id: String = hero.equipped[i]
			var xb := UI.button("%s (%d)  ✕" % [D.SPELLS[id].name, Heroes.spell_cost(hero, id)], func():
				hero.equipped.remove_at(i)
				draw[0].call(), "Small", D.SPELLS[id].desc)
			xb.disabled = not can_swap
			eq.add_child(xb)
		sp.add_child(eq)
		var book := UI.flow([_bold("Spellbook:")], 4)
		for id in hero.spellbook:
			var nxt: Array = hero.equipped.duplicate()
			nxt.append(id)
			var bt := UI.button("+ " + D.SPELLS[id].name, func():
				hero.equipped.append(id)
				draw[0].call(), "Small", "[b]%s[/b] (%s) cost %d\n%s" % [D.SPELLS[id].name, D.SPELLS[id].kind, Heroes.spell_cost(hero, id), D.SPELLS[id].desc])
			bt.disabled = not can_swap or not Heroes.can_equip(hero, nxt)
			book.add_child(bt)
		sp.add_child(book)
		box.add_child(UI.panel(sp))
		box.add_child(sec)
		if hero.artifacts.size():
			var ar := UI.vbox([UI.h3("Artifacts")], 4)
			for a in hero.artifacts:
				ar.add_child(UI.rich("[b][color=#f0d68e]%s[/color][/b] — %s" % [D.ARTIFACTS[a].name, D.ARTIFACTS[a].desc], 13))
			box.add_child(UI.panel(ar))
		box.add_child(UI.row_end([UI.button("Close", func():
			UI.close_modal()
			UI.screen("world").render_side(), "Primary")]))
		UI.modal(box, false, 720)
	draw[0].call()

func _bold(t: String) -> Label:
	var l := UI.label(t)
	l.add_theme_font_override("font", UI.font_bold)
	return l

func skill_choice(h_id: String) -> void:
	var hero = World.hero(h_id)
	var pair = hero.pendingSkillChoice if hero.pendingSkillChoice != null else Heroes.maybe_offer_skill(hero, Game.rng)
	if pair == null: return
	var cards := []
	for k in pair:
		var S: Dictionary = D.SKILLS[k]
		var nxt := Heroes.skill(hero, k)
		cards.append("[b][color=#f0d68e]%s %s[/color][/b]\n%s\n%s" % [S.name, "I".repeat(nxt + 1), S.tiers[nxt], UI.col("cost %d XP" % Heroes.skill_cost(hero, k), "muted")])
	var i := await UI.pick_cards("%s: a new skill" % hero.name, UI.col("Two skills are ready. Choose one — the other loses experience equal to the cost of the one you take.", "muted"), cards, 540)
	Heroes.choose_skill(hero, pair[i])
	UI.screen("world").render_side()
