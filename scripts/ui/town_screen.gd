# ============================================================================
# Town screen, recruiting (incl. remote recruiting posts) and upgrades.
# ============================================================================
extends Control

var tid := ""
var hid := ""

func open(t_id: String, h_id: String = "") -> void:
	tid = t_id
	hid = h_id if h_id != null else ""
	UI.show("town")
	render()

func close() -> void:
	UI.screen("world").enter(false)

func _card(kids: Array, built: bool = false) -> PanelContainer:
	var st := UI.stone("panel").margins(10)
	st.fill = Color("#342e26")
	st.trim = Color("#6cc07a", 0.7) if built else Color("#5c4a2a")
	var p := UI.panel(UI.vbox(kids, 4), st)
	p.custom_minimum_size.x = 260
	return p

func _t(text: String) -> Label:
	var l := UI.label(text, "gold2")
	l.add_theme_font_override("font", UI.font_bold)
	return l

func _desc(text: String) -> Label:
	var l := UI.label(text, "muted", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 230
	return l

func render() -> void:
	UI.clear(self)
	var S = Game.state
	var t: Dictionary = S.towns[tid]
	var P: Dictionary = S.players[S.cur]
	var hero = World.hero(hid) if hid != "" else null
	var in_town: bool = hero != null and hero.pos.c == t.c and hero.pos.x == t.x and hero.pos.y == t.y
	var root := UI.vbox([], 0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := UI.h2(("♛ " if t.capital else "♜ ") + t.name)
	UI.tip(title, "Click to rename")
	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var v = await UI.prompt("Rename town", t.name)
			if v != null and v != "":
				t.name = v
				render())
	var fchip := UI.chip(D.FACTIONS[t.faction].name)
	fchip.get_child(0).add_theme_color_override("font_color", Color(D.FACTIONS[t.faction].color))
	var bar := UI.hbox([UI.button("◂ Map", close), title, fchip, UI.chip("Capital", "warn", "If this town falls, you lose the game.") if t.capital else null, UI.spacer(),
		UI.rich("● [b][color=#f0d68e]%s[/color][/b]   %s" % [U.fmt(P.gold), UI.col("   ".join([1, 2, 3, 4].map(func(k): return "⬡%d %s" % [k, P.essence[str(k)]])), "muted")], 14)], 10)
	bar.get_child(bar.get_child_count() - 1).custom_minimum_size.x = 300
	root.add_child(UI.panel(bar, UI.stone("bar")))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	sc.add_child(m)
	var body := UI.vbox([], 10)
	m.add_child(body)
	# visiting hero line
	var gar := ", ".join(t.garrison.map(func(g): return "%d %s" % [g.count, U.esc(g.name if g.get("name", "") != "" else Units.resolve(g.key).name)]))
	var vis := UI.flow([UI.rich(("Visiting hero: " + UI.b(UI.col(U.esc(hero.name), "gold2"))) if in_town else UI.col("No hero in town — recruits go to the garrison.", "muted")),
		UI.rich(UI.col("Garrison: ", "muted") + (gar if gar != "" else UI.col("empty", "muted"))),
		UI.button("Manage armies", func(): ArmyUI.army_screen(hero.id if in_town else "", t.id, render), "Small"),
		UI.button("Upgrade creatures" if in_town else "Upgrade garrison", func(): upgrade_modal(hero.id if in_town else "", t.id), "Small")], 10)
	for k in vis.get_children():
		if k is RichTextLabel: k.custom_minimum_size.x = 300
	body.add_child(UI.panel(vis))
	# recruit
	var grid := UI.flow([], 10)
	for tier in range(1, 5):
		var bk := "dwell%d" % tier
		var d := Units.resolve(Units.key(t.faction, tier, 0, ""))
		var nm := _t(d.name)
		UI.tip(nm, UI.unit_tip(d))
		var head := UI.hbox([UI.sym(d, 32), UI.vbox([nm, UI.label("Tier %d · base %d gold · growth %d/week" % [tier, U.jr(D.CFG.unitPrice[str(tier)] * Units.price_mult(t.faction, tier)), World.growth(t, tier)], "muted", 12)], 0)])
		if not t.built.get(bk, false):
			grid.add_child(_card([head, UI.label("Build the dwelling first.", "muted", 12)]))
			continue
		var price := UI.label("", "muted")
		var st := {"n": maxi(1, t.pool[str(tier)])}
		var upd := func(): price.text = "%d gold" % World.price_for(t, tier, st.n)
		var sp := UI.spin(st.n, 1, 999, func(v):
			st.n = maxi(1, v)
			upd.call(), 80)
		upd.call()
		var buy := func(dest: String):
			var n: int = st.n
			var cost := World.price_for(t, tier, n)
			if P.gold < cost:
				UI.toast("Not enough gold"); return
			var army: Array = hero.army if dest == "hero" else t.garrison
			if not Army.can_add(army, d.key):
				UI.toast("No free stack slot"); return
			P.gold -= cost
			World.buy(t, tier, n)
			Army.add(army, d.key, n)
			UI.toast("Recruited %d %s" % [n, d.name])
			render()
		var row := UI.flow([sp, price], 6)
		if in_town: row.add_child(UI.button("→ Hero", func(): buy.call("hero"), "SmallPrimary"))
		row.add_child(UI.button("→ Garrison", func(): buy.call("garrison"), "Small"))
		grid.add_child(_card([head, UI.label("At base price: %d" % t.pool[str(tier)]), row], true))
	body.add_child(UI.panel(UI.vbox([UI.h3("Recruit"), _wide(_desc("The weekly muster is sold at the base price. You may keep buying beyond it: the next week-sized batch costs ×2, then ×3, and so on. Prices reset each week.")), grid])))
	# buildings
	var bgrid := UI.flow([], 10)
	for k in D.BUILDINGS:
		var B: Dictionary = D.BUILDINGS[k]
		if k == "up1_4" and not t.built.get("dwell4", false) and not t.built.get("dwell3", false): continue
		var built: bool = t.built.get(k, false)
		var req_ok := true
		for r in B.req:
			if not t.built.get(r, false): req_ok = false
		var pth := ""
		if k.begins_with("up2_"):
			pth = " (ranged II)" if D.SECOND_UPGRADE[t.faction][k.substr(4)] == "r" else " (melee II)"
		var kids := [_t(B.name + pth), _desc(B.desc)]
		if built:
			kids.append(UI.label("✓ Built", "good"))
		else:
			var bb := UI.button("Build · %d" % B.cost, func():
				P.gold -= B.cost
				t.built[k] = true
				t.builtToday = true
				render(), "Small")
			bb.disabled = t.builtToday or not req_ok or P.gold < B.cost
			var row := UI.hbox([bb])
			if not req_ok:
				row.add_child(UI.label("needs " + ", ".join(B.req.map(func(r): return D.BUILDINGS[r].name if D.BUILDINGS.has(r) else r)), "muted", 12))
			kids.append(row)
		bgrid.add_child(_card(kids, built))
	body.add_child(UI.panel(UI.vbox([UI.h3("Build " + ("(already built today)" if t.builtToday else "(one per day)")), bgrid])))
	# treasury / tavern / wagons
	var misc := UI.flow([], 10)
	var inv := UI.button("Invest 300", func():
		P.gold -= 300
		P.invest += 100
		render(), "Small")
	inv.disabled = P.gold < 300
	misc.add_child(_card([_t("Treasury"), _desc("\"A wise king invests in his town: 3 gold now for 1 gold forever.\" Invest 300 gold for +100 gold every week."), UI.hbox([UI.label("Weekly return: %d" % P.invest), inv])]))
	var occupied = World.hero_at(t.c, t.x, t.y)
	var tav := UI.flow([], 4)
	for c in D.CLASSES:
		var hb := UI.button(D.CLASSES[c].name, func():
			P.gold -= D.CFG.heroCost
			var nh := Game.spawn_hero(S.cur, c, t, false)
			nh.faction = t.faction
			nh.army = [{"key": Units.key(t.faction, 1, 0, ""), "count": 6, "splits": 1, "name": ""}]
			World.compute_visible(S.cur)
			UI.screen("world").sel_hero = nh.id
			hid = nh.id
			UI.toast("%s joins you" % nh.name)
			render(), "Small", D.CLASSES[c].desc + ("\n[b]A hero is already standing in town.[/b]" if occupied != null else ""))
		hb.disabled = P.gold < D.CFG.heroCost or occupied != null
		tav.add_child(hb)
	misc.add_child(_card([_t("Tavern"), _desc("Hire a new hero (%d gold). They arrive with a few recruits and a supply train." % D.CFG.heroCost), tav]))
	if in_town and (hero.train == null or hero.train.state == "none"):
		var wb := UI.button("Buy supply train · %d" % D.CFG.trainCost, func():
			P.gold -= D.CFG.trainCost
			hero.train = {"state": "with", "at": null, "wounded": []}
			render(), "Small")
		wb.disabled = P.gold < D.CFG.trainCost
		misc.add_child(_card([_t("Wagon works"), _desc("Your hero has no supply train."), wb]))
	body.add_child(misc)

func _wide(c: Control) -> Control:
	c.custom_minimum_size.x = 600
	return c

# ---- upgrades (town buildings, or an arcane font when font=true) ---------------------
func upgrade_modal(h_id: String, t_id: String, font: bool = false) -> void:
	var S = Game.state
	var P: Dictionary = S.players[S.cur]
	var hero = World.hero(h_id) if h_id != "" else null
	var t = S.towns[t_id] if t_id != "" else null
	var armies := []
	if hero != null: armies.append({"label": hero.name, "groups": hero.army})
	if t != null and not font: armies.append({"label": t.name + " garrison", "groups": t.garrison})
	var draw := [null]
	draw[0] = func():
		var box := UI.vbox([UI.h2("◎ Arcane font" if font else "Upgrade creatures"),
			UI.rich(UI.col("Cost per creature: 1 essence of its tier + a gold fee. You have %d gold and essence %s." % [P.gold, " ".join([1, 2, 3, 4].map(func(k): return "T%d:%d" % [k, P.essence[str(k)]]))], "muted"))])
		var any := false
		for A in armies:
			box.add_child(UI.h3(A.label))
			for g in A.groups.duplicate():
				var opts := World.upgrade_options(g.key, {"town": t if t != null else any_town_with(g.key, hero), "font": font, "hero": hero})
				if opts.is_empty(): continue
				any = true
				var d := Units.resolve(g.key)
				var row := UI.flow([UI.sym(d, 24), _t("%d %s" % [g.count, d.name]), UI.label("→")], 6)
				for k in opts:
					var nd := Units.resolve(k)
					var cost := World.upgrade_cost(g.key, g.count)
					var can: bool = P.gold >= cost.gold and P.essence[str(cost.tier)] >= cost.essence
					var bt := UI.button(nd.name + (" ⚑" if nd.placeholder else ""), func():
						P.gold -= cost.gold
						P.essence[str(cost.tier)] -= cost.essence
						var ex = null
						for x in A.groups:
							if x.key == k and x != g: ex = x
						if ex != null:
							ex.count += g.count
							A.groups.erase(g)
							Army.normalize(ex)
						else:
							g.key = k
						if hero != null: Heroes.add_skill_xp(hero, "craft", 1)
						draw[0].call()
						UI.screen("world").render_side(), "Small", UI.unit_tip(nd, "\nCost for all %d: %d gold + %d tier-%d essence" % [g.count, cost.gold, cost.essence, cost.tier]))
					bt.disabled = not can
					row.add_child(UI.hbox([UI.sym(nd, 18), bt], 2))
				box.add_child(row)
		if not any:
			box.add_child(UI.label("Only un-upgraded creatures can become Magi." if font else "Nothing can be upgraded here — build drill yards / war colleges / the arcane sanctum first.", "muted"))
		box.add_child(UI.row_end([UI.button("Done", func():
			UI.close_modal()
			if UI.on("town"): render()
			UI.screen("world").render_side(), "Primary")]))
		UI.modal(box, false, 580)
	draw[0].call()

## Fieldcraft I lets heroes upgrade away from town using their towns' buildings
func any_town_with(k: String, hero):
	if hero == null or Heroes.skill(hero, "fieldcraft") < 1: return null
	var f: String = Units.parse(k.split("@")[0]).faction
	for t in World.towns_of(Game.state.cur):
		if t.faction == f: return t
	return null

# ---- recruiting post: buy from own towns while abroad (+25%) ------------------------------
func remote_recruit(h_id: String) -> void:
	var S = Game.state
	var P: Dictionary = S.players[S.cur]
	var hero = World.hero(h_id)
	var draw := [null]
	draw[0] = func():
		var box := UI.vbox([UI.h2("⚑ Recruiting post"), UI.label("Buy creatures from your towns' musters at +25%. They march out to meet you.", "muted")])
		for t in World.towns_of(S.cur):
			box.add_child(UI.h3(t.name))
			for tier in range(1, 5):
				if not t.built.get("dwell%d" % tier, false): continue
				var d := Units.resolve(Units.key(t.faction, tier, 0, ""))
				var row := UI.hbox([UI.sym(d, 22), UI.label("%s (%d at base)" % [d.name, t.pool[str(tier)]]), UI.spacer()])
				for n in [1, 5]:
					var c := World.price_for(t, tier, n, 1.25)
					var bt := UI.button("+%d · %d" % [n, c], func():
						P.gold -= c
						World.buy(t, tier, n)
						Army.add(hero.army, d.key, n)
						draw[0].call()
						UI.screen("world").render_side(), "Small")
					bt.disabled = P.gold < c or not Army.can_add(hero.army, d.key)
					row.add_child(bt)
				box.add_child(row)
		box.add_child(UI.row_end([UI.button("Done", UI.close_modal, "Primary")]))
		UI.modal(box, false, 540)
	draw[0].call()
