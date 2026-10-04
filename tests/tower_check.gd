extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true
func run(root) -> void:
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42})
	Game.begin_turn()
	var tower = null
	for c in Game.state.map.cards.size():
		for o in Game.state.map.cards[c].objs:
			if o.type == "tower" and tower == null: tower = {"c": c, "x": o.x, "y": o.y}
	var P = World.player(0)
	var n := World.reveal_tiles(0, tower, 10)
	# every revealed tile is within 10 steps, and a tile 10 steps away is revealed
	var far := 0; var ok := true
	for nd in World.sight_bfs({"pos": tower}, 12):
		var t: Dictionary = nd[0]
		var seen := World.tile_seen(P, t.c, t.x, t.y)
		if nd[1] == 10 and seen: far += 1
		if nd[1] <= 10 and not seen: ok = false
	check(n > 0 and ok and far > 0, "watchtower reveals every tile within 10 steps (%d newly, %d at exactly 10)" % [n, far])
	var cards := {}
	for nd in World.sight_bfs({"pos": tower}, 10): cards[nd[0].c] = true
	print("  cards touched: ", cards.size())
	var ws = UI.screen("world")
	ws.center_on(tower.c, tower.x, tower.y)
	ws.zoom(0.7)
	ws.map.queue_redraw(); ws.fog.queue_redraw()
	for i in 8: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/tower.png")
	print("tower_check ", "FAILED" if failed else "OK")
