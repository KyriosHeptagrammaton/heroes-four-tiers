# ============================================================================
# Game — controller: new game, hotseat turns, walking, sites, battles, saves.
# Flows that wait on the player (dialogs, handoffs) are coroutines (await).
# ============================================================================
extends Node

var state = null
var rng := Rng.new(1)
const PCOLORS := ["#e8b33c", "#43b5e8"]

func W(): return UI.screen("world")
func T(): return UI.screen("town")

# ---------------------------------------------------------------- new game
func new_game_dialog() -> void:
	var cfg := {"names": ["Player 1", "Player 2"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": randi() % 1000000 + 1, "metals": true}
	var box := UI.vbox([UI.h2("New hotseat game"), UI.label("Two players share this computer and take turns. The map is hidden between turns.", "muted")])
	var fac := []
	for f in D.FACTION_IDS: fac.append([f, D.FACTIONS[f].name])
	var cls := []
	for c in D.CLASSES: cls.append([c, D.CLASSES[c].name])
	for p in 2:
		var dot := UI.label("●")
		dot.add_theme_color_override("font_color", Color(PCOLORS[p]))
		var nm := LineEdit.new()
		nm.text = cfg.names[p]
		nm.custom_minimum_size.x = 140
		nm.text_changed.connect(func(t): cfg.names[p] = t)
		box.add_child(UI.panel(UI.flow([dot, nm, UI.label("Faction", "muted"), UI.option(fac, cfg.factions[p], func(v): cfg.factions[p] = v),
			UI.label("Hero", "muted"), UI.option(cls, cfg.cls[p], func(v): cfg.cls[p] = v)], 8)))
	box.add_child(UI.hbox([UI.label("Map seed", "muted"), UI.spin(cfg.seed, 1, 999999999, func(v): cfg.seed = maxi(1, v), 130)]))
	var mt := UI.check("Three metals: copper, silver and gold", true, func(v): cfg.metals = v)
	UI.tip(mt, "On: towns make copper, which buys tier 1 creatures, buildings and everything else. Tier 2 creatures cost silver and tiers 3-4 cost gold — dig them from guarded Silver and Gold Mines. You start with 1250 copper and 750 silver.\nOff: one currency, gold, buys everything.")
	box.add_child(mt)
	box.add_child(UI.row_end([UI.button("Cancel", UI.close_modal), UI.button("Start", func():
		if cfg.factions[0] == cfg.factions[1]:
			UI.toast("Pick two different factions")
			return
		UI.close_modal()
		new_game(cfg), "Primary")]))
	UI.modal(box, false, 560)

func new_game(cfg: Dictionary) -> void:
	var gen := WorldGen.generate(cfg.seed, {"factions": cfg.factions, "metals": cfg.get("metals", true)})
	rng = Rng.new(cfg.seed * 7 + 13)
	var N: int = gen.map.cards.size()
	var metals: bool = cfg.get("metals", true)
	var S := {"v": 1, "metals": metals, "seed": cfg.seed, "day": 1, "cur": 0, "map": gen.map, "center": gen.center, "winner": null, "log": [], "towns": {}, "heroes": {}, "players": []}
	for p in 2:
		var seen := []; seen.resize(N); seen.fill(0)
		var tm := []; tm.resize(N); tm.fill(0)
		S.players.append({"name": cfg.names[p], "faction": cfg.factions[p], "color": PCOLORS[p], "gold": D.CFG.metals.start.gold if metals else D.CFG.startGold, "silver": D.CFG.metals.start.silver if metals else 0, "aurum": D.CFG.metals.start.aurum if metals else 0, "essence": {"1": 0, "2": 0, "3": 0, "4": 0}, "alive": true,
			"seen": seen, "tmask": tm, "seenSub": {}, "trans": {"cards": gen.trans[p], "spent": [], "links": [], "lines": [], "active": null}, "invest": 0, "grail": false, "skipMove": {}, "capital": null})
	state = S
	World.reset_cache()
	for t in gen.towns:
		t.built = {"dwell1": true, "walls": t.capital}
		t.pool = {"1": 0, "2": 0, "3": 0, "4": 0}
		t.extra = {"1": 0, "2": 0, "3": 0, "4": 0}
		t.garrison = []
		t.builtToday = false
		for k in range(1, 5): t.pool[str(k)] = World.growth(t, k)
		if t.owner < 0:
			var a := WorldGen.monster_army(rng, 2, 1.0)
			t.garrison = a.stacks.map(func(s): return {"key": s.key, "count": s.count, "splits": 1, "name": ""})
			t.built.dwell2 = true
			t.built.up1_1 = true
		else:
			S.players[t.owner].capital = t.id
		S.towns[t.id] = t
	for p in 2:
		spawn_hero(p, cfg.cls[p], S.towns[S.players[p].capital], true)
	for p in 2: World.compute_visible(p)
	World.log_msg("A new world takes shape.")
	W().reset_view()
	handoff(0)

func spawn_hero(p: int, cls: String, town: Dictionary, starter: bool) -> Dictionary:
	var f: String = state.players[p].faction
	var h := Heroes.create(cls, f, null, rng)
	h.id = _next_hero_id()
	h.merge({"owner": p, "pos": {"c": town.c, "x": town.x, "y": town.y}, "alive": true, "visited": {}, "train": {"state": "with", "at": null, "wounded": []}, "mp": 0}, true)
	if starter:
		h.army = [{"key": Units.key(f, 1, 0, ""), "count": 12, "splits": 2, "name": ""}, {"key": Units.key(f, 2, 0, ""), "count": 3, "splits": 1, "name": ""}]
	else:
		h.army = [{"key": Units.key(f, 1, 0, ""), "count": 6, "splits": 1, "name": ""}]
	h.mp = World.mp_max(h)
	state.heroes[h.id] = h
	return h

func _next_hero_id() -> String:
	var n: int = state.get("heroSeq", 0) + 1
	state.heroSeq = n
	return "h%d" % n

# ---------------------------------------------------------------- turns
## Show the pass-the-computer screen; returns when the player clicks.
func handoff_wait(p: int, text: String = "", button_label: String = "Continue") -> void:
	var S = state
	var P: Dictionary = S.players[p]
	var el: Control = UI.screen("handoff")
	UI.clear(el)
	var w := Waiter.new()
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	el.add_child(cc)
	var box := UI.vbox([], 10)
	cc.add_child(box)
	var sig := UI.label("♛", "", 64)
	sig.add_theme_color_override("font_color", Color(P.color))
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sig)
	var nm := UI.h1(P.name, Color(P.color))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(nm)
	var week: int = (S.day - 1) / 7 + 1
	var dow: int = (S.day - 1) % 7 + 1
	var tx := UI.label(text if text != "" else "Day %d, week %d. Pass the computer to %s." % [dow, week, P.name], "muted")
	tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size.x = 520
	box.add_child(tx)
	var bt := UI.button(button_label, func(): w.done.emit(true), "BigPrimary")
	bt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bt)
	UI.close_modal()
	UI.show("handoff")
	if UI.autopilot:
		await get_tree().process_frame
		return
	await w.done

