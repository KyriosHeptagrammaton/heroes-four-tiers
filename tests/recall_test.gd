extends RefCounted
var failed := false
func run(_root) -> void:
	var h := Heroes.create("warlord", "alpha", "Hero", Rng.new(3))
	h.stats.courage = 20
	var b := Battle.new({"seed": 3, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": "alpha.1.0.", "count": 5}, {"key": "alpha.2.0.", "count": 3}]},
		{"name": "B", "ai": true, "stacks": [{"key": "beta.1.0.", "count": 5}]}]})
	var s = b.stacks[0]
	# wipe it out by desertion
	s.deserters += s.count; s.count = 0; b.eliminated(s)
	# run until A's commander can act
	var n := 0
	while not b.hero_can_act(0) and b.over == null and n < 200:
		CombatAI.step(b) if b.sides[b.current().side].ai or b.current().type == "stack" else null
		n += 1
		if b.current() != null and b.current().type == "hero" and b.current().side == 0: break
	var err = b.command(0, "recall", s.id)
	print("recall on wiped stack -> ", err, " count ", s.count, " deserters ", s.deserters, " alive list has it: ", b.stacks_of(0).has(s))
	failed = err != null or s.count != 1
