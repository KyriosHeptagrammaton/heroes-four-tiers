extends RefCounted
func shot(root: Node, name: String, frames: int = 6) -> void:
	for i in frames:
		await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/%s.png" % name)
	print("shot ", name)

func run(root) -> void:
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["alpha", "beta"], "cls": ["warlord", "mage"], "seed": 42})
	await shot(root, "handoff")
	Game.begin_turn()
	await shot(root, "world", 12)
	var ws = UI.screen("world")
	# plan a path down the road
	var h = World.hero(ws.sel_hero)
	var best = null
	for c in range(0, 400):
		pass
	# walk toward the map centre along whatever route exists
	var goal = null
	for n in World.neighbors(h.owner, h, h.pos):
		if World.enterable(h, n, World.player(0)) == null: goal = n
	print("hero at ", h.pos, " mp ", h.mp)
	var tried := 0
	for c in [World.card(h.pos.c)]:
		pass
	ws.zoom(1.6)
	await shot(root, "world_zoom", 6)
	UI.screen("town").open(World.towns_of(0)[0].id, h.id)
	await shot(root, "town")
	ArmyUI.hero_screen(h.id)
	await shot(root, "hero")
	UI.close_modal()
	ArmyUI.army_screen(h.id, World.towns_of(0)[0].id, Callable())
	await shot(root, "army")
	UI.close_modal()
	# long walk: auto-path to some far explored road tile
	ws.enter()
	var P = World.player(0)
	var far = null
	for c in Game.state.map.cards.size():
		if P.seen[c] and World.card(c).road.has(true) and World.cheb(c, h.pos.c) >= 2:
			var tiles = WorldGen.road_tiles(World.card(c))
			for t in tiles:
				var n = {"c": c, "x": t[0], "y": t[1]}
				if World.enterable(h, n, P) == null and World.path(h, n) != null:
					far = n
			if far != null: break
	print("far target ", far)
	if far != null:
		ws.path = World.path(h, far)
		print("path len ", ws.path.size())
		await shot(root, "world_path")
		Game.walk(h, ws.path)
		await root.get_tree().create_timer(1.5).timeout
		print("after walk ", h.pos, " mp ", h.mp)
		await shot(root, "world_walked")