func handoff(p: int) -> void:
	await handoff_wait(p, "", "I am %s — show my lands" % state.players[p].name)
	begin_turn()

func begin_turn() -> void:
	World.compute_visible(state.cur)
	W().enter()
	check_skill_choices()

func resume() -> void:
	if state == null: return
	if state.winner != null:
		victory(state.winner)
		return
	handoff(state.cur)

func check_skill_choices() -> void:
	for hr in World.heroes_of(state.cur):
		if Heroes.maybe_offer_skill(hr, rng) != null:
			await ArmyUI.skill_choice(hr.id)
			check_skill_choices()
			return

func end_turn_confirm() -> void:
	var left := World.heroes_of(state.cur).filter(func(h): return h.mp > 0)
	if left.size():
		var names := ", ".join(left.map(func(h): return h.name))
		if not await UI.confirm("%s still %s movement. End turn?" % [names, "have" if left.size() > 1 else "has"]):
			return
	end_turn()

func end_turn() -> void:
	var S = state
	var nxt: int = S.cur
	var wrapped := false
	while true:
		nxt = (nxt + 1) % S.players.size()
		if nxt == 0: wrapped = true
		if S.players[nxt].alive or nxt == S.cur: break
	if wrapped:
		if World.new_day(): World.log_msg("A new week begins: creatures muster in every town.")
	S.cur = nxt
	autosave()
	handoff(S.cur)

