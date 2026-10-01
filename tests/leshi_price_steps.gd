extends RefCounted
var failed := false
func run(_root) -> void:
	var t := {"faction": "gamma", "pool": {"3": World.growth({"faction": "gamma"}, 3)}, "extra": {"3": 0}}
	var g: int = D.CFG.growth["3"]
	var pool: int = t.pool["3"]
	var unit := Units.base_price("gamma", 3)
	var p_pool := World.price_for(t, 3, pool)
	var p_next := World.price_for(t, 3, pool * 2) - p_pool
	var p_after := World.price_for(t, 3, pool * 3) - p_pool - p_next
	var p_5th := World.price_for(t, 3, pool * 6) - World.price_for(t, 3, pool * 5)
	print("Leshi weekly %d at %d = %d; next %d cost %d (x4 each = %d); next %d cost %d (x6); 5th batch %d (x26)" % [pool, unit, p_pool, pool, p_next, U.jr(unit * 4), pool, p_after, p_5th])
	failed = pool != 2 * g or p_next != U.jr(pool * unit * 4) or p_after != U.jr(pool * unit * 6) or p_5th != U.jr(pool * unit * 26)
	var at := {"faction": "alpha", "pool": {"3": World.growth({"faction": "alpha"}, 3)}, "extra": {"3": 0}}
	var ap: int = at.pool["3"]
	var a2 := World.price_for(at, 3, ap * 2) - World.price_for(at, 3, ap)
	print("Troll: weekly %d, next batch costs %d (x2)" % [ap, a2])
	failed = failed or a2 != U.jr(ap * Units.base_price("alpha", 3) * 2)
	print("leshi_price_steps ", "FAIL" if failed else "PASS")
