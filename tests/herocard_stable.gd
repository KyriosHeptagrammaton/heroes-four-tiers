extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	var b = Battle.new(sb.battle_opts(7))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	for i in 30:
		if b.over != null: break
		CombatAI.step(b); bs.render()
		await root.get_tree().process_frame
	var hs := []
	var sides := []
	for step in [0, -1, -1, -1, -1, -1, 1, 1, 1, 1, 1, 1]:
		if step != 0: bs.review_step(step)
		for i in 3: await root.get_tree().process_frame
		var card = bs._rows[0].get_child(0).get_child(0)
		hs.append(card.size.y)
		sides.append(bs._info.global_position.y)
	print("hero card heights: ", hs)
	print("details y: ", sides)
	for h in hs: failed = failed or h != hs[0]
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/herocard.png")