# ---------------------------------------------------------------- walking
func walk(hero: Dictionary, path: Array) -> void:
	var ws = W()
	if hero.mp <= 0:
		UI.toast("No movement left today")
		return
	ws.anim = true
	var P: Dictionary = state.players[hero.owner]
	var msg := ""
	while true:
		if path.is_empty(): break
		if hero.mp <= 0:
			msg = "Out of movement for today"
			break
		var n: Dictionary = path[0]
		var why = World.enterable(hero, n, P)
		if why == "stop":
			path.clear()
			_walk_done(path, "")
			interact(hero, n)
			return
		if why != null:
			path.clear()
			msg = why
			break
		path.pop_front()
		var ev = World.step(hero, n)
		ws.redraw()
		var o = World.obj_at(n.c, n.x, n.y)
		if o != null and not o.has("guard") and D.OBJ.has(o.type) and not o.type in ["monster", "town"] and (not o.get("hidden", false) or World.sub_seen(P, n.c, n.x, n.y)):
			path.clear()
			_walk_done(path, "")
			site(hero, o)
			return
		if ev != null and ev.type in ["transStart", "jump", "transEnd"]:
			path.clear()
			_walk_done(path, "")
			if ev.type == "transStart":
				UI.alert("✧ Transcendent zone", "The land shimmers. A distant part of the world has been lifted and laid beside you: [b]the next edge you cross from this card leads there[/b]. A glowing line will record your path; you can always walk it back.")
			if ev.type == "jump":
				ws.center_on_sel()
				UI.toast("You emerge in a far corner of the world…", 3.0)
			return
		if path.size():
			var w2 = World.enterable(hero, path[0], P)
			if w2 != null and w2 != "stop":
				msg = w2
				path.clear()
				break
		await get_tree().create_timer(0.07).timeout
	_walk_done(path, msg)

func _walk_done(path: Array, msg: String) -> void:
	var ws = W()
	ws.anim = false
	ws.path = path if path.size() else null
	ws.render_side()
	ws.redraw()
	if msg != "": UI.toast(msg)

func interact(hero: Dictionary, n: Dictionary) -> void:
	var S = state
	if hero.mp < 1:
		UI.toast("Not enough movement")
		return
	var o = World.obj_at(n.c, n.x, n.y)
	var oh = World.hero_at(n.c, n.x, n.y, hero)
	if oh != null:
		if oh.owner == hero.owner:
			ArmyUI.exchange(hero.id, oh.id)
			return
		var is_town: bool = o != null and o.type == "town"
		battle(hero, {"kind": "town" if is_town else "hero", "hero": oh, "town": S.towns[o.town] if is_town else null, "node": n})
		return
	if o != null and o.type == "town":
		var t: Dictionary = S.towns[o.town]
		if t.owner == hero.owner:
			World.step(hero, n)
			enter_town(hero, t)
			return
		if t.garrison.size():
			battle(hero, {"kind": "town", "town": t, "node": n})
			return
		World.step(hero, n)
		capture(hero, t)
		return
	if o != null and o.type == "monster":
		battle(hero, {"kind": "monster", "obj": o, "node": n})
		return
	if o != null and o.has("guard"):
		battle(hero, {"kind": "guard", "obj": o, "node": n})
		return
	World.step(hero, n)
	if o != null: site(hero, o)
	W().render_side(); W().redraw()

func enter_town(hero: Dictionary, t: Dictionary) -> void:
	var n := World.heal_in_town(hero)
	if n: UI.toast("%d wounded creatures rejoin %s" % [n, hero.name])
	W().render_side(); W().redraw()
	T().open(t.id, hero.id)

func capture(hero: Dictionary, t: Dictionary, lines = null) -> void:
	var S = state
	var old: int = t.owner
	t.owner = hero.owner
	t.garrison = []
	World.log_msg("%s captures %s!" % [hero.name, t.name])
	if old >= 0 and S.players[old].capital == t.id:
		state.winner = hero.owner
		autosave()
		victory(hero.owner)
		return
	W().render_side(); W().redraw()
	if lines != null: lines.append("%s now flies your banner." % t.name)
	else: UI.alert("Town captured", "%s now flies your banner." % U.esc(t.name))

func park_train(hero: Dictionary) -> void:
	hero.train.state = "parked"
	hero.train.at = {"c": hero.pos.c, "x": hero.pos.x, "y": hero.pos.y}
	UI.toast("Train parked. You may leave the road; your troops fight at -1 morale and suffer attrition until you return.", 4.2)
	W().render_side(); W().redraw()

