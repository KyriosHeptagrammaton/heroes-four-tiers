extends RefCounted
func run(_root) -> void:
	var out := {}
	for s in [1, 42, 777, 123456, 999999]:
		out[str(s)] = WorldGen.generate(s, {"factions": ["alpha", "beta"]})
	var f := FileAccess.open("/tmp/claude-0/parity/world_gd.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	print("worldgen ok")
