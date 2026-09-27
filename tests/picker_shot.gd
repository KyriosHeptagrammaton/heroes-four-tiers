extends RefCounted
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].stacks[1].key = "alpha.2.2.r"
	sb.pick_unit(sb.cfg.sides[0], sb.cfg.sides[0].stacks[1])
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/picker.png")
	print("carry T4:", sb.carry_upgrade("alpha.2.2.r", "beta", 4), " T3:", sb.carry_upgrade("alpha.2.2.r", "gamma", 3), " magi->T4:", sb.carry_upgrade("alpha.1.1.m", "delta", 4))