# ---------------------------------------------------------------- sites
func site(hero: Dictionary, o: Dictionary) -> void:
	var P: Dictionary = state.players[hero.owner]
	var remove := func():
		var cd := World.card(hero.pos.c)
		cd.objs = cd.objs.filter(func(x): return x != o)
	var done := func(): W().render_side(); W().redraw()
	match o.type:
		"chest":
			var i := await UI.pick_cards("◆ Treasure trove", "Take the gold, or study the maps and journals inside?",
				["[b]%s[/b]" % World.cost_str(o.gold), "[b]%d experience[/b]\n[color=#a39f94]in a primary skill of your choice[/color]" % o.xp])
			if i == 0:
				P.gold += o.gold
			else:
				await pick_primary(hero, o.xp)
			remove.call(); done.call()
			return
		"buried":
			P.gold += o.gold; remove.call(); done.call()
			UI.alert("✕ Buried treasure", "You dig up %s." % World.cost_str(o.gold))
			return
		"artifact":
			hero.artifacts.append(o.art); remove.call(); done.call()
			UI.alert("✧ " + D.ARTIFACTS[o.art].name, D.ARTIFACTS[o.art].desc)
			return
		"shrine":
			if hero.spellbook.has(o.spell):
				UI.toast("%s already knows %s" % [hero.name, D.SPELLS[o.spell].name])
				done.call(); return
			hero.spellbook.append(o.spell); done.call()
			UI.alert("✦ Spell shrine", "%s learns [b]%s[/b]: %s\n%s" % [U.esc(hero.name), D.SPELLS[o.spell].name, D.SPELLS[o.spell].desc, UI.col("Equip it from the Hero screen.", "muted")])
			return
		"hermit":
			if hero.visited.get(o.id, false):
				UI.toast("The hermit has nothing more to teach you"); return
			hero.visited[o.id] = true
			hero.xp[o.stat] += o.amount
			var lg := []
			Heroes.apply_primary_levels(hero, rng, lg)
			done.call()
			UI.alert("☥ Wise hermit", "+%d %s experience.%s" % [o.amount, o.stat, ("\n" + "\n".join(lg)) if lg.size() else ""])
			return
		"academy":
			if hero.visited.get(o.id, false):
				UI.toast("You have studied here already"); return
			var opts := []
			for k in D.SKILLS:
				opts.append({"label": D.SKILLS[k].name, "tip": "\n".join(D.SKILLS[k].tiers)})
			var i := await UI.choose("⌂ Academy", "Study one secondary skill (+%d experience):" % (o.amount * 2), opts)
			var k: String = D.SKILLS.keys()[i]
			hero.visited[o.id] = true
			hero.skillXp[k] += o.amount * 2
			done.call()
			check_skill_choices()
			return
		"tower":
			var n := World.reveal_radius(hero.owner, hero.pos.c, U.jr(5 * D.CFG.sightScale))
			World.scout_xp(hero, n)
			UI.toast("From the tower you survey the land.")
			done.call(); return
		"fairy", "knight":
			var d := Units.resolve(o.join.key)
			if not Army.can_add(hero.army, o.join.key):
				UI.alert(D.OBJ[o.type].name, "%d %s would join, but your army has no room." % [o.join.count, d.name])
				return
			Army.add(hero.army, o.join.key, o.join.count)
			remove.call(); done.call()
			UI.alert(D.OBJ[o.type].name, "%d %s join your army." % [o.join.count, d.name])
			return
		"mercs", "post", "font", "mine":
			use_site(hero, o)
			return
		"cache":
			P.essence[str(o.essence.tier)] += o.essence.n
			remove.call(); done.call()
			UI.alert("⬡ Essence cache", "+%d tier-%d upgrade essence." % [o.essence.n, o.essence.tier])
			return
		"forget":
			if hero.visited.get(o.id, false): return
			hero.visited[o.id] = true
			for k in hero.skillXp: hero.skillXp[k] = 0
			hero.stats.knowledge += 2
			done.call()
			UI.alert("☁ Forest of Forgetting", "Your secondary skill experience fades away… but something else takes root: +2 knowledge.")
			return
		"grail":
			remove.call()
			P.grail = true
			for k in D.PRIMARY: hero.stats[k] += 1
			done.call()
			UI.alert("♆ The Holy Grail", "%s claims the Grail: +1 to every primary skill, and %s gains %s every week." % [U.esc(hero.name), U.esc(P.name), World.cost_str(1000)])
			return
	done.call()

