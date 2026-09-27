extends RefCounted
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].stacks[1].key = "alpha.2.2.r"
	sb.cfg.sides[1].stacks.append({"key": "beta.4.1.m", "count": 1})
	sb.render()
	for i in 4: await root.get_tree().process_frame
	var found = []
	_find(sb, "Magi", found)
	var btn: Control = found[0]
	var ev := InputEventMouseMotion.new()
	ev.position = btn.get_global_rect().get_center()
	root.get_viewport().push_input(ev)
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/sandbox_pick.png")
	print("ok")
func _find(n: Node, t: String, out: Array) -> void:
	if n is Button and n.text == t: out.append(n)
	for c in n.get_children(): _find(c, t, out)
