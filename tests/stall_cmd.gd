extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	# two armies that only wait/seek: battle must survive one quiet round and end after the second
	var b := Battle.new({"seed": 5, "terrain": "swamp", "sides": [
		{"name": "A", "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 6}]},
		{"name": "B", "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 6}]}]})
	var n := 0
	while b.over == null and n < 50:
		if b.current_stack() != null: b.act("seek")
		else: break
		n += 1
	ok(b.over != null and b.over.reason == "stalemate" and b.round_n == 2, "stalemate after 2 quiet rounds (round %d, %s)" % [b.round_n, b.over])
	# commander loss
	var h := Heroes.create("warlord", "alpha", "Hero", Rng.new(3))
	h.stats.courage = 20
	var b2 := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": Units.key("alpha", 4, 0, ""), "count": 1}, {"key": Units.key("alpha", 1, 0, ""), "count": 18}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 18}]}]})
	var c0: int = b2.sides[0].courage
	var t4 = b2.stacks[0]
	var stack_loss := 3 if t4.hero else 2
	t4.count = 0; t4.last_loss_dead = true; b2.eliminated(t4)
	ok(b2.sides[0].courage == c0 - stack_loss - 4, "tier 4 (%d) + commander (4) lost: %d -> %d" % [stack_loss, c0, b2.sides[0].courage])
