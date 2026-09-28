extends RefCounted
func shot(root, name):
	for i in 6: await root.get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/%s.png" % name)
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].stacks = [{"key": "alpha.1.1.", "count": 18}, {"key": "alpha.2.1.r", "count": 9}, {"key": "alpha.3.2.", "count": 6}, {"key": "alpha.4.1.m", "count": 3}, {"key": "alpha.1.1.@gamma.2.0.", "count": 6}, {"key": "gamma.1.1.r@delta.1.0.", "count": 6}]
	sb.cfg.sides[1].stacks = [{"key": "beta.1.0.", "count": 18}, {"key": "gamma.3.1.m", "count": 6}, {"key": "delta.2.1.r", "count": 9}, {"key": "beta.4.1.", "count": 3}, {"key": "delta.4.0.", "count": 3}, {"key": "gamma.2.1.r", "count": 9}]
	sb.render()
	await shot(root, "icons_sandbox")
	sb.fight()
	await shot(root, "icons_battle")
	# sheet of every unit, big
	UI.close_modal()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color("#2b261f"); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var y := 10
	for f in D.FACTION_IDS:
		var x := 10
		for t in range(1, 5):
			for k in [Units.key(f, t, 0, ""), Units.key(f, t, 1, ""), Units.key(f, t, 1, "r") if t < 4 else Units.key(f, t, 1, ""), Units.key(f, t, 1, "m")]:
				var s := UI.sym(Units.resolve(k), 64)
				s.position = Vector2(x, y); s.size = Vector2(64, 64)
				c.add_child(s)
				x += 84
		y += 90
	var x2 := 10
	for k in ["alpha.1.1.@gamma.2.0.", "beta.1.1.m@alpha.4.0.", "gamma.1.1.r@delta.1.0.", "delta.1.2.@beta.2.0.", "alpha.3.1.@alpha.1.0."]:
		var s := UI.sym(Units.resolve(k), 96)
		s.position = Vector2(x2, 380); s.size = Vector2(96, 96)
		c.add_child(s)
		x2 += 130
	root.add_child(c)
	await shot(root, "icons_all")
