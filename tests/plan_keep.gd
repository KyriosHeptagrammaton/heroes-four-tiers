extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true
func run(root) -> void:
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42})
	Game.begin_turn()
	for i in 3: await root.get_tree().process_frame
	var ws = UI.screen("world")
	var h = World.hero(ws.sel_hero)
	# find a far tile the hero can path to (longer than today's movement)
	var goal = null
	var best := 0
	for c in Game.state.map.cards.size():
		var s: int = Game.state.map.cards[c].size
		if World.cheb(c, h.pos.c) > 5 or World.cheb(c, h.pos.c) < 3: continue
		if not World.is_road(c, s >> 1, s >> 1): continue
		var p = World.path(h, {"c": c, "x": s >> 1, "y": s >> 1})
		if p != null and p.size() > best and p.size() < 40:
			best = p.size(); goal = {"c": c, "x": s >> 1, "y": s >> 1}
	ws.path = World.path(h, goal)
	print("  planned ", ws.path.size(), " steps, movement ", h.mp)
	check(ws.path.size() > 0, "a route is planned")
	# end turn for both players, then come back
	Game.end_turn()
	for i in 3: await root.get_tree().process_frame
	Game.state.cur = 0
	Game.begin_turn()
	for i in 3: await root.get_tree().process_frame
	var back = ws.path
	check(ws.sel_hero == h.id, "the same hero is selected on return")
	check(back != null and back.size() > 0 and back[back.size() - 1].c == goal.c and back[back.size() - 1].x == goal.x, "the planned route is shown again on return")
	# switching heroes keeps each hero's own plan
	ws.select_hero(h.id)
	check(ws.path != null, "re-selecting the hero keeps its plan")
	ws.path = null
	ws.stash_plan()
	ws.restore_plan()
	check(ws.path == null, "a cancelled plan stays cancelled")
	print("plan_keep ", "FAILED" if failed else "OK")
