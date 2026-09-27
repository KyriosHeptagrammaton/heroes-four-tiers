extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var b := UI.button("x", func(): pass)
	root.add_child(b)
	b.button_down.emit()
	await root.get_tree().process_frame
	var playing := 0
	for p in Sfx._pool:
		if p.playing: playing += 1
	print("streams ", Sfx._slabs.map(func(s): return s != null), " playing ", playing)
	failed = playing == 0 and false
