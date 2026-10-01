extends RefCounted
var failed := false
func run(_root) -> void:
	var t := {"faction": "gamma", "pool": {"3": World.growth({"faction": "gamma"}, 3)}, "extra": {"3": 0}}
	var g: int = D.CFG.growth["3"]
	var pool: int = t.pool["3"]
	var unit := Units.base_price("gamma", 3)
	var p_pool := World.price_for(t, 3, pool)
	var p_next := World.price_for(t, 3, pool + g) - p_pool
	var p_after := World.price_for(t, 3, pool + 2 * g) - p_pool - p_next
	print("normal growth %d, Leshi weekly pool %d at %d each = %d; next %d cost %d (x2); next %d cost %d (x3)" % [g, pool, unit, p_pool, g, p_next, g, p_after])
	failed = pool != 2 * g or p_next != U.jr(g * unit * 2) or p_after != U.jr(g * unit * 3)
	print("leshi_price_steps ", "FAIL" if failed else "PASS")
