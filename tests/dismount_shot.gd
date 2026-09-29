extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	sb.cfg.sides[0].stacks[2].key = Units.key("alpha", 3, 0, "") + "@" + Units.key("beta", 2, 1, "")
	sb.render()
	for i in 4: await root.get_tree().process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/dismount.png")
	var found := []
	_find(sb, "✕", found)
	print("x buttons: ", found.size())
	# the mount ✕ is the one right after "per rider"
	for b in found:
		if b.tooltip_text == "" and b.has_meta("tip") and str(b.get_meta("tip")).begins_with("Dismount"):
			b.emit_signal("pressed")
	await root.get_tree().process_frame
	print("key after: ", sb.cfg.sides[0].stacks[2].key, " count ", sb.cfg.sides[0].stacks[2].count)
	failed = "@" in sb.cfg.sides[0].stacks[2].key
func _find(n: Node, t: String, out: Array) -> void:
	if n is Button and n.text == t: out.append(n)
	for c in n.get_children(): _find(c, t, out)
