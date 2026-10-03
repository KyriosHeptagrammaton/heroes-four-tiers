extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 12}, {"key": Units.key("delta", 3, 0, ""), "count": 6}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
	var ally = b.stacks[2]
	ally.phys = 0; ally.mor = 0
	b.do_rally(b.stacks[1], ally)
	ok(b.stacks[0].phys == -12 and ally.phys < 0, "Leshi buffer -12 and Draugr negative health damage (%d)" % ally.phys)
	ok(Battle.front_rank(1) == 0 and Battle.front_rank(3) == 0 and Battle.front_rank(4) == 1 and Battle.front_rank(5) == 2 and Battle.front_rank(6) == 3 and Battle.front_rank(7) == 3 and Battle.front_rank(10) == 4 and Battle.front_rank(17) == 5, "front ranks: 3→0, 4→1, 5→2, 6+→ceil(sqrt n)")
	ok(Battle.front_rank(3, true) == 3 and Battle.front_rank(4, true) == 1, "twin rule only for 3 or fewer")
