extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	var b := Battle.new({"seed": 5, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("beta", 4, 0, ""), "count": 1}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 2, 0, ""), "count": 6}, {"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
	var s = b.stacks[1]
	ok(s.count == 5 and s.hero, "6 Dire Wolves lose 1 to Metatron's start flee and become heroes (%d, %s)" % [s.count, s.hero])
	# flee on attack, with a hit too weak to cause losses
	var t = b.stacks[2]
	t.count = 6; t.hero = false; t.phys = -1000; t.mor = -1000
	b.do_attack(b.stacks[0], t)
	ok(t.count <= 5 and t.hero, "a Metatron attack's flee taking a stack to 5 makes it heroes (%d, %s)" % [t.count, t.hero])
