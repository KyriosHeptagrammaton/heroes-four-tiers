extends RefCounted
var failed := false
# CI sanity check: generate a map and play a few AI battles; exits non-zero on failure.
func run(root) -> void:
	var g := WorldGen.generate(42, {"factions": ["alpha", "beta"]})
	var ok: bool = g.map.cards.size() == 400 and g.towns.size() == 4
	for i in 5:
		var b := Battle.new({"seed": 1000 + i, "terrain": "field", "time": "dawn", "weather": "clear", "sides": [
			{"name": "A", "ai": true, "stacks": [{"key": "alpha.1.0.", "count": 20}, {"key": "alpha.2.1.r", "count": 6}]},
			{"name": "B", "ai": true, "stacks": [{"key": "delta.1.0.", "count": 20}, {"key": "gamma.3.0.", "count": 4}]}]})
		var n := 0
		while b.over == null and n < 20000:
			CombatAI.step(b); n += 1
		ok = ok and b.over != null
	print("selfcheck ", "OK" if ok else "FAILED")
	failed = not ok
