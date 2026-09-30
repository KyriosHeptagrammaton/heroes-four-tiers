extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func play(root, sb, commanders: bool, terrain: String) -> Dictionary:
	sb.cfg.sides[0].ai = true; sb.cfg.sides[1].ai = true
	sb.cfg.sides[0].hero.enabled = commanders; sb.cfg.sides[1].hero.enabled = commanders
	sb.cfg.terrain = terrain
	var b = Battle.new(sb.battle_opts(4242))
	var bs = UI.screen("battle")
	bs.ai_delay = 0.0
	bs.ai_stats = {"searched": 0, "rejected": 0, "native": 0, "ms": []}
	bs.start(b, func(_b): pass)
	var frames := 0
	var worst := 0
	var last := Time.get_ticks_usec()
	while b.over == null and frames < 20000:
		await root.get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last); last = now
		frames += 1
		if frames == 40:   # open replay mid-battle: planning must cancel, then resume
			bs.review_step(-1); await root.get_tree().process_frame; bs.go_live()
	var ms: Array = bs.ai_stats.ms.duplicate(); ms.sort()
	var med = ms[ms.size() / 2] if ms.size() else 0
	return {"over": b.over, "rounds": b.round_n, "stats": bs.ai_stats, "median_ms": med, "max_ms": ms.back() if ms.size() else 0, "worst_frame_ms": worst / 1000.0}
func run(root) -> void:
	Main.boot()
	var BS = load("res://scripts/ui/battle_screen.gd")
	BS._ai_level = "hard"
	var sb = UI.screen("sandbox")
	sb.open()
	BS._ai_level = "normal"
	var r0 = await play(root, sb, false, "field")
	print("normal, no commanders: worst frame ", r0.worst_frame_ms, " ms, rounds ", r0.rounds)
	BS._ai_level = "hard"
	var r1 = await play(root, sb, false, "field")
	print("no commanders: ", r1)
	ok(r1.over != null and r1.stats.searched > 0 and r1.stats.rejected == 0, "Hard plays a full battle without commanders")
	var r2 = await play(root, sb, true, "field")
	print("with commanders: ", r2)
	ok(r2.over != null and r2.stats.searched > 0, "Hard also searches with commanders on the field")
	var r3 = await play(root, sb, true, "town")
	print("siege: ", r3)
	ok(r3.over != null and r3.stats.searched > 0, "Hard searches in a siege (illegal picks fall back)")
	BS._ai_level = null
