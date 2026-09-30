extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].hero.stats.initiative = 2
	var b = Battle.new(sb.battle_opts(7))
	ok(b.command_block(0, "recall") != "", "recall blocked with no deserters: " + b.command_block(0, "recall"))
	ok(b.command_block(0, "revive") != "", "revive blocked with no fallen: " + b.command_block(0, "revive"))
	ok(b.command_block(0, "embolden") == "", "embolden usable with pips")
	ok(b.command_block(0, "steel") == "", "steel nerves always usable")
	b.sides[0].hs.pips = 2
	ok(b.command_block(0, "embolden") == "No initiative pips left", "embolden blocked with no pips")
	var s = b.stacks_of(0)[0]
	s.count -= 2; s.deserters += 2; s.dead += 1
	ok(b.command_block(0, "recall") == "", "recall usable once a stack has deserters and courage %d" % b.sides[0].courage)
	b.sides[0].courage = 0
	ok(b.command_block(0, "recall").begins_with("Not enough courage"), "recall blocked without courage")
	b.sides[0].hs.spareKnowledge = 0
	ok(b.command_block(0, "revive").begins_with("Not enough spare knowledge"), "revive blocked without spare knowledge")
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/cmd_block.png")
