extends RefCounted
func run(root) -> void:
	Main.boot()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color("#2b261f"); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	root.add_child(c)
	var keys := ["alpha.1.1.r@gamma.2.1.", "beta.1.1.m@alpha.4.0.", "gamma.1.2.@delta.1.1.m", "delta.1.1.r@beta.2.1.r", "alpha.3.1.@alpha.1.1."]
	for mode in 2:
		UnitSym.set_portraits(mode == 0)
		for i in keys.size():
			var s := UI.sym(Units.resolve(keys[i]), 96)
			s.position = Vector2(20 + i * 150, 30 + mode * 150); s.size = Vector2(96, 96)
			c.add_child(s)
		for i in 6: await root.get_tree().process_frame
		await RenderingServer.frame_post_draw
		if mode == 0:
			root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/riders_a.png")
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/riders.png")
	UnitSym.set_portraits(true)
