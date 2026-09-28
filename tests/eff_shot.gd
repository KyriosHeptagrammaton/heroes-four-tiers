extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].hero.stats.attack = 5
	sb.cfg.sides[0].stacks[2] = {"key": Units.key("gamma", 3, 0, ""), "count": 12}
	sb.cfg.sides[0].faction = "gamma"
	var b = Battle.new(sb.battle_opts(5))
	UI.screen("battle").start(b, func(_b): pass)
	for i in 4: await root.get_tree().process_frame
	UI.screen("battle").sel = b.stacks[2].id
	UI.screen("battle").render()
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/eff.png")
