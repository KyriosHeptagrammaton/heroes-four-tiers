extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	var b = Battle.new(sb.battle_opts(3))
	var a = b.stacks_of(0)[0]
	var t = b.stacks_of(1)[2]
	t.retaliating = true
	b.do_attack(a, t)
	var found: bool = b.last_attack.size() == 2
	print(b.last_attack)
	UI.screen("battle").start(b, func(_b): pass)
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/attack_mark.png")
	Main.options()
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/options2.png")
	failed = not found
