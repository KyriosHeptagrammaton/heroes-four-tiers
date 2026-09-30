extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func mk(sides: Array) -> Battle:
	return Battle.new({"seed": 5, "probe": true, "sides": sides})
func run(_root) -> void:
	ok(Units.resolve(Units.key("beta", 4, 0, "")).name == "Metatron", "beta T4 is Metatron")
	# Skeleton Magi share: 2 magi stacks, 5 dead -> 2.5 each (2 now, 0.5 carried)
	var SM := Units.key("delta", 1, 1, "m")
	var b := mk([{"name": "A", "stacks": [{"key": SM, "count": 10}, {"key": SM, "count": 10}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}])
	b.deal_damage(b.stacks[2], 6, 0)
	var dead: int = b.stacks[2].dead
	var g0: int = b.stacks[0].count - 10
	print("  %d died; magi gained %d and %d" % [dead, g0, b.stacks[1].count - 10])
	ok(g0 == int(floor(dead / 2.0)) and b.stacks[1].count - 10 == g0, "each of 2 Skeleton Magi stacks gains dead ÷ 2 (rounded down, remainder carried)")
	# Angel aura once
	var ang := Units.key("gamma", 4, 0, "")
	var pk := Units.key("gamma", 1, 0, "")
	var b1 := mk([{"name": "A", "stacks": [{"key": ang, "count": 1}, {"key": pk, "count": 18}]}, {"name": "B", "stacks": [{"key": pk, "count": 18}]}])
	var b2 := mk([{"name": "A", "stacks": [{"key": ang, "count": 1}, {"key": ang, "count": 1}, {"key": pk, "count": 18}]}, {"name": "B", "stacks": [{"key": pk, "count": 18}]}])
	ok(b1.stacks[1].morale_val == b2.stacks[2].morale_val, "two Angels give the same +1 morale as one (%d vs %d)" % [b1.stacks[1].morale_val, b2.stacks[2].morale_val])
	# Metatron scatter once per battle
	var met := Units.key("beta", 4, 0, "")
	var b3 := Battle.new({"seed": 5, "sides": [{"name": "A", "stacks": [{"key": met, "count": 1}, {"key": met, "count": 1}, {"key": pk, "count": 18}]}, {"name": "B", "stacks": [{"key": pk, "count": 18}]}]})
	ok(b3.stacks[2].count == 17 and b3.stacks[3].count == 17, "two Metatrons: each other stack loses only 1 creature (%d, %d)" % [b3.stacks[2].count, b3.stacks[3].count])
	# kin loss
	var sk := Units.key("delta", 1, 0, "")
	var b4 := mk([{"name": "A", "stacks": [{"key": sk, "count": 5}, {"key": Units.key("delta", 1, 1, "r"), "count": 18}, {"key": Units.key("delta", 1, 2, ""), "count": 18}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]},
		{"name": "B", "stacks": [{"key": pk, "count": 18}]}])
	var m_before := [b4.stacks[1].morale_val, b4.stacks[2].morale_val, b4.stacks[3].morale_val]
	b4.stacks[0].count = 0; b4.eliminated(b4.stacks[0])
	ok(b4.stacks[1].morale_val == m_before[0] - 1 and b4.stacks[2].morale_val == m_before[1] - 1, "other Skeleton stacks (Ranged I, Melee II) lose 1 morale")
	ok(b4.stacks[3].morale_val == m_before[2], "a different base creature is unaffected")
