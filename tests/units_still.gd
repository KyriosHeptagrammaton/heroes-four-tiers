extends RefCounted
var failed := false
# Stack cards must not move as the commander cards change (turns, casts, the
# commander falling or fleeing); only the death of a stack may reflow its row.
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	var b = Battle.new(sb.battle_opts(7))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	var last := {}
	var lastn := [-1, -1]
	var moves := 0
	var hw := {}
	for i in 60:
		if b.over != null: break
		for k in 3: await root.get_tree().process_frame
		var alive := [0, 0]
		for s in b.stacks:
			if s.count > 0 or bs._cards.has(s.id): alive[s.side] += 1
		var pos := {}
		for id in bs._cards:
			pos[id] = bs._cards[id].global_position
		for side in 2:
			var c = bs._rows[side].get_child(0).get_child(0)
			hw["%d:%s" % [side, c.size]] = true
		for id in bs._cards:
			hw["w%d" % int(bs._cards[id].size.x)] = true
			if bs._cards[id].size.x > bs.STACK_W:
				var body = bs._cards[id].get_child(0)
				for ch in body.get_children():
					print("  wide ", id, " ", ch.get_class(), " ", ch.get_combined_minimum_size(), " ", ch.text if ch is Label else "")
		for id in pos:
			if last.has(id) and last[id] != pos[id]:
				print("step ", i, " stack ", id, " moved ", last[id], " -> ", pos[id])
				moves += 1
		last = pos
		CombatAI.step(b); bs.render()
	print("hero card sizes: ", hw.keys())
	print("moves ", moves)
	failed = moves > 0
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/units_still.png")
