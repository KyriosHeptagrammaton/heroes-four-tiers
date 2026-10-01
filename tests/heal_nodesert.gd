extends RefCounted
var failed := false
func run(_root) -> void:
	var DR := Units.key("delta", 3, 0, "")
	var bh := Battle.new({"seed": 5, "probe": true, "sides": [{"name": "A", "stacks": [{"key": DR, "count": 6}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]}, {"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
	var dr = bh.stacks[0]; var ally = bh.stacks[1]
	ally.phys = 2
	ally.mor = 50
	var cap: int = ally.count * Battle.cap(ally.morale_val)
	bh.do_heal(dr, ally)
	print("heal: count %d, deserters %d, morale damage %d (cap %d), health damage %d" % [ally.count, ally.deserters, ally.mor, cap, ally.phys])
	failed = ally.deserters != 0 or ally.mor != 90
	print("heal_nodesert ", "FAIL" if failed else "PASS")