func use_site(hero: Dictionary, o: Dictionary) -> void:
	var S = state
	var P: Dictionary = S.players[hero.owner]
	var done := func(): W().render_side(); W().redraw()
	match o.type:
		"mine":
			var M: Dictionary = D.MINES[o.kind]
			if o.owner == hero.owner:
				UI.toast("%s: yours (+%s/day)" % [World.mine_name(o.kind), World.cost_str(M.income, World.mine_metal(o.kind))]); return
			if o.owner >= 0:
				World.log_msg("%s raids %s's %s." % [hero.name, S.players[o.owner].name, World.mine_name(o.kind)])
				o.owner = -1
			done.call()
			if await UI.confirm("%s: pay %s to survey and claim it (+%s per day)?" % [World.mine_name(o.kind), World.cost_str(M.cost), World.cost_str(M.income, World.mine_metal(o.kind))]):
				if P.gold < M.cost:
					UI.toast("Not enough " + World.metal_name("gold")); return
				P.gold -= M.cost
				o.owner = hero.owner
				World.log_msg("%s claims a %s." % [hero.name, World.mine_name(o.kind)])
				done.call()
		"mercs":
			if o.get("hired", false):
				UI.toast("The camp is empty"); return
			var d := Units.resolve(o.join.key)
			var box := UI.vbox([UI.h2("♞ Mercenary camp"), UI.hbox([UI.sym(d, 36), UI.rich("%d × [b]%s[/b]\nfor %s" % [o.join.count, U.esc(d.name), World.cost_str(o.price)])]),
				UI.panel(UI.rich(UI.unit_tip(d), 12))])
			box.add_child(UI.row_end([UI.button("Leave", UI.close_modal), UI.button("Hire", func():
				if P.gold < o.price:
					UI.toast("Not enough " + World.metal_name("gold")); return
				if not Army.can_add(hero.army, o.join.key):
					UI.toast("No room in your army"); return
				P.gold -= o.price
				Army.add(hero.army, o.join.key, o.join.count)
				o.hired = true
				UI.close_modal()
				done.call(), "Primary")]))
			UI.modal(box, false, 420)
		"post":
			T().remote_recruit(hero.id)
		"font":
			T().upgrade_modal(hero.id, "", true)

func pick_primary(hero: Dictionary, xp: int) -> void:
	var opts := D.PRIMARY.map(func(k): return {"label": k.capitalize()})
	var i := await UI.choose("+%d experience" % xp, "Choose the primary skill that gains it:", opts)
	hero.xp[D.PRIMARY[i]] += xp
	var lg := []
	Heroes.apply_primary_levels(hero, rng, lg)
	if lg.size():
		await UI.alert("Level up", "\n".join(lg))

# ---------------------------------------------------------------- battles
func tag(stacks: Array, p: String) -> Array:
	for s in stacks: s.uid = p + str(s.uid)
	return stacks

func def_info(tgt: Dictionary) -> Dictionary:
	var S = state
	if tgt.kind == "monster" or tgt.kind == "guard":
		var a: Dictionary = tgt.obj.army if tgt.kind == "monster" else tgt.obj.guard
		var st := []
		for i in a.stacks.size():
			st.append({"key": a.stacks[i].key, "count": a.stacks[i].count, "uid": "M%d" % i})
		return {"owner": -1, "name": "Neutral creatures" if tgt.kind == "monster" else "Guardians", "hero": null, "stacks": st, "neutral": true, "faction": a.faction}
	if tgt.kind == "hero":
		var h: Dictionary = tgt.hero
		return {"owner": h.owner, "name": S.players[h.owner].name + " – " + h.name, "hero": h, "stacks": Army.battle_stacks(h.army, "H"), "faction": h.faction, "neutral": false}
	var t: Dictionary = tgt.town
	var oh = tgt.get("hero")
	if oh == null: oh = World.hero_at(t.c, t.x, t.y)
	var stacks := Army.battle_stacks(t.garrison, "T")
	if oh != null: stacks = Army.battle_stacks(oh.army, "H") + stacks
	stacks = stacks.slice(0, D.CFG.maxStacks)
	return {"owner": t.owner, "name": (S.players[t.owner].name + " – " + t.name) if t.owner >= 0 else t.name + " garrison", "hero": oh, "stacks": stacks, "neutral": t.owner < 0, "faction": t.faction, "town": t}

func ground_choices(tgt: Dictionary) -> Array:
	var c: int = tgt.node.c
	var out := []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := World.cx(c) + dx
			var y := World.cy(c) + dy
			if x < 0 or y < 0 or x >= World.W() or y >= World.H(): continue
			var t: String = World.card(y * World.W() + x).t
			if t == "chasm" or t == "town": continue
			if not out.has(t): out.append(t)
	if out.is_empty(): out.append("field")
	return out

func ai_ground(choices: Array) -> String:
	var score := {"canyon": 5, "hill": 4, "escarpment": 4, "mountain": 4, "bluffs": 3, "watchfort": 3, "village": 3, "forest": 2, "swamp": 2, "moor": 1}
	var best: String = choices[0]
	for c in choices:
		if score.get(c, 0) > score.get(best, 0): best = c
	return best

