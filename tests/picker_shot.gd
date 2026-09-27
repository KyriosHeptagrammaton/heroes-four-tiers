extends RefCounted
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].stacks[0].key = "alpha.1.1.r@gamma.2.0."
	sb.render()
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/sandbox_mount.png")
	sb.pick_unit(sb.cfg.sides[0], sb.cfg.sides[0].stacks[0], "mount")
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/picker.png")
	print("ok")
