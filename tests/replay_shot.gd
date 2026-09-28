extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].ai = true
	sb.cfg.sides[1].ai = true
	var b = Battle.new(sb.battle_opts(7))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0     # we drive the AI by hand
	bs.start(b, func(_b): pass)
	for i in 14:
		if b.over != null: break
		CombatAI.step(b)
		bs.render()
	await root.get_tree().process_frame
	var n: int = bs._hist.size()
	print("snapshots: ", n, " log ", b.log.size())
	var live_counts = b.stacks.map(func(x): return x.count)
	var live_log: int = b.log.size()
	for i in 5: bs.review_step(-1)
	ok(bs.reviewing() and bs.b != b, "reviewing a frozen board")
	print("view counts ", bs.b.stacks.map(func(x): return x.count), " live ", live_counts)
	ok(bs.b.log.size() < live_log, "log rewound (%d < %d)" % [bs.b.log.size(), live_log])
	# try to play: must be refused
	var before = b.log.size()
	bs.pick_action("attack"); bs.do_act("attack", b.stacks[3].id)
	ok(b.log.size() == before, "nothing played while reviewing")
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/replay.png")
	bs.review_step(1)
	ok(bs._rev == n - 5, "step forward")
	bs.go_live()
	ok(not bs.reviewing() and bs.b == b and b.stacks.map(func(x): return x.count) == live_counts, "back to live, untouched")
	ok(bs._hist.size() == n, "no duplicate snapshot on return")
