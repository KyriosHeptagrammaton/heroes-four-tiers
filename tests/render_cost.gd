extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	var b = Battle.new(sb.battle_opts(4242))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	await root.get_tree().process_frame
	var ts := []
	for i in 6:
		CombatAI.step(b)
		var t := Time.get_ticks_usec()
		bs.render()
		ts.append((Time.get_ticks_usec() - t) / 1000.0)
		var t2 := Time.get_ticks_usec()
		await root.get_tree().process_frame
		ts.append(["frame", (Time.get_ticks_usec() - t2) / 1000.0])
	print("render ms / next frame: ", ts)