func battle(hero: Dictionary, tgt: Dictionary) -> void:
	var S = state
	var info := def_info(tgt)
	var me: Dictionary = S.players[hero.owner]
	var ground: String
	var ignored := false
	if tgt.kind == "town":
		ground = "town" if info.town.built.get("walls", false) else ai_ground(ground_choices(tgt))
	elif info.owner < 0:
		ground = ai_ground(ground_choices(tgt))
	else:
		# human defender picks ground (hotseat: pass the computer)
		var choices := ground_choices(tgt)
		var def: Dictionary = S.players[info.owner]
		await handoff_wait(info.owner, "%s's %s is attacking your %s! Choose your ground." % [me.name, hero.name, info.hero.name if info.hero != null else "army"])
		var opts := choices.map(func(t): return {"label": D.TERRAIN[t].name, "desc": D.TERRAIN[t].desc})
		opts.append({"label": "Ignore the attack", "desc": "1-3 of your stacks start slow", "variant": "Danger"})
		var i := await UI.choose("%s: choose your ground" % def.name, UI.col("Pick the battlefield from the card you stand on or any card around it — or ignore the attack.", "muted"), opts, "", 520)
		if i < choices.size():
			ground = choices[i]
			await handoff_wait(hero.owner, "%s chose to fight on %s." % [def.name, D.TERRAIN[ground].name])
		else:
			ignored = true
			ground = World.card(tgt.node.c).t
			await handoff_wait(hero.owner, "%s ignores the attack." % def.name)
	# attacker chooses the time (or feints)
	W().enter(false)
	var defenders := ", ".join(info.stacks.map(func(s): return "%s %s" % [W().count_word(s.count), Units.resolve(s.key).name]))
	var TT: Dictionary = D.TERRAIN[ground]
	var text := "Ground: [b]%s[/b] — %s%s\n\nDefenders: %s\n\n%s" % [TT.name, UI.col(TT.desc, "muted"), ("\n" + UI.col("The defender ignored your attack: 1-3 of their stacks start slow.", "good")) if ignored else "", U.esc(defenders), UI.col("Choose the time of your attack:", "muted")]
	var topts := []
	for t in D.TIMES: topts.append({"label": D.TIMES[t].name, "desc": D.TIMES[t].desc})
	topts.append({"label": "Feint (do not attack)", "variant": "Danger"})
	var ti := await UI.choose("Attack " + info.name, text, topts, "", 520)
	if ti >= D.TIMES.size():
		hero.mp = maxi(0, hero.mp - 1)
		if not ignored and info.owner >= 0 and info.hero != null:
			S.players[info.owner].skipMove[info.hero.id] = true
			World.log_msg("%s feints; %s wasted their preparations." % [hero.name, info.hero.name])
		W().enter()
		return
	launch(hero, tgt, info, ground, D.TIMES.keys()[ti], ignored)

func launch(hero: Dictionary, tgt: Dictionary, info: Dictionary, ground: String, time: String, ignored: bool) -> void:
	var S = state
	var weather := "rain" if rng.next() < D.CFG.rainChance else "clear"
	field_upgrade(hero)
	if info.hero != null: field_upgrade(info.hero)
	var b := Battle.new({
		"seed": rng.rint(1, 1000000000), "terrain": ground, "time": time, "weather": weather, "ignoredAttack": ignored,
		"sides": [
			{"name": S.players[hero.owner].name + " – " + hero.name, "hero": hero, "stacks": Army.battle_stacks(hero.army, "H"), "faction": hero.faction, "trainless": World.trainless(hero)},
			{"name": info.name, "hero": info.hero, "stacks": info.stacks, "faction": info.faction, "ai": info.owner < 0, "neutral": info.owner < 0, "trainless": World.trainless(info.hero) if info.hero != null else false},
		]})
	UI.screen("battle").start(b, func(bb): resolve(bb, hero, tgt, info))

func field_upgrade(hero: Dictionary) -> void:
	if Heroes.skill(hero, "fieldcraft") < 2: return
	var P: Dictionary = state.players[hero.owner]
	for g in hero.army:
		if "@" in g.key: continue
		var p := Units.parse(g.key)
		if p.up != 0 or p.tier > 3: continue
		var ok := false
		for t in World.towns_of(hero.owner):
			if t.built.get("up1_%d" % p.tier, false) and t.faction == p.faction: ok = true
		if not ok: continue
		if P.essence[str(p.tier)] >= g.count:
			P.essence[str(p.tier)] -= g.count
			g.key = Units.key(p.faction, p.tier, 1, "")
			World.log_msg("%s's %d creatures upgrade in the field." % [hero.name, g.count])

func part(side_sum: Dictionary, prefix: String) -> Array:
	var out := []
	for s in side_sum.stacks:
		if s.uid != null and str(s.uid).begins_with(prefix):
			var c: Dictionary = s.duplicate()
			c.uid = str(s.uid).substr(1)
			out.append(c)
	return out

