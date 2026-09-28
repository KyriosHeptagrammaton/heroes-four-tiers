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
	# find a plain 2-health creature with no special damage rules
	var key := ""
	for f in D.FACTION_IDS:
		for t in [1, 2, 3]:
			var k := Units.key(f, t, 0, "")
			var d := Units.resolve(k)
			if int(d.hp) == 2 and not d.sp.has("courageHealth") and not d.sp.has("lastStandConvert") and key == "":
				key = k
	print("using ", Units.resolve(key).name)
	# doc example: 3 creatures, 2 health, 4 damage -> max 3, one dies, 4 removed
	var b := mk(key, 3)
	var s = b.stacks[0]
	var r := b.deal_damage(s, 4, 0)
	ok(r.killed == 1 and s.count == 2 and s.phys == 0, "doc example: 3x2hp takes 4 -> 1 dies, 0 left (got %d dead, %d left, phys %d)" % [r.killed, s.count, s.phys])
	b = mk(key, 3); s = b.stacks[0]
	r = b.deal_damage(s, 3, 0)
	ok(r.killed == 0 and s.phys == 3, "3 damage fits (3x(2-1)=3): no deaths")
	b = mk(key, 10); s = b.stacks[0]
	r = b.deal_damage(s, 25, 0)
	# 25 > 10 -> 9 left, 21 ; 21 > 9 -> 8, 17 ; 17 > 8 -> 7, 13 ; 13 > 7 -> 6, 9 ; 9 > 6 -> 5, 5 ; 5 <= 5 stop
	ok(r.killed == 5 and s.count == 5 and s.phys == 5, "10x2hp takes 25 -> 5 dead, 5 dmg left (got %d, %d)" % [r.killed, s.phys])
	b = mk(key, 10); s = b.stacks[0]
	var pre := b.simulate_phys(s, 25)
	ok(pre == 5, "simulate_phys agrees (%d)" % pre)
	# test toggle: count x health
	Battle._full = true
	b = mk(key, 3); s = b.stacks[0]
	r = b.deal_damage(s, 6, 0)
	ok(r.killed == 0 and s.phys == 6, "toggle: 3x2hp holds 6")
	r = b.deal_damage(s, 1, 0)
	ok(r.killed == 1 and s.count == 2 and s.phys == 3, "toggle: 7th point kills one, 3 left (got %d, %d)" % [r.killed, s.phys])
	b = mk(key, 10); s = b.stacks[0]
	var mv: int = s.morale_val
	r = b.deal_damage(s, 0, 10 * mv)
	ok(r.deserted == 0, "toggle: morale holds count x morale (%d)" % (10 * mv))
	Battle._full = false
