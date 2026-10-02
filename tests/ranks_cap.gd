extends RefCounted
var failed := false
func run(_root) -> void:
	var bad := 0
	var checked := 0
	for f in D.FACTION_IDS:
		for t in [1, 2, 3, 4]:
			for n in range(1, 41):
				var b := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": Units.key(f, t, 0, ""), "count": n}]}, {"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
				var s = b.stacks[0]
				s.phys = 0; s.mor = 0
				var cour: int = b.sides[0].courage
				for kind in ["phys", "mor"]:
					var cap: int = b.phys_cap(s) if kind == "phys" else b.mor_cap(s)
					var at: Dictionary = b.resolve_losses(n, 0, 0, cap if kind == "phys" else 0, cap if kind == "mor" else 0, b.health(s), s.morale_val, cour, 0)
					var over: Dictionary = b.resolve_losses(n, 0, 0, cap + 1 if kind == "phys" else 0, cap + 1 if kind == "mor" else 0, b.health(s), s.morale_val, cour, 0)
					checked += 1
					if at.killed + at.deserted != 0 or over.killed + over.deserted == 0:
						bad += 1
						if bad < 6: print("mismatch %s.%d n=%d %s cap=%d at=%s over=%s" % [f, t, n, kind, cap, at, over])
	print("checked %d (unit, size, kind) cases; %d where the shown limit was wrong" % [checked, bad])
	failed = bad != 0
