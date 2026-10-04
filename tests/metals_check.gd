extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true

func mines(kind: String) -> Array:
	var out := []
	for c in Game.state.map.cards:
		for o in c.objs:
			if o.type == "mine" and o.kind == kind: out.append(o)
	return out

func guard_size(o: Dictionary) -> float:
	var v := 0.0
	for s in o.guard.stacks: v += s.count * Units.unit_price(s.key)
	return v

func run(root) -> void:
	Main.boot()
	# classic economy first
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42, "metals": false})
	var P: Dictionary = Game.state.players[0]
	check(P.gold == 2500 and World.tier_metal(3) == "gold" and mines("silver").is_empty(), "metals off: 2500 gold, one currency, no silver mines")
	# default game: three metals
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42})
	P = Game.state.players[0]
	check(Game.state.metals, "three metals is the default")
	check(P.gold == 1250 and P.silver == 750 and P.aurum == 0, "start: 1250 copper, 750 silver, 0 gold")
	check([1, 2, 3, 4].map(func(t): return World.tier_metal(t)) == ["gold", "silver", "aurum", "gems"], "tier metals copper/silver/gold/gems")
	check(P.gems == 0 and World.building_metal("dwell4") == "aurum" and World.building_metal("dwell3") == "silver" and World.building_metal("dwell2") == "gold" and World.building_cost("dwell4") == 400, "tier 4 lair costs gold, other buildings copper; no starting gems")
	var hoards := []
	for c in Game.state.map.cards:
		for o in c.objs:
			if o.type == "gems": hoards.append(o)
	check(hoards.size() == 3 and hoards.all(func(o): return o.has("guard") and o.gems in [6, 8, 10]), "3 guarded Jewel hoards with 6/8/10 gems")
	var t4 = World.towns_of(0)[0]
	check(World.price_for(t4, 4, 1) == 8, "a Titan costs 8 gems (%d)" % World.price_for(t4, 4, 1))
	var uc4 := World.upgrade_cost("beta.4.0.", "beta.4.1.m", 1)
	check(uc4.metal == "gems" and uc4.gold == 4, "Titan -> Magi upgrade: 4 gems (%s)" % uc4)
	check(World.metal_name("gold") == "copper" and World.metal_name("aurum") == "gold", "names: copper and gold")
	var sm := mines("silver")
	var gm := mines("goldmine")
	check(sm.size() == 4 and gm.size() == 2, "map has 4 silver and 2 gold mines (%d, %d)" % [sm.size(), gm.size()])
	var sv := mines("silvervein")
	check(sv.size() == 4 and World.mine_metal("silvervein") == "silver", "map has 4 silver veins producing silver (%d)" % sv.size())
	var gv := mines("goldvein")
	check(gv.size() == 2 and World.mine_metal("goldvein") == "aurum" and World.mine_name("goldvein") == "Gold Vein" and World.mine_name("vein") == "Copper Vein", "map has 2 gold veins producing gold; the old vein reads Copper Vein (%d)" % gv.size())
	print("gold vein guard per level %.0f" % (guard_size(gv[0]) / maxf(1, gv[0].guard.level)))
	print("silver vein guard per level %.0f" % (guard_size(sv[0]) / maxf(1, sv[0].guard.level)))
	var norm := []
	for k in ["timber", "quarry", "vein"]: norm += mines(k)
	var avg := func(a: Array) -> float:
		var t := 0.0
		for o in a: t += guard_size(o) / maxf(1, o.guard.level)
		return t / maxf(1, a.size())
	print("guard value per level: normal %.0f silver %.0f gold %.0f" % [avg.call(norm), avg.call(sm), avg.call(gm)])
	check(avg.call(sm) > avg.call(norm) * 1.8 and avg.call(gm) > avg.call(sm) * 1.8, "silver mines guarded much more than normal, gold mines more again")
	# income
	sm[0].owner = 0; gm[0].owner = 0
	var g0: int = P.gold
	var c0: int = World.income(0, "gold")
	Game.state.day = 2
	World.new_day()
	check(P.silver == 790 and P.aurum == 60 and P.gold == g0 + c0, "a day: +40 silver, +60 gold, town copper (%d, %d, %d)" % [P.silver, P.aurum, P.gold - g0])
	var uc := World.upgrade_cost("alpha.2.0.", "alpha.2.1.", 3)
	check(uc.metal == "silver", "upgrading tier 2 costs silver")
	# town screen buys tier 2 with silver
	var t = World.towns_of(0)[0]
	t.built.dwell2 = true
	var before: int = P.silver
	var cop: int = P.gold
	var price := World.price_for(t, 2, 1)
	World.pay(P, World.tier_metal(2), price)
	check(P.silver == before - price and P.gold == cop, "tier 2 recruit takes silver only")
	Game.begin_turn()
	for i in 6: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/metals_world.png")
	var h = World.heroes_of(0)[0]
	UI.screen("town").open(t.id, h.id)
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/metals_town.png")
	# the build button for the lair names gold
	print("metals_check ", "FAILED" if failed else "OK")
