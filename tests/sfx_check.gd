extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	for st in Sfx.STYLES:
		print(st, " ", Sfx._sets[st].map(func(s): return s != null and s.get_length() > 0.05))
	Sfx.set_style("door")
	await root.get_tree().process_frame
	var playing := 0
	for p in Sfx._pool:
		if p.playing: playing += 1
	print("playing ", playing, " style ", Sfx.style)
	Sfx.set_style("stone")
