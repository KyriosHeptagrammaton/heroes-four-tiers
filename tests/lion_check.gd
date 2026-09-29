extends RefCounted
var failed := false
func run(_root) -> void:
	var b := Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 2, 0, ""), "count": 9}]}]})
	var lion = b.stacks[1]
	var bers = b.stacks[0]
	var n := b.hit_numbers(lion, bers, {"average": true})
	print("lion morale ", lion.morale_val, " avg hit: total ", n.total, " -> mor ", n.mor, " phys ", n.phys, " mult ", n.mult)
	var base_mor := U.jr(n.total * D.CFG.moraleShare)
	failed = n.mor != base_mor + lion.morale_val
	print("lion_check ", "FAIL" if failed else "PASS")
