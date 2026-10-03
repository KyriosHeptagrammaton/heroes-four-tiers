extends RefCounted
# End-to-end smoke test: two autopiloted players explore, recruit, fight
# monsters and each other, save/load mid-game. Fails loudly on script errors.
var root: Node
var battles := 0
var done := {}

func wait_idle(max_frames: int = 600) -> void:
	var ws = UI.screen("world")
	for i in max_frames:
		await root.get_tree().process_frame
		if UI.cur_screen == "world" and not ws.anim and not UI.modal_open():
			return
	print("!! wait_idle timed out: screen=", UI.cur_screen, " anim=", ws.anim, " modal=", UI.modal_open(), " content=", UI._modal_content)
	if UI._modal_content != null: print("   modal text: ", _texts(UI._modal_content).substr(0, 300))
	UI.close_modal()

func targets(h) -> Array:
	var S = Game.state
	var P = S.players[h.owner]
	var out := []
	for c in S.map.cards.size():
		if not P.seen[c] or World.cheb(c, h.pos.c) > 5: continue
		for o in S.map.cards[c].objs:
			if not World.tile_seen(P, c, o.x, o.y): continue
			if o.get("hidden", false) and not World.sub_seen(P, c, o.x, o.y): continue
			if o.type == "town" and S.towns[o.town].owner == h.owner: continue
			if o.type == "mine" and o.owner == h.owner: continue
			if h.visited.has(o.id) or done.has(o.id): continue
			out.append({"c": c, "x": o.x, "y": o.y})
	for oh in S.heroes.values():
		if oh.alive and oh.owner != h.owner and World.tile_vis(h.owner, oh.pos.c, oh.pos.x, oh.pos.y):
			out.append(oh.pos.duplicate())
	return out

func recruit(p: int) -> void:
	var S = Game.state
	var P = S.players[p]
	if World.heroes_of(p).is_empty() and P.gold >= D.CFG.heroCost:
		var t0 = World.towns_of(p)[0]
		if World.hero_at(t0.c, t0.x, t0.y) == null:
			P.gold -= D.CFG.heroCost
			Game.spawn_hero(p, "paragon", t0, false)
			print("[hire] ", P.name)
	for t in World.towns_of(p):
		var h = World.hero_at(t.c, t.x, t.y)
		for k in ["dwell2", "up1_1", "dwell3", "up1_2"]:
			if not t.builtToday and not t.built.get(k, false) and P.gold >= D.BUILDINGS[k].cost + 400:
				var ok := true
				for r in D.BUILDINGS[k].req:
					if not t.built.get(r, false): ok = false
				if ok:
					P.gold -= D.BUILDINGS[k].cost; t.built[k] = true; t.builtToday = true
		for tier in range(1, 4):
			if not t.built.get("dwell%d" % tier, false): continue
			var n: int = t.pool[str(tier)]
			if n <= 0: continue
			var cost := World.price_for(t, tier, n)
			var key := Units.key(t.faction, tier, 0, "")
			var army: Array = h.army if (h != null and h.owner == p) else t.garrison
			if World.can_pay(P, World.tier_metal(tier), cost) and Army.can_add(army, key):
				World.pay(P, World.tier_metal(tier), cost); World.buy(t, tier, n); Army.add(army, key, n)

func run(r) -> void:
	root = r
	UI.autopilot = true
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["gamma", "delta"], "cls": ["warlord", "mage"], "seed": 777})
	await root.get_tree().process_frame
	await wait_idle()
	var ws = UI.screen("world")
	for turn in 70:
		var S = Game.state
		if S == null or S.winner != null: break
		var p: int = S.cur
		print("-- turn ", turn, " day ", S.day, " player ", p, " screen ", UI.cur_screen)
		recruit(p)
		for h in World.heroes_of(p):
			for tries in 6:
				if not h.alive or h.mp <= 0 or Game.state == null: break
				var best = null
				var bl := 1 << 30
				for t in targets(h):
					var pth = World.path(h, t)
					if pth != null and pth.size() < bl:
						bl = pth.size(); best = pth
				if best == null:
					# march on the enemy capital: the explored road tile closest to it
					var goal_c: int = S.towns[S.players[1 - p].capital].c
					var cands := []
					for c in S.map.cards.size():
						if S.players[p].seen[c] and World.cheb(c, h.pos.c) <= 4:
							for rt in WorldGen.road_tiles(World.card(c)):
								if World.tile_seen(S.players[p], c, rt[0], rt[1]):
									cands.append({"c": c, "x": rt[0], "y": rt[1]})
					var gx := World.cx(goal_c) + 0.5
					var gy := World.cy(goal_c) + 0.5
					var dist := func(n): return Vector2(World.cx(n.c) + (n.x + 0.5) / World.card(n.c).size - gx, World.cy(n.c) + (n.y + 0.5) / World.card(n.c).size - gy).length()
					cands.sort_custom(func(a, b): return dist.call(a) < dist.call(b))
					var here: float = dist.call(h.pos)
					for n in cands.slice(0, 40):
						if dist.call(n) >= here: break
						if World.enterable(h, n, S.players[p]) == null:
							best = World.path(h, n)
							if best != null: break
				if best == null:
					break
				var was_battle := false
				ws.sel_hero = h.id
				ws.path = best
				var goal_o = World.obj_at(best[best.size()-1].c, best[best.size()-1].x, best[best.size()-1].y)
				if goal_o != null and goal_o.type in ["post", "font", "mine", "mercs", "shrine", "tower"]: done[goal_o.id] = true
				Game.walk(h, best)
				for i in 30:
					await root.get_tree().process_frame
					if UI.cur_screen == "battle": was_battle = true
				for i in 10:
					await root.get_tree().process_frame
				if UI.modal_open(): UI.close_modal()
				await wait_idle()
				if was_battle: battles += 1
		if turn == 9:
			print("saving + loading at day ", S.day)
			Game.save("smoketest")
			Game.load_save("smoketest")
			await wait_idle()
		if Game.state == null or Game.state.winner != null: break
		Game.end_turn()
		await wait_idle()
	var S = Game.state
	if S == null:
		print("GAME OVER (state cleared)")
	else:
		print("day ", S.day, " winner ", S.winner, " battles ", battles)
		for p in 2:
			var P = S.players[p]
			var hs := World.heroes_of(p)
			print(P.name, ": gold ", P.gold, " silver ", P.get("silver", 0), " aurum ", P.get("aurum", 0), " heroes ", hs.size(), " towns ", World.towns_of(p).size(), " essence ", P.essence,
				" armies ", hs.map(func(h): return Army.value(h.army)))
	print("PLAYTHROUGH DONE")

func _texts(n: Node) -> String:
	var s := ""
	if n is Label or n is Button: s += n.text + " | "
	if n is RichTextLabel: s += n.get_parsed_text() + " | "
	for c in n.get_children(): s += _texts(c)
	return s
