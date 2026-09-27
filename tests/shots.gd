extends RefCounted
# Screenshots of the main screens (run under xvfb with the opengl3 driver).
func shot(root: Node, name: String) -> void:
	for i in 6:
		await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/claude-0/shots/%s.png" % name)
	print("shot ", name)

func run(root) -> void:
	Main.boot()
	await shot(root, "menu")
	UI.screen("sandbox").open()
	await shot(root, "sandbox")
	var sb = UI.screen("sandbox")
	sb.cfg.sides[1].ai = true
	sb.fight()
	var bs = UI.screen("battle")
	await shot(root, "battle1")
	# play a few AI steps for both sides
	for i in 14:
		CombatAI.step(bs.b)
	bs.mode = "attack"
	bs.render()
	await shot(root, "battle2")
