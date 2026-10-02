extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	# reviewer's scenario: 5 Skeleton Magi beside another attacker, 3 enemy creatures die elsewhere
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("delta", 1, 1, "m"), "count": 5}, {"key": Units.key("alpha", 3, 0, ""), "count": 6}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 10}]}]})
	var magi = b.stacks[0]
	b.deal_damage(b.stacks[2], 6, 0, {"source": b.stacks[1], "kind": "attack"})
	var stored: int = magi.morale_val
	var fresh := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("delta", 1, 1, "m"), "count": magi.count}, {"key": Units.key("alpha", 3, 0, ""), "count": 6}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 10}]}]})
	fresh.stacks[0].hero = magi.hero
	fresh.recalc_morale(fresh.stacks[0])
	print("  magi now %d creatures: morale %d, a fresh stack of that size has %d" % [magi.count, stored, fresh.stacks[0].morale_val])
	ok(magi.count > 5 and stored == fresh.stacks[0].morale_val, "grown Skeleton Magi have up-to-date morale")
	var b6 := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": Units.key("alpha", 2, 0, ""), "count": 6}]}, {"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
	ok(Battle.front_rank(6) == 2 and b6.phys_cap(b6.stacks[0]) == 2, "6 Dire Wolves: 2 front (limit 2) / 4 back (limit 8)")
