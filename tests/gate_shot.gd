extends RefCounted
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	print("problem: ", sb.setup_problem())
	sb.cfg.sides[0].hero.stats.knowledge = 6
	sb.cfg.sides[1].hero.stats.knowledge = 6
	print("fixed: '", sb.setup_problem(), "'")
	sb.cfg.sides[1].hero.stats.knowledge = 3
	sb.cfg.sides[1].hero.equipped = ["flame", "valor"]
	sb.render()
	for i in 4: await root.get_tree().process_frame
	var found := []
	_find(sb, "⚔ Fight!", found)
	var ev := InputEventMouseMotion.new()
	ev.position = found[0].get_global_rect().get_center()
	root.get_viewport().push_input(ev)
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/gate.png")
	var f2 := []
	_find(sb, "Atk", f2)
	ev = InputEventMouseMotion.new()
	ev.position = f2[0].get_global_rect().get_center()
	root.get_viewport().push_input(ev)
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/atk_tip.png")
func _find(n: Node, t: String, out: Array) -> void:
	if (n is Button or n is Label) and n.text == t: out.append(n)
	for c in n.get_children(): _find(c, t, out)
