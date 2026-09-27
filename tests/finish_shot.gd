extends RefCounted
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].ai = true
	sb.cfg.sides[1].stacks.append({"key": "beta.4.0.", "count": 1})
	sb.fight()
	var bs = UI.screen("battle")
	bs.ai_delay = 0.0
	for i in 3000:
		await root.get_tree().process_frame
		if UI.modal_open(): break
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/finish.png")
	print("ok")
