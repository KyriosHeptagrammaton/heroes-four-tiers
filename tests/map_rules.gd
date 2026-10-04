extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true

func army_size(a: Array) -> int:
	var n := 0
	for s in a: n += int(s.count)
	return n

func run(root) -> void:
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42})
	var S = Game.state
	# encounter strength: 2 x 1.15^d
	check(absf(WorldGen.encounter_strength(0) - 2.0) < 0.001 and absf(WorldGen.encounter_strength(10) - 2.0 * pow(1.15, 10)) < 0.001, "encounter strength = 2 x 1.15^cards")
	# ley stones on the map
	var leys := []
	var monsters := []
	for c in S.map.cards.size():
		for o in S.map.cards[c].objs:
			if o.type == "ley": leys.append([c, o])
			if o.type == "monster": monsters.append([c, o])
	check(leys.size() == int(D.CFG.leyStones), "%d ley stones placed" % leys.size())
	# monsters further out are bigger on average (same tier mix aside)
	var near := []; var far := []
	for m in monsters:
		var c: int = m[0]
		var d := 1 << 30
		for st in [[2, 2], [S.map.W - 3, S.map.H - 3]]:
			d = mini(d, maxi(absi(c % S.map.W - st[0]), absi(c / S.map.W - st[1])))
		(near if d <= 5 else far).append(army_size(m[1].army.stacks))
	var avg := func(a: Array) -> float:
		var t := 0.0
		for x in a: t += x
		return t / maxf(1, a.size())
	print("  monster creatures: near avg %.1f (%d), far avg %.1f (%d)" % [avg.call(near), near.size(), avg.call(far), far.size()])
	check(avg.call(far) > avg.call(near), "farther monsters are larger")
	# spells: only in own town or at a ley stone
	var h = World.heroes_of(0)[0]
	check(World.can_swap_spells(h), "hero in its capital may change spells")
	h.pos = {"c": leys[0][0], "x": leys[0][1].x, "y": leys[0][1].y}
	check(World.can_swap_spells(h), "hero on a ley stone may change spells")
	h.pos = {"c": monsters[0][0], "x": 0, "y": 0}
	if World.obj_at(h.pos.c, 0, 0) != null: h.pos.x = 1
	check(not World.can_swap_spells(h), "hero out in the field may not change spells")
	# weekly growth of neutral armies (25%, fractions carried)
	var m0: Dictionary = monsters[0][1].army.stacks[0]
	var before: int = m0.count
	var g_town = null
	for t in S.towns.values():
		if t.owner < 0: g_town = t
	var tb: int = army_size(g_town.garrison)
	for i in 7: World.new_day()
	print("  day now ", S.day, " monster stack ", before, " -> ", m0.count, " neutral town ", tb, " -> ", army_size(g_town.garrison))
	check(m0.count == int(floor(before * 1.25 + 0.000001)), "a monster stack grows 25% at the week's end")
	check(army_size(g_town.garrison) >= int(floor(tb * 1.25)) - g_town.garrison.size(), "neutral town garrison grows too")
	for i in 7: World.new_day()
	check(m0.count == int(floor(before * 1.5625 + 0.000001)), "two weeks: x1.5625 with fractions carried (%d)" % m0.count)
	# calendar chip
	Game.begin_turn()
	for i in 4: await root.get_tree().process_frame
	print("map_rules ", "FAILED" if failed else "OK")