func resolve(b: Battle, hero: Dictionary, tgt: Dictionary, info: Dictionary) -> void:
	var S = state
	var o: Dictionary = b.over
	var sm := b.summary()
	var lines := []
	var a_won: bool = o.winner == 0
	var d_won: bool = o.winner == 1
	var a_alive := b.stacks_of(0).size() > 0
	var d_alive := b.stacks_of(1).size() > 0
	# casualties
	var wa := World.apply_casualties(hero.owner, hero.army, part(sm[0], "H"), a_alive, hero)
	if wa.size(): lines.append("%s: %d wounded ride in the supply train." % [hero.name, U.sum(wa.map(func(w): return w.count))])
	var dh = info.hero
	if dh != null:
		var w := World.apply_casualties(dh.owner, dh.army, part(sm[1], "H"), d_alive, dh)
		if w.size(): lines.append("%s: %d wounded." % [dh.name, U.sum(w.map(func(x): return x.count))])
	if tgt.kind == "town":
		World.apply_casualties(info.town.owner, info.town.garrison, part(sm[1], "T"), d_alive, null)
	if tgt.kind == "monster" or tgt.kind == "guard":
		var army: Dictionary = tgt.obj.army if tgt.kind == "monster" else tgt.obj.guard
		var ns := []
		for i in army.stacks.size():
			var surv := 0
			for x in sm[1].stacks:
				if x.uid == "M%d" % i: surv = x.survivors
			if surv > 0: ns.append({"key": army.stacks[i].key, "count": surv})
		army.stacks = ns
	# xp & essence
	lines.append_array(World.hero_xp(hero, b.sides[0], o.get("fled") == 1, a_won, dh, b.round_n))
	if dh != null:
		lines.append_array(World.hero_xp(dh, b.sides[1], o.get("fled") == 0, d_won, hero, b.round_n))
	var win = 0 if a_won else (1 if d_won else null)
	var win_owner: int = hero.owner if win == 0 else (info.owner if win == 1 else -1)
	if win_owner >= 0:
		var P: Dictionary = S.players[win_owner]
		var k: Dictionary = b.sides[win].st.killsByTier
		var ess := []
		for t in range(1, 5):
			if k.get(t, 0):
				P.essence[str(t)] += k[t]
				ess.append("%d×T%d" % [k[t], t])
		if ess.size(): lines.append("%s gains upgrade essence: %s." % [P.name, ", ".join(ess)])
	# commander deaths
	if sm[0].heroGone == "dead":
		kill_hero(hero, dh)
		lines.append("%s fell beside the tier-4 creatures." % hero.name)
	if dh != null and sm[1].heroGone == "dead":
		kill_hero(dh, hero)
		lines.append("%s fell beside the tier-4 creatures." % dh.name)
	# outcomes
	var n: Dictionary = tgt.node
	if a_won:
		if tgt.kind == "monster":
			var cd := World.card(n.c)
			cd.objs = cd.objs.filter(func(x): return x != tgt.obj)
			lines.append("The creatures flee the area." if o.reason == "fled" else "The creatures are destroyed.")
		if tgt.kind == "guard":
			tgt.obj.erase("guard")
		if dh != null and dh.alive:
			if o.reason == "fled":
				retreat_hero(dh, hero, lines)
			else:
				kill_hero(dh, hero)
				lines.append("%s is defeated. %s takes their spell book." % [dh.name, hero.name])
		if tgt.kind == "town": info.town.garrison = []
		if hero.alive and hero.army.size():
			World.step(hero, n)
			if tgt.kind == "town":
				capture(hero, info.town, lines)
				if S.winner != null: return
			if tgt.kind == "guard":
				await after_report(lines)
				site(hero, tgt.obj)
				return
	elif d_won:
		if hero.alive:
			if o.reason == "fled":
				hero.mp = 0
				lines.append("%s retreats." % hero.name)
				if dh != null and Heroes.skill(dh, "spellthief") >= 1: take_book(dh, hero)
			else:
				kill_hero(hero, dh)
				lines.append("%s is defeated." % hero.name)
	else:
		hero.mp = 0
		lines.append("Neither side can make headway; the armies disengage.")
	if hero.alive and hero.army.is_empty():
		kill_hero(hero, dh)
		lines.append("%s has no army left and leaves the field for good." % hero.name)
	check_elimination()
	await after_report(lines)

func after_report(lines: Array) -> void:
	World.compute_visible(state.cur)
	W().enter()
	if state.winner != null: return
	await UI.alert("After the battle", "\n".join(lines.map(func(l): return U.esc(l))))
	check_skill_choices()

func take_book(winner: Dictionary, loser: Dictionary) -> void:
	for s in loser.spellbook:
		if not winner.spellbook.has(s): winner.spellbook.append(s)

