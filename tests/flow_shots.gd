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
	Game.begin_turn()
	await shot(root, "f0", 10)
	var S = Game.state
	var h = World.heroes_of(0)[0]
	# find a monster and put the hero next to it
	var mon = null
	var mc := -1
	for c in S.map.cards.size():
		for o in S.map.cards[c].objs:
			if o.type == "monster" and mon == null:
				mon = o; mc = c
	h.pos = {"c": mc, "x": mon.x, "y": mon.y}
	World.reveal_radius(0, mc, 2)
	World.compute_visible(0)
	UI.screen("world").center_on(mc, mon.x, mon.y)
	var ws = UI.screen("world")
	ws.on_hover(ws.map.size / 2)
	await shot(root, "f1_hover", 8)
	h.pos = {"c": mc, "x": mon.x, "y": mon.y}
	Game.battle(h, {"kind": "monster", "obj": mon, "node": {"c": mc, "x": mon.x, "y": mon.y}})
	await shot(root, "f2_time", 8)
	# press the first time option
	var btns := []
	_find_buttons(UI._modal_content, btns)
	btns[0].emit_signal("pressed")
	await shot(root, "f3_battle", 10)
	var bs = UI.screen("battle")
	# hover a defender card while in attack mode
	bs.mode = "attack"
	bs.render()
	await root.get_tree().process_frame
	var target = null
	for id in bs._cards:
		if bs.b.stack(id).side == 1: target = bs._cards[id]
	if target:
		Input.warp_mouse(target.get_global_rect().get_center())
		var ev := InputEventMouseMotion.new()
		ev.position = target.get_global_rect().get_center()
		root.get_viewport().push_input(ev)
	await shot(root, "f4_preview", 10)

func _find_buttons(n: Node, out: Array) -> void:
	if n is Button: out.append(n)
	for c in n.get_children(): _find_buttons(c, out)
