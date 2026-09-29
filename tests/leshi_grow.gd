extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	var L := Units.key("gamma", 3, 0, "")
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": L, "count": 12}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 18}, {"key": Units.key("beta", 2, 0, ""), "count": 9}, {"key": Units.key("beta", 1, 0, ""), "count": 18}]}]})
	var le = b.stacks[0]
	b.strike(le, b.stacks[1])
	ok(le.extra_hp == 1 and b.health(le) == 1, "kills a Martial Saint (1 > true 0): +1, true health 1, shows 1")
	b.strike(le, b.stacks[2])
	ok(le.extra_hp == 2 and b.health(le) == 2, "then kills a Lion (2 > 1): +1 more, shows 2 (got %d)" % b.health(le))
	b.strike(le, b.stacks[3])
	ok(le.extra_hp == 2, "a Martial Saint (1) no longer out-healths it (2)")
	for l in b.log: if "grows" in l.t: print("  log: ", l.t)
