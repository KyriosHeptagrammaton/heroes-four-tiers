extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].ai = true
	var b = Battle.new(sb.battle_opts(7))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	for i in 14:
		if b.over != null: break
		CombatAI.step(b); bs.render()
	var pos := []
	for step in [0, -1, -1, -1, 1, 1, 1, 1]:
		if step != 0: bs.review_step(step)
		for i in 3: await root.get_tree().process_frame
		pos.append([bs._nav_prev.global_position.x, bs._nav_next.global_position.x, bs._nav_live.global_position.x, bs._nav_live.visible, bs._nav_live.disabled, bs._nav_lbl.text, bs._info.global_position.y])
	for p in pos: print(p)
	for p in pos: failed = failed or p[0] != pos[0][0] or p[1] != pos[0][1] or p[2] != pos[0][2] or not p[3] or (p[6] != pos[1][6] and p[4] == false)
	print("nav stable: ", not failed)
