extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	var c1 := World.upgrade_cost(Units.key("beta", 3, 0, ""), Units.key("beta", 3, 1, ""), 6)
	ok(c1.gold == 6 * (335 - 210) and c1.essence == 6 and c1.tier == 3, "Archon -> Archon Melee I: 6 x (335-210) gold + 6 T3 essence (%s)" % c1)
	var c2 := World.upgrade_cost(Units.key("gamma", 3, 1, ""), Units.key("gamma", 3, 2, ""), 4)
	ok(c2.gold == 4 * 75, "Leshi Melee I -> II: 4 x 75 (%s)" % c2)
	var c3 := World.upgrade_cost(Units.key("alpha", 4, 0, ""), Units.key("alpha", 4, 1, "m"), 1)
	ok(c3.gold == 400, "Titan -> Titan Magi: 400 (%s)" % c3)
	ok(Units.base_price("beta", 2) == 82.0 and Units.base_price("gamma", 3) == 125.0, "recruit prices come from the table")
	for f in D.FACTION_IDS:
		for t in [1, 2, 3, 4]:
			for k in Units.variants(f, t):
				if Units.variant_value(k) <= 0: ok(false, "missing value for " + k)
	print("all variants have a value")
