extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func mk(k: String, n: int) -> Battle:
	return Battle.new({"seed": 3, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": k, "count": n}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
func run(_root) -> void:
	var dw := Units.key("alpha", 2, 0, "")   # Dire Wolf, 2 health
	# 3 creatures: all back rank, hold 3 x 2 = 6
	var b := mk(dw, 3); var s = b.stacks[0]
	ok(b.deal_damage(s, 6, 0).killed == 0, "3 x 2-health hold 6 (all back rank)")
	ok(b.deal_damage(s, 1, 0).killed == 1 and s.count == 2 and s.phys == 3, "the 7th point kills one, 3 damage left")
	# 16 creatures: front 4 (limit 4), back 12 (limit 24)
	b = mk(dw, 16); s = b.stacks[0]
	var r := b.deal_damage(s, 20, 0)
	ok(r.killed == 4 and s.count == 12 and s.phys == 4, "16 take 20: whole front rank of 4 falls, 4 held (%d, %d)" % [r.killed, s.phys])
	b = mk(dw, 16); s = b.stacks[0]
	ok(b.simulate_phys(s, 20) == 4, "last-stand check agrees")
	# hero units: 5 or fewer
	var h := Heroes.create("warlord", "alpha", "Hero", Rng.new(3))
	var b2 := Battle.new({"seed": 3, "probe": true, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": dw, "count": 3}, {"key": dw, "count": 4}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
	ok(b2.stacks[0].hero and not b2.stacks[1].hero, "3 creatures start as heroes, 4 do not")
	var s6 = b2.stacks[1]
	s6.count = 3; b2.check_hero_unit(s6)
	ok(s6.hero, "a stack dropping to 3 becomes heroes")
	h.skills["heroics"] = 2
	var b3 := Battle.new({"seed": 3, "probe": true, "sides": [
		{"name": "A", "hero": h, "stacks": [{"key": dw, "count": 9}, {"key": dw, "count": 10}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
	ok(b3.stacks[0].hero and not b3.stacks[1].hero, "Heroics II: 9 are heroes, 10 are not")
	# small stacks: all front rank when the army has another stack of exactly the same kind
	var mk2 := func(keys: Array) -> Battle:
		return Battle.new({"seed": 3, "probe": true, "sides": [
			{"name": "A", "stacks": keys.map(func(k): return {"key": k, "count": 3})},
			{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 1}]}]})
	var tr := Units.key("alpha", 3, 0, "")
	var lone: Battle = mk2.call([tr])
	var twin: Battle = mk2.call([tr, tr])
	var other: Battle = mk2.call([tr, Units.key("alpha", 3, 1, "")])
	ok(not lone.small_all_front(lone.stacks[0]) and lone.phys_cap(lone.stacks[0]) == 9, "3 Trolls alone: all back rank, hold 9")
	ok(twin.small_all_front(twin.stacks[0]) and twin.phys_cap(twin.stacks[0]) == 6, "3 Trolls with another Troll stack: all front rank, hold 3 x 2 = 6")
	ok(not other.small_all_front(other.stacks[0]), "a Troll Melee I stack doesn't count as the same kind")
	var rt := twin.deal_damage(twin.stacks[0], 7, 0)
	ok(rt.killed == 1, "7 damage kills one of the twinned Trolls (front rank limit 6)")
	ok(twin.stacks[1].hero, "small stacks are still heroes")
