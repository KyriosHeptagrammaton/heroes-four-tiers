extends RefCounted
var failed := false
func attempt(with_horn: bool):
	var h := Heroes.create("warlord", "alpha", "Hero", Rng.new(3))
	h.stats.courage = 20
	if with_horn: h.artifacts.append("horn")
	var b := Battle.new({"seed": 3, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": "alpha.1.0.", "count": 5}, {"key": "alpha.2.0.", "count": 30}]},
		{"name": "B", "ai": true, "stacks": [{"key": "beta.3.0.", "count": 40}]}]})
	var s = b.stacks[0]
	s.deserters += s.count; s.count = 0; b.eliminated(s)
	var n := 0
	while not b.hero_can_act(0) and b.over == null and n < 200:
		CombatAI.step(b)
		n += 1
		if b.current() != null and b.current().type == "hero" and b.current().side == 0: break
	var err = b.command(0, "recall", s.id)
	# a stack still on the field works either way
	var s2 = b.stacks[1]
	s2.count -= 1; s2.deserters += 1
	var err2 = b.command(0, "recall", s2.id)
	return [err, s.count, err2]
func run(_root) -> void:
	var r0 = attempt(false)
	var r1 = attempt(true)
	print("no horn: ", r0, "  horn: ", r1)
	failed = r0[0] == null or r0[1] != 0 or r1[0] != null or r1[1] != 1 or r0[2] != null
	print("recall_test ", "FAIL" if failed else "PASS")
	# revive: wiped-out stacks need Necromancy; Necromancy III raises two per revive
	for lvl in [0, 1, 3]:
		var h := Heroes.create("warlord", "alpha", "Hero", Rng.new(3))
		h.stats.knowledge = 30; h.equipped = []
		if lvl: h.skills["necromancy"] = lvl
		var b := Battle.new({"seed": 3, "sides": [
			{"name": "A", "hero": h, "stacks": [{"key": "alpha.1.0.", "count": 5}, {"key": "alpha.2.0.", "count": 30}]},
			{"name": "B", "ai": true, "stacks": [{"key": "beta.3.0.", "count": 40}]}]})
		var s = b.stacks[0]
		s.dead += s.count; s.count = 0; b.eliminated(s)
		var n := 0
		while b.over == null and n < 200:
			if b.current() != null and b.current().type == "hero" and b.current().side == 0: break
			CombatAI.step(b); n += 1
		var err = b.command(0, "revive", s.id)
		print("revive wiped, necromancy %d: %s count %d" % [lvl, err, s.count])
		if lvl == 0: failed = failed or err == null or s.count != 0
		elif lvl == 1: failed = failed or err != null or s.count != 1
		else: failed = failed or err != null or s.count != 2
	print("recall_test ", "FAIL" if failed else "PASS")