func kill_hero(loser: Dictionary, winner) -> void:
	var S = state
	if not loser.alive: return
	loser.alive = false
	if winner != null and winner.alive:
		take_book(winner, loser)
		winner.artifacts.append_array(loser.artifacts)
		loser.artifacts = []
	var P: Dictionary = S.players[loser.owner]
	if P.trans.active != null and P.trans.active.hero == loser.id:
		P.trans.lines.append(P.trans.active.line)
		P.trans.active = null
	if loser.army.size():
		var ts := World.towns_of(loser.owner)
		if ts.size() and winner == null:
			for g in loser.army: Army.add(ts[0].garrison, g.key, g.count)
	World.log_msg("%s is gone." % loser.name)

func retreat_hero(loser: Dictionary, winner, lines: Array) -> void:
	var t = null
	for x in World.towns_of(loser.owner):
		if World.hero_at(x.c, x.x, x.y, loser) == null:
			t = x; break
	if winner != null and Heroes.skill(winner, "spellthief") >= 1:
		take_book(winner, loser)
		lines.append("%s copies %s's spell book." % [winner.name, loser.name])
	if t != null:
		loser.pos = {"c": t.c, "x": t.x, "y": t.y}
		loser.mp = 0
		lines.append("%s retreats to %s." % [loser.name, t.name])
	else:
		kill_hero(loser, winner)
		lines.append("%s has nowhere to retreat and is lost." % loser.name)

func check_elimination() -> void:
	var S = state
	for p in S.players.size():
		var P: Dictionary = S.players[p]
		if not P.alive: continue
		if World.heroes_of(p).is_empty() and World.towns_of(p).is_empty():
			P.alive = false
			World.log_msg("%s has been eliminated." % P.name)
	var alive := []
	for p in S.players.size():
		if S.players[p].alive: alive.append(p)
	if alive.size() == 1:
		S.winner = alive[0]
		victory(S.winner)

func victory(p: int) -> void:
	var P: Dictionary = state.players[p]
	await handoff_wait(p, "%s is victorious! Day %d." % [P.name, state.day], "Main menu")
	state = null
	Main.menu()

# ---------------------------------------------------------------- saves
## Saves live in a "saves" folder next to the program (or in the user folder
## when that is not writable, e.g. when run from the editor).
func save_dir() -> String:
	var d := OS.get_executable_path().get_base_dir().path_join("saves")
	if OS.has_feature("editor") or DirAccess.make_dir_recursive_absolute(d) != OK:
		d = ProjectSettings.globalize_path("user://saves")
		DirAccess.make_dir_recursive_absolute(d)
	return d

func serialize() -> String:
	state.rngState = rng.get_state()
	return JSON.stringify(state)

func save(name: String) -> bool:
	var f := FileAccess.open(save_dir().path_join(name + ".json"), FileAccess.WRITE)
	if f == null: return false
	f.store_string(serialize())
	f.close()
	return true

func autosave() -> void:
	save("autosave")

func list_saves() -> Array:
	var out := []
	var d := save_dir()
	var da := DirAccess.open(d)
	if da == null: return out
	for fn in da.get_files():
		if fn.ends_with(".json"):
			out.append({"name": fn.get_basename(), "time": FileAccess.get_modified_time(d.path_join(fn))})
	out.sort_custom(func(a, b): return a.time > b.time)
	return out

func load_save(name: String) -> bool:
	var txt := FileAccess.get_file_as_string(save_dir().path_join(name + ".json"))
	if txt == "":
		UI.toast("Could not load " + name)
		return false
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		UI.toast("Could not read " + name)
		return false
	state = D._ints(parsed)
	rng = Rng.new(1)
	rng.set_state(int(state.get("rngState", 1)))
	World.reset_cache()
	W().reset_view()
	resume()
	return true

func save_dialog() -> void:
	var v = await UI.prompt("Save game as", "Day %d" % state.day)
	if v == null or v == "": return
	var clean := ""
	for ch in v:
		if ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-.": clean += ch
	UI.toast("Saved" if save(clean) else "Save failed")

func load_dialog() -> void:
	var lst := list_saves()
	var box := UI.vbox([UI.h2("Load game")])
	if lst.is_empty():
		box.add_child(UI.label("No saved games yet.", "muted"))
	for s in lst:
		var dt := Time.get_datetime_string_from_unix_time(s.time + int(Time.get_time_zone_from_system().bias) * 60, true)
		var bt := UI.button("%s     %s" % [s.name, dt], func(): UI.close_modal(); load_save(s.name))
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(bt)
	box.add_child(UI.label("Saves live in: " + save_dir(), "muted", 12))
	box.add_child(UI.row_end([UI.button("Close", UI.close_modal)]))
	UI.modal(box, false, 420)
