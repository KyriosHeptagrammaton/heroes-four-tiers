extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func mk() -> Battle:
	return Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 12}, {"key": Units.key("delta", 3, 0, ""), "count": 6}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
func run(_root) -> void:
	# Leshi buffer and Draugr negative health damage apply in every casualty mode
	for m in ["standard", "full", "ranks"]:
		Battle._mode = m
		var b := mk()
		var ally = b.stacks[2]
		ally.phys = 0; ally.mor = 0
		b.do_rally(b.stacks[1], ally)
		ok(b.stacks[0].phys == -12 and ally.phys < 0, "%s: Leshi buffer -12 and Draugr negative health damage (%d)" % [m, ally.phys])
	# ranks: 16 creatures with 2 health take 20 health damage
	var dw := Units.key("alpha", 2, 0, "")
	var res := {}
	for m in ["standard", "full", "ranks"]:
		Battle._mode = m
		var b2 := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": dw, "count": 16}]}, {"name": "B", "stacks": [{"key": dw, "count": 1}]}]})
		var s = b2.stacks[0]
		var r := b2.deal_damage(s, 20, 0)
		res[m] = [r.killed, s.count, s.phys]
		print("  %s: 16 x 2-health take 20 -> %d killed, %d left, %d damage held" % [m, r.killed, s.count, s.phys])
	ok(res.standard == [2, 14, 12], "standard: 20 > 15 kills 1 (16 left), 16 > 14 kills another, 12 held")
	ok(res.full == [0, 16, 20], "full: 20 <= 32, nobody dies")
	# front rank 4 at threshold 4x1: 20>4 ->16, 16>3 ->12, 12>2 ->8, 8>1 ->4: whole front (4) dies; back 12x2=24 holds 4
	ok(res.ranks == [4, 12, 4], "ranks: whole front rank of 4 falls, back rank holds the rest")
	# ranks morale: front tested before back
	Battle._mode = "ranks"
	var b3 := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": dw, "count": 16}]}, {"name": "B", "stacks": [{"key": dw, "count": 1}]}]})
	var s3 = b3.stacks[0]
	var mv: int = s3.morale_val
	var cour: int = b3.sides[0].courage
	var exp := b3.resolve_losses(16, 0, 0, 0, 4 * (mv - 1) + 1, 2, mv, cour, 0)
	print("  ranks morale: mv %d, %d morale damage on a front rank of 4 -> %s" % [mv, 4 * (mv - 1) + 1, exp])
	ok(exp.deserted >= 1 and exp.count <= 15, "ranks: just over the front rank's morale threshold makes a front creature desert")
	ok(Battle.front_rank(1) == 0 and Battle.front_rank(5) == 0 and Battle.front_rank(6) == 3 and Battle.front_rank(10) == 4 and Battle.front_rank(17) == 5, "front rank = ceil(sqrt(n)), none at 5 or fewer")
	var b5 := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": Units.key("alpha", 3, 0, ""), "count": 3}]}, {"name": "B", "stacks": [{"key": dw, "count": 1}]}]})
	var r5 := b5.deal_damage(b5.stacks[0], 9, 0)
	ok(r5.killed == 0 and b5.phys_cap(b5.stacks[0]) == 9, "3 Trolls are all back rank: hold 3 x 3 = 9 (killed %d, cap %d)" % [r5.killed, b5.phys_cap(b5.stacks[0])])
	Battle._mode = "standard"
