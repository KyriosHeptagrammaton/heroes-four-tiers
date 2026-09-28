extends RefCounted
func shot(root, name):
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/%s.png" % name)
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	Main.options()
	await shot(root, "options")
	UnitSym.set_portraits(false)
	root.get_tree().call_group("unitsym", "queue_redraw")
	UI.close_modal()
	await shot(root, "sandbox_abstract")
	UnitSym.set_portraits(true)
